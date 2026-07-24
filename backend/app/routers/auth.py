import random
from datetime import datetime, timezone

from fastapi import APIRouter, Depends, HTTPException
from sqlalchemy.orm import Session

from .. import models, schemas, security
from ..database import get_db

router = APIRouter(tags=["auth"])


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


@router.post("/student/register")
def student_register(body: schemas.StudentRegisterRequest, db: Session = Depends(get_db)):
    user = db.get(models.User, body.deviceID)
    if user is None:
        user = models.User(device_id=body.deviceID, install_date=datetime.now(timezone.utc))
        db.add(user)
    # 均衡随机分组：仅在该设备尚无有效分组时分配（幂等：重装/重注册不变组）
    if user.experiment_group not in ("staticColor", "dynamicF0"):
        # Sign in with Apple 跨设备幂等：同一 Apple ID 在其它设备已有分组 → 直接继承，
        # 避免同一被试在两台设备被分进不同组污染 A/B 数据
        prior = None
        if body.appleUserID:
            prior = (
                db.query(models.User)
                .filter(
                    models.User.apple_user_id == body.appleUserID,
                    models.User.experiment_group.in_(["staticColor", "dynamicF0"]),
                )
                .first()
            )
        if prior is not None:
            user.experiment_group = prior.experiment_group
        else:
            a = db.query(models.User).filter(models.User.experiment_group == "staticColor").count()
            b = db.query(models.User).filter(models.User.experiment_group == "dynamicF0").count()
            if a < b:
                user.experiment_group = "staticColor"
            elif b < a:
                user.experiment_group = "dynamicF0"
            else:
                user.experiment_group = random.choice(["staticColor", "dynamicF0"])
    if body.appleUserID:
        user.apple_user_id = body.appleUserID
    user.nickname = body.nickname
    user.role = "student"
    user.class_code = None
    user.native_language = body.nativeLanguage
    db.commit()
    return {"experimentGroup": user.experiment_group}


@router.delete("/student/account")
def student_delete_account(deviceID: str, appleUserID: str | None = None,
                           db: Session = Depends(get_db)):
    """彻底删除该用户及其全部训练数据（App Store 审核指南 5.1.1(v) 强制要求）。

    同时也是研究伦理上的「撤回同意」通道：被试有权随时退出并删除其数据。
    若提供 appleUserID，则一并清除该 Apple 账户在其它设备上的记录，
    避免用户在一台设备上"删除"后数据仍留存在另一台设备的记录里。
    """
    device_ids = {deviceID}
    if appleUserID:
        rows = db.query(models.User.device_id).filter(
            models.User.apple_user_id == appleUserID).all()
        device_ids.update(r[0] for r in rows)

    ids = list(device_ids)
    deleted = {}
    for model, key in (
        (models.TrainingSession, "training_sessions"),
        (models.AspirationAttempt, "aspiration_attempts"),
        (models.FreeTextRecord, "freetext_records"),
        (models.User, "users"),
    ):
        deleted[key] = db.query(model).filter(
            model.device_id.in_(ids)).delete(synchronize_session=False)
    db.commit()
    return {"deleted": deleted, "deviceIDs": ids}


