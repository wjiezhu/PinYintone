"""研究数据写入前的服务端校验。

字典 §2 要求「客户端校验不能替代服务端校验」。本模块是客户端之外的第二层：
即便客户端漏了转换或被旧版本绕过，错误数据也进不了研究库。

**这一层存在的理由很具体**：本项目已经两次因为「每处都记得加条件」而出错
（技术失败哨兵在 export.sql 筛了、teacher.py 漏了）。约定靠不住，校验靠得住。
"""

from typing import Iterable

# 字典 §6：citation_tones 按音节排列，1/2/3/4，**0 表示轻声**。
# ⚠ App 内部用 5 表示轻声，上报前必须换算；此处收到 5 一律拒绝，
#   否则会静默写入字典里不存在的值，取数时才发现。
VALID_CITATION_TONES = {0, 1, 2, 3, 4}
APP_INTERNAL_NEUTRAL = 5


class ResearchValidationError(ValueError):
    """校验失败。错误信息只描述问题，不回显可能含个人信息的原始载荷。"""


def validate_citation_tones(tones: Iterable) -> list[int]:
    """校验并返回 citation_tones。

    - 空序列拒绝（字典要求无观测值写 NULL，而不是空数组）
    - 收到 5 时给出明确提示：这是 App 内部编码，未做换算
    - 其余越界值一律拒绝，不静默丢弃、不猜测
    """
    items = list(tones) if tones is not None else []
    if not items:
        raise ResearchValidationError(
            "citation_tones 不能为空；无观测值应写 NULL 而非空数组")
    out = []
    for t in items:
        if not isinstance(t, int) or isinstance(t, bool):
            raise ResearchValidationError(f"citation_tones 含非整数值：{type(t).__name__}")
        if t == APP_INTERNAL_NEUTRAL:
            raise ResearchValidationError(
                "citation_tones 含 5：这是 App 内部的轻声编码，"
                "研究库轻声为 0，上报前须经 ResearchToneCoding 换算")
        if t not in VALID_CITATION_TONES:
            raise ResearchValidationError(f"citation_tones 含非法调值：{t}（允许 0–4）")
        out.append(t)
    return out


def validate_metric_value(value, *, status: str):
    """校验评分指标。

    字典 §2 / §7：无观测值写 NULL，**不写 0、空字符串或虚构默认值**。
    旧表曾用 -1 哨兵绕开 NOT NULL 约束，新表 metric_value 本就可空，
    故哨兵值在此一律拒绝——否则 -1 会被当成「极好的成绩」参与统计
    （DTW 越低越好，这正是旧表出过的事故）。
    """
    if value is None:
        return None
    if value < 0:
        raise ResearchValidationError(
            f"metric_value 为负（{value}）：疑似旧表的哨兵值；"
            "无有效指标应写 NULL")
    if status in ("recording_failed", "analysis_failed", "cancelled") :
        raise ResearchValidationError(
            f"status={status} 时不应有 metric_value；失败记录写 NULL")
    return value
