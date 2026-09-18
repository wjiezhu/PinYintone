#!/usr/bin/env python3
"""研究数据导出（字段字典 §14）。

用法：
    python3 scripts/export_research.py --manifest-ids <id> [<id> ...] --out-dir export/
    python3 scripts/export_research.py --manifest-ids <id> --out-dir t/ --include-test   # 测试账户验证链路

**绝不导出**：
- research_identity_map（账号映射）——研究编号与业务账号的唯一关联点，
  导出即破坏去标识化（字典 §4：映射不进入论文导出）
- 测试账户（is_test=true），除非显式 --include-test 用于验证链路
- 窗口外记录、配置清单之外的记录
- 录音、Apple 标识、姓名、邮箱（研究表本就不存）

CSV 约定（字典 §14）：UTF-8；数组为合法 JSON；布尔 true/false；
**NULL 为空单元格**。NULL 与空字符串、0 不同义——例如 metric_value 为空
表示「无有效评分」，不是零分。
"""
import argparse
import csv
import json
import os
import sys
from datetime import datetime, timezone
from decimal import Decimal

sys.path.insert(0, os.path.dirname(os.path.dirname(os.path.abspath(__file__))))

from app import research_models as m  # noqa: E402
from app.database import SessionLocal  # noqa: E402

EXPORT_FORMAT_VERSION = "research-export-1.0"

# 字典 §3 eligibility_spec，研究者已确认
ELIGIBLE_NATIONALITY = "MA"
ELIGIBLE_STAGES = {"hsk1", "hsk2", "hsk3"}


def _cell(v):
    """CSV 单元格编码。NULL → 空单元格；布尔 → true/false；数组/对象 → JSON。"""
    if v is None:
        return ""
    if isinstance(v, bool):
        return "true" if v else "false"
    if isinstance(v, (list, dict)):
        return json.dumps(v, ensure_ascii=False)
    if isinstance(v, datetime):
        return v.isoformat()
    if isinstance(v, Decimal):
        return str(v)
    return v


def _write(path, rows, columns):
    with open(path, "w", newline="", encoding="utf-8") as f:
        w = csv.writer(f)
        w.writerow(columns)
        for r in rows:
            w.writerow([_cell(getattr(r, c)) for c in columns])
    return len(rows)


def _columns(model, exclude=()):
    return [c.name for c in model.__table__.columns if c.name not in exclude]


def _latest_consent(db, pid):
    return (db.query(m.ResearchConsentEvent)
            .filter(m.ResearchConsentEvent.participant_id == pid)
            .order_by(m.ResearchConsentEvent.occurred_at.desc()).first())


def _background_eligible(db, pid) -> tuple[bool, str]:
    """按冻结规则判纳入：成年、国籍含 MA、课程阶段 hsk1–3。

    **缺失或未知不推定满足**（字典 §14）：没答、跳过、prefer_not 一律视为不满足。
    """
    inst = (db.query(m.ResearchSurveyInstance)
            .filter_by(participant_id=pid, form_key="background_v1").first())
    if inst is None:
        return False, "no_background"
    answers = {a.question_id: a for a in
               db.query(m.ResearchSurveyAnswer).filter_by(survey_instance_id=inst.survey_instance_id)}

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


