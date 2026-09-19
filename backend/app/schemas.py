from datetime import datetime, timezone
"""Pydantic 模型。字段名严格对齐 iOS 端 JSON（camelCase / 特定大小写），
确保与 Swift Codable 直接互通，不做别名转换。"""
from typing import Annotated, Optional

from pydantic import AfterValidator, BaseModel, BeforeValidator, PlainSerializer


# ───────────── Auth ─────────────

class TeacherRegisterRequest(BaseModel):
    email: str
    password: str
    name: str


class TeacherRegisterResponse(BaseModel):
    classCode: str
    token: str
    teacherID: int


class TeacherLoginRequest(BaseModel):
    email: str
    password: str


class TeacherLoginResponse(BaseModel):
    token: str
    teacherID: int
    classCode: str


class StudentRegisterRequest(BaseModel):
    deviceID: str
    role: str
    appleUserID: Optional[str] = None       # Sign in with Apple 稳定标识
    spokenLanguages: Optional[list[str]] = None  # 会说的语言（多选，母语迁移分析）
    experimentGroup: Optional[str] = None   # 历史兼容字段，服务端分配，客户端值忽略
    nickname: Optional[str] = None
    classCode: Optional[str] = None
    teacherEmail: Optional[str] = None
    teacherToken: Optional[str] = None
    nativeLanguage: Optional[str] = None
    # 客户端用 Apple 参考时间(数字)编码，服务端忽略并以 now() 入库
    registeredAt: Optional[float] = None


class StudentRegisterResponse(BaseModel):
    """空响应：后端已不再下发任何实验分组字段（A/B 已取消）。"""

# ───────────── Sync（上行 DTO）─────────────

class TrainingSessionDTO(BaseModel):
    id: str
    deviceID: str
    classCode: Optional[str] = None
    role: str
    groupAssignment: str
    lexemeID: str
    dtwScore: float
    grade: str
    attemptNumber: int
    timestamp: str   # ISO8601
    # 诊断埋点（旧版客户端不带这些字段，故全部可选）
    referenceType: Optional[str] = None
    voicedFrameCount: Optional[int] = None
    qualityFlag: Optional[bool] = None
    referenceSwitchedDuringAttempt: Optional[bool] = None
    # 研究字段（升级需求 §3.1 / §3.2；旧版客户端不带，故可选）
    phase: Optional[str] = None
    wordSetID: Optional[str] = None
    presentationOrder: Optional[str] = None
    assessmentSetVersion: Optional[str] = None
    # 记录语义与版本（升级需求 §6.1 / §6.2；同样可选，保证旧客户端兼容）
    feedbackMode: Optional[str] = None
    resultStatus: Optional[str] = None
    failureReason: Optional[str] = None
    schemaVersion: Optional[int] = None
    appVersion: Optional[str] = None


class AspirationAttemptDTO(BaseModel):
    id: str
    deviceID: str
    classCode: Optional[str] = None
    role: str
    targetWord: str
    triggerRate: float
    passed: bool
    timestamp: str
    phase: Optional[str] = None
    schemaVersion: Optional[int] = None
    appVersion: Optional[str] = None


class FreeTextRecordDTO(BaseModel):
    id: str
    deviceID: str
    classCode: Optional[str] = None
    role: str
    originalText: str
    tokenizedWord: str
    pinyin: str
    toneSequence: list[int] = []
    f0Track: list[float] = []
    duration: float
    timestamp: str
    phase: Optional[str] = None
    schemaVersion: Optional[int] = None
    appVersion: Optional[str] = None


# ───────────── Teacher Dashboard（下行响应）─────────────

class ClassSummary(BaseModel):
    totalStudents: int
    weeklyNewStudents: Optional[int] = None
    avgDTW: float
    passRate: float


class ToneErrorItem(BaseModel):
    toneType: str
    errorRate: float


class ToneBreakdownData(BaseModel):
    items: list[ToneErrorItem] = []


class StudentRowData(BaseModel):
    id: str                                  # deviceID
    nickname: Optional[str] = None
    totalSessions: int
    recentPassRate: float
    # Apple 参考时间(秒)，匹配 iOS JSONDecoder 默认 .deferredToDate
    lastActiveAt: Optional[float] = None


class StudentDetailData(BaseModel):
    deviceID: str
    dtwTimeSeries: list[float] = []
    errorWords: list[str] = []


