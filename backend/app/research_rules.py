"""研究纳入与同意的判定规则。接口（routers/research.py）与导出（scripts/export_research.py）
**共用同一份实现**。

分成独立模块的原因：这两处此前各写各的「最新同意」「背景是否合格」，
而本项目已经吃过「同一条规则两处实现、只改了一处」的亏（技术失败哨兵在
export.sql 里筛了、teacher.py 里漏了）。接口放进来的人和导出算进去的人必须是同一批。
"""
from datetime import datetime, timezone

from . import research_models as m

# 纳入条件（需求 R01，研究者已确认）：成年、国籍含 MA、课程阶段 hsk1–3。
# 语言背景只作描述，不作排除条件；本轮**不区分新旧用户**。
ELIGIBLE_NATIONALITY = "MA"
ELIGIBLE_STAGES = {"hsk1", "hsk2", "hsk3"}

# App 内可选的界面语言。研究记录里的语言必须是用户**在 App 内选择并实际看到**的
# 这四种之一——收到 en_US、ar-MA 之类说明客户端把系统区域当成了界面语言。
UI_LANGUAGES = {"zh", "en", "fr", "ar"}


def aware(dt: datetime) -> datetime:
    """SQLite 读回会丢 tzinfo（Postgres 不会）；统一成带时区再比较。"""
    return dt if dt.tzinfo else dt.replace(tzinfo=timezone.utc)


def latest_consent(db, participant_id: str):
    """该参与者最新一条同意事件。

    以**服务端接收顺序**为准，客户端发生时间只作并列时的次序：
    撤回必然晚于同意到达服务端，而客户端时钟可能被改动或漂移——
    按客户端时间排会让一条「时间更早」的撤回排到同意前面，等于没撤。
    """
    return (db.query(m.ResearchConsentEvent)
            .filter(m.ResearchConsentEvent.participant_id == participant_id)
            .order_by(m.ResearchConsentEvent.received_at.desc(),
                      m.ResearchConsentEvent.occurred_at.desc())
            .first())


def has_active_consent(db, participant_id: str) -> bool:
    latest = latest_consent(db, participant_id)
    return latest is not None and latest.action == "granted"


def background_answers(db, participant_id: str):
    """返回 (背景问卷实例, {question_id: answer})；没有实例时为 (None, {})。"""
    inst = (db.query(m.ResearchSurveyInstance)
            .filter_by(participant_id=participant_id, form_key="background_v1")
            .order_by(m.ResearchSurveyInstance.invited_at.desc())
            .first())
    if inst is None:
        return None, {}
    answers = {a.question_id: a for a in
               db.query(m.ResearchSurveyAnswer)
               .filter_by(survey_instance_id=inst.survey_instance_id)}
    return inst, answers


def judge_background(answers: dict) -> tuple[bool, str]:
    """按答案判纳入。**缺失或未知不推定满足**：没答、跳过、prefer_not 一律不满足。

    返回 (是否合格, 不合格原因)。原因取值与 participants.exclusion_reason 一致。
    """
    def codes(q):
        a = answers.get(q)
        return set(a.option_codes or []) if a and a.answer_state == "answered" else set()

    if "adult" not in codes("B01"):
        return False, "age"
    if ELIGIBLE_NATIONALITY not in codes("B02"):
        return False, "nationality"
    if not (codes("B03") & ELIGIBLE_STAGES):
        return False, "course_stage"
    return True, ""


def background_eligible(db, participant_id: str) -> tuple[bool, str]:
    """该参与者的背景表是否已**最终提交**且符合纳入条件。

    只认最终状态（complete / partial）：仅「已邀请」「稍后填写」的实例没有答案，
    不能据此判合格，也不能判不合格——归为 no_background。
    """
    inst, answers = background_answers(db, participant_id)
    if inst is None or inst.status not in ("complete", "partial"):
        return False, "no_background"
    return judge_background(answers)
