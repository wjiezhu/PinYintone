"""新版研究数据上报（字段字典 research-data-1.0）。

两条贯穿全文件的约束：

1. **服务端校验不可由客户端校验替代**（字典 §2）。事件名、payload 字段、
   attempt_id 必填性都在这里再验一遍——客户端可能是旧版本，也可能被改过。
2. **幂等靠唯一约束**（字典 §8）。同一 event_id 重传只留一行，
   不靠客户端保证不重发。
"""
from datetime import datetime, timezone

from fastapi import APIRouter, Depends, HTTPException
from sqlalchemy.orm import Session

from .. import research_models, schemas
from ..database import get_db

router = APIRouter(tags=["research"])

# 字典 §8 事件白名单。扩展须同步递增字典版本，否则这里会拒收。
EVENT_NAMES = {
    "task_opened", "model_audio_started", "learner_audio_started",
    "feedback_displayed", "feedback_mode_changed", "history_opened",
    "operation_error", "crash_report_received",
}

# 必须携带 attempt_id 的事件
EVENTS_REQUIRING_ATTEMPT = {
    "learner_audio_started", "feedback_displayed", "feedback_mode_changed",
}

# 各事件允许的 payload 字段
ALLOWED_PAYLOAD_KEYS = {
    "task_opened": {"task_type"},
    "feedback_displayed": {"mode"},
    "feedback_mode_changed": {"from_mode", "to_mode"},
    "operation_error": {"stage", "error_code"},
    "crash_report_received": {"crash_occurred_at"},
    "model_audio_started": set(),
    "learner_audio_started": set(),
    "history_opened": set(),
}

ERROR_CODES = {
    "permission_denied", "no_signal", "signal_unusable", "network_unavailable",
    "timeout", "analysis_engine_error", "playback_error", "render_error",
    "advice_service_error", "unknown",
}


def _validate_event(e: schemas.ResearchEventDTO) -> None:
    if e.eventName not in EVENT_NAMES:
        raise HTTPException(400, f"未知事件名：{e.eventName}")
    if e.eventName in EVENTS_REQUIRING_ATTEMPT and not e.attemptID:
        raise HTTPException(400, f"{e.eventName} 必须携带 attemptID")
    allowed = ALLOWED_PAYLOAD_KEYS[e.eventName]
    extra = set(e.payload or {}) - allowed
    if extra:
        raise HTTPException(400, f"{e.eventName} 不允许的 payload 字段：{sorted(extra)}")
    if e.eventName == "operation_error":
        code = (e.payload or {}).get("error_code")
        if code not in ERROR_CODES:
            raise HTTPException(400, f"未定义的错误码：{code}")
    if e.sessionElapsedMs is not None and e.sessionElapsedMs < 0:
        raise HTTPException(400, "sessionElapsedMs 不得为负")


def _participant_or_404(db: Session, participant_id: str) -> research_models.ResearchParticipant:
    p = db.get(research_models.ResearchParticipant, participant_id)
    if p is None:
        raise HTTPException(404, "参与者不存在")
    return p


@router.post("/research/events")
def upload_events(body: schemas.ResearchEventBatch, db: Session = Depends(get_db)):
    """批量上报操作事件。返回实际新增行数，重复的按幂等丢弃。

    撤回同意后即便离线队列重传也不得入库（字典 §15：
    「离线重传也不能绕过同意状态校验」）——故每批都重新核对同意状态，
    不信任客户端上报时的状态快照。
    """
    participant = _participant_or_404(db, body.participantID)

    # 同意状态以**服务端**的最新一条同意事件为准
    latest = (
        db.query(research_models.ResearchConsentEvent)
        .filter(research_models.ResearchConsentEvent.participant_id == body.participantID)
        .order_by(research_models.ResearchConsentEvent.occurred_at.desc())
        .first()
    )
    if latest is None or latest.action != "granted":
        raise HTTPException(403, "该参与者当前无有效同意，拒绝接收研究事件")

    manifest = db.get(research_models.ResearchManifest, body.manifestID)
    if manifest is None:
        raise HTTPException(404, "配置不存在")

    now = datetime.now(timezone.utc)
    inserted = 0
    for e in body.events:
        _validate_event(e)
        # 幂等：已存在同一 event_id 则跳过，不更新已有行
        if db.get(research_models.ResearchInteractionEvent, e.eventID) is not None:
            continue
        db.add(research_models.ResearchInteractionEvent(
            event_id=e.eventID,
            participant_id=body.participantID,
            manifest_id=body.manifestID,
            session_id=e.sessionID,
            attempt_id=e.attemptID,
            lexeme_version_id=e.lexemeVersionID,
            event_name=e.eventName,
            occurred_at=e.occurredAt,
            received_at=now,
            session_elapsed_ms=e.sessionElapsedMs,
            ui_language=e.uiLanguage,
            payload=e.payload or {},
        ))
        inserted += 1
    db.commit()
    return {"received": len(body.events), "inserted": inserted}
