import csv
import io
from collections import Counter, defaultdict
from datetime import datetime, timezone

from fastapi import APIRouter, Depends, Header, HTTPException
from fastapi.responses import Response
from sqlalchemy.orm import Session

from .. import models, schemas, security
from ..corpus import hanzi_for, tones_for
from ..database import get_db

router = APIRouter(tags=["teacher"])

PASS_THRESHOLD = 0.5  # CLAUDE.md：归一化 DTW ≤ 0.5 通关


def _scored(sessions):
    """只保留**有发音成绩**的记录。

    technical_retry（没录上）的 dtw_score 是哨兵 -1，混进统计会双重出错：
    -1 会把班级均分拉低（DTW 越低越好 → 录音失败越多班级越"优秀"），
    且 -1 <= 0.5 会被算成通关。CLAUDE.md 禁令 9：技术失败不得计入发音成绩。
    """
    return [s for s in sessions
            if (s.result_status or "valid_result") != "technical_retry"]


def _passed(s) -> bool:
    """是否通关。**以 grade 为准，不要用 dtw_score 重算。**

    schema_version >= 5 起平调词走向闸门可以在 dtw_score <= 0.5 时仍判 fail，
    用分数重算会与学习者当时看到的结果不一致（"所见 ≠ 所评"）。
    更早的记录 grade 本就由分数派生，用 grade 判等价，故可跨版本统一。
    """
    if s.grade:
        return s.grade != "fail"
    return s.dtw_score <= PASS_THRESHOLD


APPLE_EPOCH = datetime(2001, 1, 1, tzinfo=timezone.utc)


def _apple_ts(dt: datetime | None) -> float | None:
    """转 Apple 参考时间(秒)，匹配 iOS JSONDecoder 默认 .deferredToDate。"""
    if dt is None:
        return None
    if dt.tzinfo is None:
        dt = dt.replace(tzinfo=timezone.utc)
    return (dt - APPLE_EPOCH).total_seconds()


def current_teacher(
    authorization: str | None = Header(default=None),
    db: Session = Depends(get_db),
) -> models.Teacher:
    if not authorization or not authorization.startswith("Bearer "):
        raise HTTPException(status_code=401, detail="missing bearer token")
    try:
        teacher_id = security.decode_token(authorization.split(" ", 1)[1])
    except Exception:
        raise HTTPException(status_code=401, detail="invalid token")
    teacher = db.get(models.Teacher, teacher_id)
    if teacher is None:
        raise HTTPException(status_code=401, detail="unknown teacher")
    return teacher


def _class_sessions(db: Session, class_code: str) -> list[models.TrainingSession]:
    return (
        db.query(models.TrainingSession)
        .filter(models.TrainingSession.class_code == class_code)
        .all()
    )


@router.get("/teacher/class/summary", response_model=schemas.ClassSummary)
def class_summary(teacher: models.Teacher = Depends(current_teacher), db: Session = Depends(get_db)):
    sessions = _class_sessions(db, teacher.class_code)
    students = (
        db.query(models.User).filter(models.User.class_code == teacher.class_code).count()
    )
    scored = _scored(sessions)
    if scored:
        avg = sum(s.dtw_score for s in scored) / len(scored)
        pass_rate = sum(1 for s in scored if _passed(s)) / len(scored)
    else:
        avg, pass_rate = 0.0, 0.0
    return schemas.ClassSummary(
        totalStudents=students, weeklyNewStudents=None, avgDTW=avg, passRate=pass_rate
    )


@router.get("/teacher/class/tone-breakdown", response_model=schemas.ToneBreakdownData)
def tone_breakdown(teacher: models.Teacher = Depends(current_teacher), db: Session = Depends(get_db)):
    total = {1: 0, 2: 0, 3: 0, 4: 0}
    fails = {1: 0, 2: 0, 3: 0, 4: 0}
    for s in _scored(_class_sessions(db, teacher.class_code)):
        failed = not _passed(s)
        for tone in tones_for(s.lexeme_id):
            if tone in total:
                total[tone] += 1
                if failed:
                    fails[tone] += 1
    items = [
        schemas.ToneErrorItem(
            toneType=f"T{t}",
            errorRate=(fails[t] / total[t]) if total[t] else 0.0,
        )
        for t in (1, 2, 3, 4)
    ]
    return schemas.ToneBreakdownData(items=items)


