"""声调编码换算：App 内部 ↔ 研究库。与 Swift 的 ResearchToneCoding 同一规则。

App 内部（Lexeme.tones、lexemes.json）用 5 表示轻声；
研究库（字典 §6 citation_tones）用 0。

差异是**静默**的——原样写入不会报错，只有取数时才发现值对不上，
而语料里有 3 个轻声词（告诉、清楚、休息）。两端各有测试互相对照。
"""

INTERNAL_NEUTRAL = 5
RESEARCH_NEUTRAL = 0


class ToneCodingError(ValueError):
    pass


def citation_tones_from_internal(tones: list[int]) -> list[int]:
    """App 内部声调序列 → 研究库 citation_tones。未知调值抛错，不静默丢弃也不猜测。"""
    if not tones:
        raise ToneCodingError("声调序列为空")
    out = []
    for t in tones:
        if 1 <= t <= 4:
            out.append(t)
        elif t == INTERNAL_NEUTRAL:
            out.append(RESEARCH_NEUTRAL)
        else:
            raise ToneCodingError(f"不支持的声调值：{t}")
    return out
