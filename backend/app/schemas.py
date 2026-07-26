"""Pydantic 模型。字段名严格对齐 iOS 端 JSON（camelCase / 特定大小写），
确保与 Swift Codable 直接互通，不做别名转换。"""
from typing import Optional

from pydantic import BaseModel


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
    experimentGroup: Optional[str] = None   # 服务端均衡分配，客户端值忽略
    nickname: Optional[str] = None
    classCode: Optional[str] = None
    teacherEmail: Optional[str] = None
    teacherToken: Optional[str] = None
    nativeLanguage: Optional[str] = None
    # 客户端用 Apple 参考时间(数字)编码，服务端忽略并以 now() 入库
    registeredAt: Optional[float] = None


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


class AspirationAttemptDTO(BaseModel):
    id: str
    deviceID: str
    classCode: Optional[str] = None
    role: str
    targetWord: str
    triggerRate: float
    passed: bool
    timestamp: str


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


# ───────────── Teacher Dashboard（下行响应）─────────────

class ClassSummary(BaseModel):
    totalStudents: int
    weeklyNewStudents: Optional[int] = None
    avgDTW: float
    passRate: float


class GroupBar(BaseModel):
    group: str
    avgDTW: float
    count: int


class GroupComparisonData(BaseModel):
    bars: list[GroupBar] = []


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