# ---------------- 新版研究上报（字段字典 research-data-1.0） ----------------
#
# 时间字段的契约（**研究接口专用，旧接口不受影响**）：
# - 入参必须是**带时区**的 ISO8601 字符串。**拒收数字**。
#   iOS 默认 JSONEncoder 把日期编码成自 2001-01-01 起的秒数，而 pydantic 会把数字
#   当自 1970-01-01 起的秒数解读——差 31 年。实测曾返回 200 并把 2026-09-19 存成
#   1995-09-19，导出因全部落在窗口外而为空，且无任何报错。拒收让它大声失败。
# - 拒收不带时区的串：按服务器本地时区猜会让采集窗口边界漂移。
# - 出参一律输出带时区的 UTC：SQLite 读回会丢 tzinfo，客户端的 ISO8601 解码器
#   要求时区，不补上就会解码失败、研究配置静默拿不到。

def _reject_numeric_time(v):
    if isinstance(v, (int, float)) and not isinstance(v, bool):
        raise ValueError(
            "研究接口要求 ISO8601 字符串时间，收到数字。"
            "很可能是 iOS 默认的 2001 基准秒数——按 1970 解读会错 31 年")
    return v


def _require_tz(v: datetime) -> datetime:
    if v.tzinfo is None:
        raise ValueError("研究接口要求带时区的时间（如 2026-09-19T01:00:00Z）")
    return v


def _as_utc_iso(v: datetime) -> str:
    return (v if v.tzinfo else v.replace(tzinfo=timezone.utc)).isoformat()


IsoDatetime = Annotated[datetime, BeforeValidator(_reject_numeric_time),
                        AfterValidator(_require_tz)]
OutDatetime = Annotated[datetime, PlainSerializer(_as_utc_iso, return_type=str)]


class ResearchEventDTO(BaseModel):
    """单条操作事件。字段名与客户端 Codable 对齐（camelCase）。"""
    eventID: str
    sessionID: str
    attemptID: str | None = None
    lexemeVersionID: str | None = None
    eventName: str
    occurredAt: IsoDatetime
    sessionElapsedMs: int | None = None
    uiLanguage: str
    payload: dict[str, str] = {}


class ResearchEventBatch(BaseModel):
    participantID: str
    manifestID: str
    events: list[ResearchEventDTO]


class ResearchEnrollRequest(BaseModel):
    """纳入研究。internalUserID 是业务账号键，**不是** Apple 标识。"""
    internalUserID: str
    manifestID: str
    consentVersion: str
    consentLanguage: str
    consentOccurredAt: IsoDatetime
    recruitmentSource: str = "unknown"
    priorUseStatus: str = "unknown"
    priorUseEvidence: str = "insufficient"
    isTest: bool = False


class ResearchEnrollResponse(BaseModel):
    participantID: str
    studyID: str
    alreadyEnrolled: bool


class ResearchWithdrawRequest(BaseModel):
    participantID: str
    consentVersion: str
    consentLanguage: str
    occurredAt: IsoDatetime


class SurveyAnswerDTO(BaseModel):
    questionID: str
    state: str                     # answered / skipped / not_answered
    optionCodes: list[str] | None = None
    textValue: str | None = None
    answeredAt: IsoDatetime | None = None


class SurveyOutcomeDTO(BaseModel):
    formKey: str
    formVersion: str
    translationVersion: str
    language: str
    answers: list[SurveyAnswerDTO]
    status: str                    # declined / partial / complete
    startedAt: IsoDatetime | None = None
    submittedAt: IsoDatetime | None = None


class SurveyUploadRequest(BaseModel):
    participantID: str
    manifestID: str
    outcome: SurveyOutcomeDTO
    timingClass: str
    qualifyingAttemptsAtInvite: int = 0


class ActiveManifestResponse(BaseModel):
    manifestID: str
    studyID: str
    collectionStartAt: OutDatetime
    collectionEndAt: OutDatetime
    postTriggerCount: int
    consentVersion: str
    surveyVersion: str


class ResearchAttemptDTO(BaseModel):
    attemptID: str
    sessionID: str
    taskType: str
    lexemeVersionID: str | None = None
    retryOfAttemptID: str | None = None
    priorPracticeCount: int | None = None
    startedAt: IsoDatetime
    status: str
    finishedAt: IsoDatetime | None = None
    recordingDurationMs: int | None = None
    analysisDurationMs: int | None = None
    signalStatus: str
    metricValue: float | None = None
    passed: bool | None = None
    errorCode: str | None = None
    resultDisplayedAt: IsoDatetime | None = None
    timeQuality: str


class ResearchAttemptBatch(BaseModel):
    participantID: str
    manifestID: str
    attempts: list[ResearchAttemptDTO]


class IssueReportRequest(BaseModel):
    reportID: str
    participantID: str
    manifestID: str
    attemptID: str | None = None
    submittedAt: IsoDatetime
    category: str
    detail: str | None = None
    relatedEventID: str | None = None
