#!/usr/bin/env python3
"""冻结一份研究配置（字典 §3 research_manifests）。

用法示例（所有值都必须显式给出，脚本不提供默认值）：

    python3 scripts/seed_manifest.py \
        --study-id pinyintone-2026-ma \
        --app-version 2.0 --build-number 12 \
        --lexicon-version lex-2026.09 --scoring-version scoring-v5 \
        --feedback-version fb-1.0 --advice-policy-version advice-1.0 \
        --survey-version survey-1.0 --consent-version consent-1.0 \
        --eligibility-version eligibility-1.0 \
        --collection-start 2026-10-01T00:00:00+00:00

为什么不给默认值：manifest 决定评分、词库、提示与问卷版本，
猜一个默认值会把数据归到错误的配置下，而这种错误在导出时极难发现。
`collection_start_at` 尤其如此——字典 §3 要求填**实际公开可用**的时点，
「不填预计日期」，所以必须由运行者在上线核实后手工给出。
"""
import argparse
import os
import sys
import uuid
from datetime import datetime, timedelta, timezone

sys.path.insert(0, os.path.dirname(os.path.dirname(os.path.abspath(__file__))))

from app import research_models  # noqa: E402
from app.database import SessionLocal  # noqa: E402

# 采集窗口：统一 14 天，左闭右开，**不是每位用户各 14 天**（字典 §3）
WINDOW_DAYS = 14


def main() -> int:
    p = argparse.ArgumentParser(description=__doc__,
                                formatter_class=argparse.RawDescriptionHelpFormatter)
    for name in ("study-id", "app-version", "build-number", "lexicon-version",
                 "scoring-version", "feedback-version", "advice-policy-version",
                 "survey-version", "consent-version", "eligibility-version"):
        p.add_argument(f"--{name}", required=True)
    p.add_argument("--collection-start", required=True,
                   help="新版在 App Store 实际公开可用的时点（ISO8601，带时区）。"
                        "必须是核实后的真实时间，不得填预计日期。")
    p.add_argument("--post-trigger-count", type=int, default=5,
                   help="研究者已确认为 5")
    p.add_argument("--reward-rule-version", default=None,
                   help="积分规则版本；留空则积分功能整体关闭。"
                        "已确定的规则见 docs/V2_DECISIONS.md 第 12 条："
                        "每词首次说对 +1 分，无其它得分方式，版本号 reward-1.0")
    args = p.parse_args()

    start = datetime.fromisoformat(args.collection_start)
    if start.tzinfo is None:
        print("错误：--collection-start 必须带时区，否则窗口边界会因服务器时区而漂移",
              file=sys.stderr)
        return 1
    end = start + timedelta(days=WINDOW_DAYS)
    now = datetime.now(timezone.utc)

    db = SessionLocal()
    try:
        m = research_models.ResearchManifest(
            manifest_id=str(uuid.uuid4()),
            study_id=args.study_id,
            app_version=args.app_version,
            build_number=args.build_number,
            lexicon_version=args.lexicon_version,
            scoring_version=args.scoring_version,
            # 由技术填实际规则，作者审核（字典 §3）
            scoring_spec={
                "metric_name": "normalized_dtw",
                "unit": "dimensionless",
                "direction": "lower_better",
                "min_value": 0,
                "max_value": None,
                "pass_threshold": 0.5,
                "note": "grade 自 schemaVersion 5 起不是 dtw 的纯函数："
                        "全一声词掉调 >3 半音会被走向闸门判 fail，"
                        "判通关请用 grade 而非阈值重算",
            },
            feedback_version=args.feedback_version,
            advice_policy_version=args.advice_policy_version,
            survey_version=args.survey_version,
            consent_version=args.consent_version,
            eligibility_version=args.eligibility_version,
            eligibility_spec={
                "adult_required": True,
                "nationality_any": ["MA"],
                "course_stage_any": ["hsk1", "hsk2", "hsk3"],
                "new_user_required": True,
                "note": "语言背景不作为排除条件",
            },
            post_trigger_count=args.post_trigger_count,
            post_trigger_scope="fixed_word_result_displayed",
            reward_rule_version=args.reward_rule_version,
            collection_start_at=start,
            collection_end_at=end,
            frozen_at=now,
        )
        db.add(m)
        db.commit()
        print(f"已冻结配置 manifest_id={m.manifest_id}")
        print(f"  study_id={m.study_id}")
        print(f"  采集窗口 {start.isoformat()} → {end.isoformat()}（左闭右开，统一 14 天）")
        return 0
    finally:
        db.close()


if __name__ == "__main__":
    raise SystemExit(main())
