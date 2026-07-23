from datetime import datetime, timezone

from fastapi import APIRouter, Depends
from sqlalchemy.orm import Session

from .. import models, schemas
from ..database import get_db

router = APIRouter(prefix="/api/sync", tags=["sync"])


def _parse_ts(value: str) -> datetime:
    # 兼容 "...Z" 结尾的 ISO8601
    try:
        return datetime.fromisoformat(value.replace("Z", "+00:00"))
    except ValueError:
        return datetime.now(timezone.utc)


@router.post("/session")
def sync_session(dto: schemas.TrainingSessionDTO, db: Session = Depends(get_db)):
    obj = db.get(models.TrainingSession, dto.id)
    if obj is None:
        obj = models.TrainingSession(id=dto.id)
        db.add(obj)
    obj.device_id = dto.deviceID
    obj.class_code = dto.classCode
    obj.role = dto.role
    obj.group_assignment = dto.groupAssignment
    obj.lexeme_id = dto.lexemeID
    obj.dtw_score = dto.dtwScore
    obj.grade = dto.grade
    obj.attempt_number = dto.attemptNumber
    obj.timestamp = _parse_ts(dto.timestamp)
    obj.reference_type = dto.referenceType
    obj.voiced_frame_count = dto.voicedFrameCount
    obj.quality_flag = dto.qualityFlag
    obj.reference_switched = dto.referenceSwitchedDuringAttempt
    db.commit()
    return {}


@router.post("/aspiration")
def sync_aspiration(dto: schemas.AspirationAttemptDTO, db: Session = Depends(get_db)):
    obj = db.get(models.AspirationAttempt, dto.id)
    if obj is None:
        obj = models.AspirationAttempt(id=dto.id)
        db.add(obj)
    obj.device_id = dto.deviceID
    obj.class_code = dto.classCode
    obj.role = dto.role
    obj.target_word = dto.targetWord
    obj.trigger_rate = dto.triggerRate
    obj.passed = dto.passed
    obj.timestamp = _parse_ts(dto.timestamp)
    db.commit()
    return {}


@router.post("/freetext")
def sync_freetext(dto: schemas.FreeTextRecordDTO, db: Session = Depends(get_db)):
    obj = db.get(models.FreeTextRecord, dto.id)
    if obj is None:
        obj = models.FreeTextRecord(id=dto.id)
        db.add(obj)
    obj.device_id = dto.deviceID
    obj.class_code = dto.classCode
    obj.role = dto.role
    obj.original_text = dto.originalText
    obj.tokenized_word = dto.tokenizedWord
    obj.pinyin = dto.pinyin
    obj.tone_sequence = dto.toneSequence
    obj.f0_track = dto.f0Track
    obj.duration = dto.duration
    obj.timestamp = _parse_ts(dto.timestamp)
    db.commit()
    return {}
