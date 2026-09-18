#!/usr/bin/env python3
"""把研究词表写入 research_lexemes（字典 §6）。

数据来源（两份文件共同构成唯一真源，App 端读的是同两份）：
- PinYintone/Resources/Corpus/lexemes.json         —— 汉字、拼音、声调（App 运行用）
- PinYintone/Resources/Corpus/research_lexicon.json —— 版本编号与研究元数据

规则：
- 声调写入前**必须**经 tone_coding 换算（轻声 5 → 0），否则 3 个轻声词会写错。
- **approved 的词条必须齐备** target_realization / source_detail /
  reference_audio_version / reviewed_at，缺一即拒绝写入——不能让未核实的词条
  以 approved 身份进库。
- 幂等：同一 lexeme_version_id 已存在则跳过，**不覆盖**已冻结的词条。
  改动内容须在 research_lexicon.json 里新建 lexemeVersionID。

用法：python3 scripts/seed_lexicon.py [--dry-run]
"""
import argparse
import json
import os
import sys
from datetime import datetime

sys.path.insert(0, os.path.dirname(os.path.dirname(os.path.abspath(__file__))))

from app import research_models  # noqa: E402
from app.database import SessionLocal  # noqa: E402
from app.tone_coding import citation_tones_from_internal  # noqa: E402

REPO = os.path.dirname(os.path.dirname(os.path.dirname(os.path.abspath(__file__))))
CORPUS = os.path.join(REPO, "PinYintone", "Resources", "Corpus")
REQUIRED_WHEN_APPROVED = ("targetRealization", "sourceDetail",
                          "referenceAudioVersion", "reviewedAt")


def build_rows():
    """读两份源文件，产出待写入的行。任何不一致都直接报错，不猜测。"""
    with open(os.path.join(CORPUS, "lexemes.json"), encoding="utf-8") as f:
        corpus = {x["id"]: x for x in json.load(f)}
    with open(os.path.join(CORPUS, "research_lexicon.json"), encoding="utf-8") as f:
        lexicon = json.load(f)

    version = lexicon["lexiconVersion"]
    rows, problems = [], []
    for e in lexicon["entries"]:
        lid = e["lexemeID"]
        if lid not in corpus:
            problems.append(f"{lid}: research_lexicon 有，但 lexemes.json 里没有")
            continue
        if e["reviewStatus"] == "approved":
            missing = [k for k in REQUIRED_WHEN_APPROVED if not e.get(k)]
            if missing:
                problems.append(f"{lid}: 标记为 approved 但缺 {missing}——未核实不得以 approved 进库")
                continue
        c = corpus[lid]
        rows.append(dict(
            lexeme_version_id=e["lexemeVersionID"],
            lexeme_id=lid,
            lexicon_version=version,
            hanzi=c["hanzi"],
            pinyin=c["pinyin"],
            citation_tones=citation_tones_from_internal(c["tones"]),
            target_realization=e.get("targetRealization"),
            source_type=e["sourceType"],
            source_detail=e.get("sourceDetail"),
            reference_audio_version=e.get("referenceAudioVersion"),
            reference_source=e["referenceSource"],
            reference_generator=e.get("referenceGenerator"),
            teacher_hint_version=e.get("teacherHintVersion"),
            teacher_hint_text=e.get("teacherHintText"),
            review_status=e["reviewStatus"],
            reviewed_at=(datetime.fromisoformat(e["reviewedAt"])
                         if e.get("reviewedAt") else None),
        ))
    missing_in_lexicon = set(corpus) - {e["lexemeID"] for e in lexicon["entries"]}
    for lid in sorted(missing_in_lexicon):
        problems.append(f"{lid}: lexemes.json 有，但 research_lexicon 里没有版本编号")
    return version, rows, problems


def main() -> int:
    p = argparse.ArgumentParser()
    p.add_argument("--dry-run", action="store_true", help="只校验，不写库")
    args = p.parse_args()

    version, rows, problems = build_rows()
    if problems:
        print("拒绝写入，源文件不一致：", file=sys.stderr)
        for x in problems:
            print("  -", x, file=sys.stderr)
        return 1

    pending = sum(1 for r in rows if r["review_status"] != "approved")
    print(f"词表 {version}：{len(rows)} 条，其中未核对 {pending} 条")
    if pending:
        print(f"  ⚠ 未核对词条**不得用于正式采集**（字典 §6：正式训练词条须 approved）")
    if args.dry_run:
        return 0

    db = SessionLocal()
    inserted = 0
    try:
        for r in rows:
            if db.get(research_models.ResearchLexeme, r["lexeme_version_id"]) is not None:
                continue  # 不覆盖已冻结词条
            db.add(research_models.ResearchLexeme(**r))
            inserted += 1
        db.commit()
    finally:
        db.close()
    print(f"新增 {inserted} 条（已存在的版本保持不变）")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