@router.get("/teacher/students", response_model=list[schemas.StudentRowData])
def students(teacher: models.Teacher = Depends(current_teacher), db: Session = Depends(get_db)):
    sessions = _class_sessions(db, teacher.class_code)
    by_device: dict[str, list[models.TrainingSession]] = defaultdict(list)
    for s in sessions:
        by_device[s.device_id].append(s)

    nick = {
        u.device_id: u.nickname
        for u in db.query(models.User).filter(models.User.class_code == teacher.class_code).all()
    }

    rows: list[schemas.StudentRowData] = []
    for device_id, items in by_device.items():
        items.sort(key=lambda s: s.timestamp)
        recent = _scored(items)[-10:]
        recent_pass = (sum(1 for s in recent if _passed(s)) / len(recent)) if recent else 0.0
        rows.append(
            schemas.StudentRowData(
                id=device_id,
                nickname=nick.get(device_id),
                totalSessions=len(items),
                recentPassRate=recent_pass,
                lastActiveAt=_apple_ts(items[-1].timestamp),
            )
        )
    rows.sort(key=lambda r: r.lastActiveAt or 0, reverse=True)
    return rows


@router.get("/teacher/students/{device_id}", response_model=schemas.StudentDetailData)
def student_detail(
    device_id: str,
    teacher: models.Teacher = Depends(current_teacher),
    db: Session = Depends(get_db),
):
    items = (
        db.query(models.TrainingSession)
        .filter(
            models.TrainingSession.class_code == teacher.class_code,
            models.TrainingSession.device_id == device_id,
        )
        .order_by(models.TrainingSession.timestamp)
        .all()
    )
    scored = _scored(items)
    fails = Counter(s.lexeme_id for s in scored if not _passed(s))
    return schemas.StudentDetailData(
        deviceID=device_id,
        # 只画有成绩的点：哨兵 -1 画出来是个"突然满分"的尖峰
        dtwTimeSeries=[s.dtw_score for s in scored],
        errorWords=[hanzi_for(lex) for lex, _ in fails.most_common(5)],
    )


@router.get("/teacher/export/csv")
def export_csv(teacher: models.Teacher = Depends(current_teacher), db: Session = Depends(get_db)):
    out = io.StringIO()
    writer = csv.writer(out)
    # presentation_order 仅历史记录有值（A/B 取消前），schema_version >= 3 为空。
    # feedback_mode 各版本都有值但语义不同：v1/v2 是随机分配的实验条件，
    # v3 是学习者自选的显示模式（裸测为空）——导出后不可混在一起分析。
    # 列集按档案 §8：原始长表 + 质量标记 + 阶段 + 尝试次数 + 应用版本。
    writer.writerow(
        ["device_id", "phase", "word_set_id", "feedback_mode", "presentation_order",
         "assessment_set_version", "lexeme_id", "dtw_score", "grade", "attempt",
         "result_status", "quality_flag", "schema_version", "app_version", "timestamp"]
    )
    for s in sorted(_class_sessions(db, teacher.class_code), key=lambda s: s.timestamp):
        writer.writerow(
            [s.device_id, s.phase, s.word_set_id,
             s.feedback_mode, s.presentation_order,
             s.assessment_set_version, s.lexeme_id, f"{s.dtw_score:.4f}",
             s.grade, s.attempt_number,
             s.result_status, s.quality_flag, s.schema_version, s.app_version,
             s.timestamp.isoformat()]
        )
    return Response(
        content=out.getvalue(),
        media_type="text/csv",
        headers={"Content-Disposition": "attachment; filename=pinyintone_class.csv"},
    )
