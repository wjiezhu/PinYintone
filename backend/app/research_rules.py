"""研究纳入与同意的判定规则。接口（routers/research.py）与导出（scripts/export_research.py）
**共用同一份实现**。

分成独立模块的原因：这两处此前各写各的「最新同意」「背景是否合格」，
而本项目已经吃过「同一条规则两处实现、只改了一处」的亏（技术失败哨兵在
export.sql 里筛了、teacher.py 里漏了）。接口放进来的人和导出算进去的人必须是同一批。
"""
from datetime import datetime, timezone

from . import research_models as m

# 纳入条件以**参与者纳入时所用配置**的 eligibility_spec 为准，不在这里写死：
# - 第一轮（eligibility-2.0）：成年、国籍含 MA、课程阶段 hsk1–3。
# - 现场实测轮（eligibility-3.0，2026-10-28）：去掉国籍限制，国籍照常记录。
# 语言背景只作描述，不作排除条件；**不区分新旧用户**。
# 旧配置没有 spec 时按第一轮的规则判（那时规则就是这样）。
ELIGIBLE_NATIONALITY = "MA"
ELIGIBLE_STAGES = {"hsk1", "hsk2", "hsk3"}
FIRST_ROUND_SPEC = {"adult_required": True,
                    "nationality_any": [ELIGIBLE_NATIONALITY],
                    "course_stage_any": sorted(ELIGIBLE_STAGES)}

# App 内可选的界面语言。研究记录里的语言必须是用户**在 App 内选择并实际看到**的
# 这四种之一——收到 en_US、ar-MA 之类说明客户端把系统区域当成了界面语言。
UI_LANGUAGES = {"zh", "en", "fr", "ar", "es", "it"}


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


def spec_of(manifest) -> dict:
    """配置里的纳入规则；旧配置没有时按第一轮规则。"""
    spec = getattr(manifest, "eligibility_spec", None) if manifest is not None else None
    return spec or FIRST_ROUND_SPEC


def judge_background(answers: dict, spec: dict | None = None) -> tuple[bool, str]:
    """按答案判纳入。**缺失或未知不推定满足**：没答、跳过、prefer_not 一律不满足。

    `spec` 是配置的 eligibility_spec。`nationality_any` 为空或缺省 = 不限国籍
    （国籍题照常作答、照常保存，只是不参与判定）。

    返回 (是否合格, 不合格原因)。原因取值与 participants.exclusion_reason 一致。
    """
    spec = spec or FIRST_ROUND_SPEC

    def codes(q):
        a = answers.get(q)
        return set(a.option_codes or []) if a and a.answer_state == "answered" else set()

    if spec.get("adult_required", True) and "adult" not in codes("B01"):
        return False, "age"
    nationalities = set(spec.get("nationality_any") or [])
    if nationalities and not (codes("B02") & nationalities):
        return False, "nationality"
    stages = set(spec.get("course_stage_any") or [])
    if stages and not (codes("B03") & stages):
        return False, "course_stage"
    return True, ""


def describe_spec(spec: dict) -> str:
    """纳入规则的一句话描述，写进导出说明。"""
    parts = []
    if spec.get("adult_required", True):
        parts.append("成年")
    nat = spec.get("nationality_any") or []
    parts.append(f"国籍含 {'/'.join(nat)}" if nat else "不限国籍（国籍照常记录）")
    stages = spec.get("course_stage_any") or []
    if stages:
        parts.append(f"课程阶段 {'/'.join(sorted(stages))}")
    return "、".join(parts)


def background_eligible(db, participant_id: str, spec: dict | None = None) -> tuple[bool, str]:
    """该参与者的背景表是否已**最终提交**且符合纳入条件。

    只认最终状态（complete / partial）：仅「已邀请」「稍后填写」的实例没有答案，
    不能据此判合格，也不能判不合格——归为 no_background。
    """
    inst, answers = background_answers(db, participant_id)
    if inst is None or inst.status not in ("complete", "partial"):
        return False, "no_background"
    return judge_background(answers, spec)
