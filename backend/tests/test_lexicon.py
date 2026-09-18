"""研究词表种子与声调换算。"""
import json
import os

import pytest

from app.tone_coding import ToneCodingError, citation_tones_from_internal

CORPUS = os.path.join(os.path.dirname(os.path.dirname(os.path.dirname(
    os.path.abspath(__file__)))), "PinYintone", "Resources", "Corpus")


def test_neutral_tone_converted():
    assert citation_tones_from_internal([4, 5]) == [4, 0]   # 告诉
    assert citation_tones_from_internal([1, 5]) == [1, 0]   # 清楚


def test_regular_tones_unchanged():
    assert citation_tones_from_internal([1, 2, 3, 4]) == [1, 2, 3, 4]


def test_unknown_tone_raises_not_guesses():
    with pytest.raises(ToneCodingError):
        citation_tones_from_internal([1, 9])
    with pytest.raises(ToneCodingError):
        citation_tones_from_internal([0])      # 0 是研究库的轻声码，App 内部不合法
    with pytest.raises(ToneCodingError):
        citation_tones_from_internal([])


def test_whole_corpus_converts_and_no_five_survives():
    with open(os.path.join(CORPUS, "lexemes.json"), encoding="utf-8") as f:
        corpus = json.load(f)
    neutral = 0
    for x in corpus:
        out = citation_tones_from_internal(x["tones"])
        assert 5 not in out, f"{x['hanzi']} 转换后仍含 5"
        if 5 in x["tones"]:
            neutral += 1
    assert neutral > 0, "语料应含轻声词，否则没覆盖到关键路径"


def test_seed_rows_build_cleanly():
    from scripts.seed_lexicon import build_rows
    version, rows, problems = build_rows()
    assert problems == [], problems
    assert len(rows) == 20
    # 版本编号不是稳定编号
    assert all(r["lexeme_version_id"] != r["lexeme_id"] for r in rows)


def test_approved_without_required_fields_rejected(tmp_path, monkeypatch):
    """未核实的词条不得以 approved 身份进库。"""
    import scripts.seed_lexicon as seed
    with open(os.path.join(CORPUS, "research_lexicon.json"), encoding="utf-8") as f:
        lex = json.load(f)
    lex["entries"][0]["reviewStatus"] = "approved"   # 但 sourceDetail 等仍为 null
    fake = tmp_path / "Corpus"
    fake.mkdir()
    (fake / "research_lexicon.json").write_text(json.dumps(lex), encoding="utf-8")
    with open(os.path.join(CORPUS, "lexemes.json"), encoding="utf-8") as f:
        (fake / "lexemes.json").write_text(f.read(), encoding="utf-8")
    monkeypatch.setattr(seed, "CORPUS", str(fake))
    _, _, problems = seed.build_rows()
    assert any("approved" in p for p in problems)
