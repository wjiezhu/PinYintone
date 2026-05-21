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


@router.get("/class-code/verify/{code}", response_model=schemas.VerifyResponse)
def verify_class_code(code: str, db: Session = Depends(get_db)):
    exists = db.query(models.Teacher).filter(models.Teacher.class_code == code).first()
    return schemas.VerifyResponse(valid=exists is not None)


@router.post("/student/register")
def student_register(body: schemas.StudentRegisterRequest, db: Session = Depends(get_db)):
    user = db.get(models.User, body.deviceID)
    if user is None:
        user = models.User(device_id=body.deviceID, install_date=datetime.now(timezone.utc))
        db.add(user)
    user.nickname = body.nickname
    user.class_code = body.classCode
    user.role = body.role
    user.experiment_group = body.experimentGroup
    user.native_language = body.nativeLanguage
    db.commit()
    return {}


@router.put("/student/bind")
def student_bind(body: schemas.BindRequest, db: Session = Depends(get_db)):
    user = db.get(models.User, body.deviceID)
    if user is None:
        user = models.User(device_id=body.deviceID, role="student")
        db.add(user)
    user.class_code = body.classCode
    user.role = "student"
    db.commit()
    return {}