def export(db, manifest_ids, out_dir, include_test=False):
    os.makedirs(out_dir, exist_ok=True)
    manifests = db.query(m.ResearchManifest).filter(
        m.ResearchManifest.manifest_id.in_(manifest_ids)).all()
    if len(manifests) != len(set(manifest_ids)):
        found = {x.manifest_id for x in manifests}
        raise SystemExit(f"配置不存在：{sorted(set(manifest_ids) - found)}")
    # 窗口统一成带时区：SQLite 读回会丢 tzinfo（Postgres 不会），
    # 不规范化的话同一份代码在测试库与生产库上行为不同
    windows = {x.manifest_id: (_aware(x.collection_start_at), _aware(x.collection_end_at))
               for x in manifests}

    # ---- 纳入判定（字典 §14 纳入条件）----
    included, excluded = [], {}
    for p in db.query(m.ResearchParticipant).all():
        reason = None
        if p.is_test and not include_test:
            reason = "is_test"
        elif p.prior_use_status != "new":
            reason = "prior_use_not_new"      # 旧用户不纳入本轮；unknown 也不推定为 new
        else:
            latest = _latest_consent(db, p.participant_id)
            # 撤回后资料的保留策略**尚未获准执行**（字典 §5：正式策略冻结前，
            # 不自动将退出者资料加入新研究导出）。故一律排除，待策略冻结后再改。
            if latest is None or latest.action != "granted":
                reason = "consent_not_active"
            else:
                ok, why = _background_eligible(db, p.participant_id)
                if not ok:
                    reason = why
        if reason:
            excluded[reason] = excluded.get(reason, 0) + 1
        else:
            included.append(p.participant_id)
    ids = set(included)

    def in_window(row, ts):
        w = windows.get(row.manifest_id)
        # 左闭右开（字典 §3）
        return w is not None and w[0] <= _aware(ts) < w[1]

    counts = {}
    counts["participants"] = _write(
        os.path.join(out_dir, "participants.csv"),
        [p for p in db.query(m.ResearchParticipant) if p.participant_id in ids],
        _columns(m.ResearchParticipant))

    attempts = [a for a in db.query(m.ResearchAttempt)
                if a.participant_id in ids and in_window(a, a.started_at)]
    counts["attempts"] = _write(os.path.join(out_dir, "attempts.csv"),
                                attempts, _columns(m.ResearchAttempt))

    events = [e for e in db.query(m.ResearchInteractionEvent)
              if e.participant_id in ids and in_window(e, e.occurred_at)]
    counts["interaction_events"] = _write(os.path.join(out_dir, "interaction_events.csv"),
                                          events, _columns(m.ResearchInteractionEvent))

    instances = [s for s in db.query(m.ResearchSurveyInstance)
                 if s.participant_id in ids and s.manifest_id in windows]
    counts["survey_instances"] = _write(os.path.join(out_dir, "survey_instances.csv"),
                                        instances, _columns(m.ResearchSurveyInstance))
    inst_ids = {s.survey_instance_id for s in instances}
    counts["survey_answers"] = _write(
        os.path.join(out_dir, "survey_answers.csv"),
        [a for a in db.query(m.ResearchSurveyAnswer) if a.survey_instance_id in inst_ids],
        _columns(m.ResearchSurveyAnswer))

    # 问题报告的自由文字可能含个人信息：研究者须在展示前检查（字典 §12），
    # 故 detail 单独放一个文件，默认发布的主表不含原文
    reports = [r for r in db.query(m.ResearchIssueReport)
               if r.participant_id in ids and in_window(r, r.submitted_at)]
    counts["issue_reports"] = _write(os.path.join(out_dir, "issue_reports.csv"),
                                     reports, _columns(m.ResearchIssueReport, exclude={"detail"}))
    _write(os.path.join(out_dir, "issue_reports_detail_REVIEW_BEFORE_SHARING.csv"),
           reports, ["report_id", "detail"])

    counts["lexemes"] = _write(os.path.join(out_dir, "lexemes.csv"),
                               db.query(m.ResearchLexeme).all(), _columns(m.ResearchLexeme))
    counts["manifests"] = _write(os.path.join(out_dir, "manifests.csv"),
                                 manifests, _columns(m.ResearchManifest))

    meta = {
        "export_format_version": EXPORT_FORMAT_VERSION,
        "generated_at": datetime.now(timezone.utc).isoformat(),
        "manifest_ids": sorted(windows),
        "windows": {k: [v[0].isoformat(), v[1].isoformat()] for k, v in windows.items()},
        "include_test": include_test,
        "inclusion_rule": ("同意有效、成年、国籍含 MA、课程阶段 hsk1–3、prior_use_status=new、"
                           "is_test=false、记录位于研究窗口、配置在指定清单内。缺失或未知不推定满足。"),
        "withdrawal_policy": ("撤回者资料一律排除：保留退出前资料的意向尚待学校要求核对，"
                              "未获准执行前不自动纳入（字典 §5）。"),
        "csv_conventions": "UTF-8；数组为 JSON；布尔 true/false；NULL 为空单元格（≠ 0 ≠ 空字符串）",
        "not_exported": ["research_identity_map（账号映射）", "录音", "Apple 标识/姓名/邮箱"],
        "row_counts": counts,
        "participants_included": len(ids),
        "participants_excluded_by_reason": excluded,
        "warnings": ([] if not include_test else
                     ["⚠ 本次导出含测试账户，仅供验证统计链路，不得用于论文分析"]),
    }
    with open(os.path.join(out_dir, "export_meta.json"), "w", encoding="utf-8") as f:
        json.dump(meta, f, ensure_ascii=False, indent=2)
    return meta


def _aware(dt):
    return dt if dt.tzinfo else dt.replace(tzinfo=timezone.utc)


def main() -> int:
    p = argparse.ArgumentParser(description=__doc__,
                                formatter_class=argparse.RawDescriptionHelpFormatter)
    p.add_argument("--manifest-ids", nargs="+", required=True)
    p.add_argument("--out-dir", required=True)
    p.add_argument("--include-test", action="store_true",
                   help="包含测试账户——仅用于验证统计链路，不得用于论文分析")
    args = p.parse_args()
    db = SessionLocal()
    try:
        meta = export(db, args.manifest_ids, args.out_dir, args.include_test)
    finally:
        db.close()
    print(f"纳入 {meta['participants_included']} 人；排除：{meta['participants_excluded_by_reason']}")
    for k, v in meta["row_counts"].items():
        print(f"  {k}: {v}")
    for w in meta["warnings"]:
        print(w)
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
