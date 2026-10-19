import logging
import uuid
from datetime import datetime, timezone

from fastapi import APIRouter, Depends, HTTPException
from sqlalchemy.orm import Session

from .. import accounts, identity, models, research_models, schemas, security
from ..config import settings
from ..database import get_db
from ..research_rules import latest_consent

router = APIRouter(tags=["auth"])
log = logging.getLogger("pinyintone.identity")


@router.post("/teacher/register", response_model=schemas.TeacherRegisterResponse)
def teacher_register(body: schemas.TeacherRegisterRequest, db: Session = Depends(get_db)):
    if db.query(models.Teacher).filter(models.Teacher.email == body.email).first():
        # iOS 据 detail 含 "email" 判定为邮箱已注册
        raise HTTPException(status_code=400, detail="email already registered")

    code = security.generate_class_code(db)
    teacher = models.Teacher(
        email=body.email,
        password_hash=security.hash_password(body.password),
        name=body.name,
        class_code=code,
    )
    db.add(teacher)
    db.commit()
    db.refresh(teacher)

    return schemas.TeacherRegisterResponse(
        classCode=teacher.class_code,
        token=security.create_access_token(teacher.id),
        teacherID=teacher.id,
    )


@router.post("/teacher/login", response_model=schemas.TeacherLoginResponse)
def teacher_login(body: schemas.TeacherLoginRequest, db: Session = Depends(get_db)):
    teacher = db.query(models.Teacher).filter(models.Teacher.email == body.email).first()
    if not teacher or not security.verify_password(body.password, teacher.password_hash):
        raise HTTPException(status_code=401, detail="invalid credentials")
    return schemas.TeacherLoginResponse(
        token=security.create_access_token(teacher.id),
        teacherID=teacher.id,
        classCode=teacher.class_code,
    )


@router.post("/student/register", response_model=schemas.StudentRegisterResponse)
def student_register(body: schemas.StudentRegisterRequest, db: Session = Depends(get_db)):
    """学生注册（按 deviceID 幂等建档）。

    已取消 A/B 分组：两种反馈显示方式由学习者自己在设置里选，
    不是随机分配的实验条件，因此这里**不再分配** counterbalance_index / experiment_group。
    两列在库中保留，只为让升级前写入的历史记录仍可读。
    """
    user = db.get(models.User, body.deviceID)
    # 登录身份以服务端验过签的凭证为准，不信客户端直接传的用户号（identity.py）
    login = identity.authenticate(body.provider, body.identityToken, body.appleUserID, user)
    if user is None:
        user = models.User(device_id=body.deviceID, install_date=datetime.now(timezone.utc))
        db.add(user)

    if login is not None:
        # 这台设备换了一个账号登录：先清掉上一个人的内部编号，
        # 否则新账号会被当成同一位研究参与者
        accounts.forget_previous_owner(user, login.provider, login.subject)
        user.auth_provider = login.provider
        user.auth_subject = login.subject
        # 历史列：Apple 登录同步写一份，便于回滚到旧后端
        user.apple_user_id = login.subject if login.provider == "apple" else None
        now = identity.utcnow()
        if login.how == "verified":
            user.auth_verified_at = now
        elif login.how == "legacy":
            user.legacy_login_at = now
    if body.spokenLanguages is not None:
        user.spoken_languages = body.spokenLanguages
    user.nickname = body.nickname
    user.role = "student"
    # 学生不绑定班级：classCode 恒为 None，数据进入"未绑定班级"池（CLAUDE.md 禁止事项 4）
    user.class_code = None
    user.native_language = body.nativeLanguage
    # 账号的稳定内部编号：同一登录身份的各设备行共用，研究纳入按它去重
    db.flush()
    accounts.ensure_account_id(db, user)
    db.commit()
    return schemas.StudentRegisterResponse()


@router.delete("/student/account")
def student_delete_account(deviceID: str, appleUserID: str | None = None,
                           db: Session = Depends(get_db)):
    """彻底删除该用户及其全部训练数据（App Store 审核指南 5.1.1(v) 强制要求）。

    同时也是研究伦理上的「撤回同意」通道：被试有权随时退出并删除其数据。
    同一登录身份 (provider, subject) 在其它设备上的记录一并清除，
    避免用户在一台设备上"删除"后数据仍留存在另一台设备的记录里。

    要删的身份取自这台设备行上记的登录身份，**不信客户端传的 appleUserID**——
    否则知道别人的用户号就能删掉别人的全部数据。appleUserID 只在设备行已不存在
    （或从未绑定身份）时作为旧版 iOS 的兼容入口，且受过渡开关约束。
    """
    device_ids = {deviceID}
    identities: set[tuple[str, str]] = set()
    user = db.get(models.User, deviceID)
    own = accounts.identity_of(user) if user is not None else None
    if own is not None:
        identities.add(own)
        if appleUserID and own != ("apple", appleUserID):
            log.warning("删除账号：appleUserID 与设备行的登录身份不一致，已忽略")
    elif appleUserID and settings.allow_legacy_unverified_apple:
        log.warning("删除账号：设备行没有登录身份，按过渡开关采信 appleUserID")
        identities.add(("apple", appleUserID))
    for provider, subject in identities:
        device_ids.update(u.device_id for u in accounts.users_with_identity(db, provider, subject))

    ids = list(device_ids)

    # 删除账号的人若在研究中，同时记一条「退出研究」。
    # 不删研究表里的行（去标识化资料的保留策略尚未审定，且导出本就排除退出者），
    # 但必须让服务端从此拒收该参与者的研究上传——否则账号没了，
    # 另一台设备上的离线队列还能继续往研究库里写。
    account_ids = {r[0] for r in db.query(models.User.account_id)
                   .filter(models.User.device_id.in_(ids)).all() if r[0]}
    identities.update((r[0], r[1]) for r in db.query(
        models.User.auth_provider, models.User.auth_subject)
        .filter(models.User.device_id.in_(ids)).all() if r[0] and r[1])
    now = datetime.now(timezone.utc)
    withdrawn = 0
    for im in (db.query(research_models.ResearchIdentityMap)
               .filter(research_models.ResearchIdentityMap.internal_user_id
                       .in_(account_ids | device_ids)).all()):
        latest = latest_consent(db, im.participant_id)
        if latest is None or latest.action != "granted":
            continue
        db.add(research_models.ResearchConsentEvent(
            consent_event_id=str(uuid.uuid4()),
            participant_id=im.participant_id,
            action="withdrawn",
            consent_version=latest.consent_version,
            language=latest.language,
            occurred_at=now,
            received_at=now,
        ))
        withdrawn += 1
    deleted = {}
    for model, key in (
        (models.TrainingSession, "training_sessions"),
        (models.AspirationAttempt, "aspiration_attempts"),
        (models.FreeTextRecord, "freetext_records"),
        (models.User, "users"),
    ):
        deleted[key] = db.query(model).filter(
            model.device_id.in_(ids)).delete(synchronize_session=False)
    # 账号没了，登录身份与内部编号的对应关系也一并删除
    for provider, subject in identities:
        db.query(models.AccountLink).filter(
            models.AccountLink.provider == provider,
            models.AccountLink.subject == subject).delete(synchronize_session=False)
    db.commit()
    return {"deleted": deleted, "deviceIDs": ids, "researchWithdrawn": withdrawn}


