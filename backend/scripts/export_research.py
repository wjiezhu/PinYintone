#!/usr/bin/env python3
"""研究数据导出（字段字典 §14）与研究者核对汇总（需求 R09）。

用法：
    python3 scripts/export_research.py --manifest-ids <id> [<id> ...] --out-dir export/
    python3 scripts/export_research.py --manifest-ids <id> --out-dir export/ \\
        --cutoff 2026-10-26T00:00:00+00:00          # 定稿：只取截止时点前到达的资料
    python3 scripts/export_research.py --manifest-ids <id> --out-dir t/ --include-test   # 验证链路

这是新版研究的**唯一**导出路径。旧的 analysis/export.sql 与教师看板读的是冻结的旧表，
不能代替本脚本。

**绝不导出**：
- research_identity_map（账号映射）——研究编号与业务账号的唯一关联点，
  导出即破坏去标识化（字典 §4：映射不进入论文导出）
- 测试账户（is_test=true），除非显式 --include-test 用于验证链路
- 不符合纳入条件者、已退出者、窗口外记录、配置清单之外的记录
- 录音、Apple 标识、姓名、邮箱（研究表本就不存）

**截止时点**（--cutoff，默认为运行时刻）：窗口关闭后仍会收到窗口内产生的离线补传。
导出只取截止时点前**到达服务端**的资料，并把该时点写进 export_meta.json——
截止之后才到的资料不会悄悄进入已定稿的结果；要纳入就重新导出并使用新的截止时点。

除各表 CSV 外，另写两份核对文件：
- export_meta.json：提交号、App/构建、配置清单、截止时点、纳入排除规则、各表行数
- summary.json：纳入人数、问卷各状态、成功与各类失败尝试数、去重后事件数、版本分布

CSV 约定（字典 §14）：UTF-8；数组为合法 JSON；布尔 true/false；
**NULL 为空单元格**。NULL 与空字符串、0 不同义——例如 metric_value 为空
表示「无有效评分」，不是零分。
"""
import argparse
import csv
import json
import os
import subprocess
import sys
from collections import Counter
from datetime import datetime, timezone
from decimal import Decimal

sys.path.insert(0, os.path.dirname(os.path.dirname(os.path.abspath(__file__))))

from app import research_models as m  # noqa: E402
from app.database import SessionLocal  # noqa: E402
from app.research_rules import (aware, background_eligible, describe_spec,  # noqa: E402
                                latest_consent, spec_of)

EXPORT_FORMAT_VERSION = "research-export-2.0"
SURVEY_FINAL = {"declined", "partial", "complete"}
SURVEY_SUBMITTED = {"partial", "complete"}


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


def _backend_commit() -> str:
    """产生本次导出的后端代码提交号。取不到就如实写 unknown，不编。"""
    env = os.environ.get("EXPORT_BACKEND_COMMIT") or os.environ.get("RENDER_GIT_COMMIT")
    if env:
        return env
    try:
        return subprocess.run(["git", "rev-parse", "HEAD"], capture_output=True, text=True,
                              cwd=os.path.dirname(os.path.abspath(__file__)),
                              check=True).stdout.strip()
    except Exception:
        return "unknown"


def export(db, manifest_ids, out_dir, include_test=False, cutoff=None):
    os.makedirs(out_dir, exist_ok=True)
    cutoff = aware(cutoff) if cutoff else datetime.now(timezone.utc)
    manifests = db.query(m.ResearchManifest).filter(
        m.ResearchManifest.manifest_id.in_(manifest_ids)).all()
    if len(manifests) != len(set(manifest_ids)):
        found = {x.manifest_id for x in manifests}
        raise SystemExit(f"配置不存在：{sorted(set(manifest_ids) - found)}")
    # 窗口统一成带时区：SQLite 读回会丢 tzinfo（Postgres 不会），
    # 不规范化的话同一份代码在测试库与生产库上行为不同
    windows = {x.manifest_id: (aware(x.collection_start_at), aware(x.collection_end_at))
               for x in manifests}
    studies = {x.study_id for x in manifests}

    # ---- 纳入判定（字典 §14 纳入条件 + 需求 R01 / R09）----
    included, excluded = [], Counter()
    enrolled_total = 0
    for p in db.query(m.ResearchParticipant).all():
        # 新旧研究分开：不属于指定配置所在研究的人，不计入本次任何统计
        if p.study_id not in studies:
            continue
        enrolled_total += 1
        reason = None
        if p.is_test and not include_test:
            reason = "is_test"
        elif p.eligibility_status != "eligible":
            reason = p.exclusion_reason or "not_eligible"
        else:
            # 本轮**不以新旧用户作为纳入条件**（研究者已确认，V2_DECISIONS 第 15 条）。
            # prior_use_status 如实记录（未实现识别路径时为 unknown），
            # **不把所有人改写成 new**。论文的样本描述应写「未区分新旧用户」。
            latest = latest_consent(db, p.participant_id)
            # 退出者资料的保留策略**尚未审定**（字典 §5、需求 R08）：
            # 审定前一律排除，不由本脚本自行改成保留退出前资料。
            if latest is None or latest.action != "granted":
                reason = "consent_not_active"
            else:
                enrolled = (db.get(m.ResearchManifest, p.enrolled_manifest_id)
                            if p.enrolled_manifest_id else None)
                ok, why = background_eligible(db, p.participant_id, spec_of(enrolled))
                if not ok:
                    reason = why
        if reason:
            excluded[reason] += 1
        else:
            included.append(p.participant_id)
    ids = set(included)

    def in_window(row, ts):
        w = windows.get(row.manifest_id)
        # 左闭右开（字典 §3）。按**发生时间**判，不按到达时间。
        return w is not None and w[0] <= aware(ts) < w[1]

    def arrived(ts):
        # 截止时点之前到达服务端的才进本次导出
        return ts is None or aware(ts) <= cutoff

    late = Counter()

    def keep(rows, occurred, received, table):
        out = []
        for r in rows:
            if r.participant_id not in ids or not in_window(r, occurred(r)):
                continue
            if not arrived(received(r)):
                late[table] += 1
                continue
            out.append(r)
        return out

    counts = {}
    participants = [p for p in db.query(m.ResearchParticipant) if p.participant_id in ids]
    counts["participants"] = _write(os.path.join(out_dir, "participants.csv"),
                                    participants, _columns(m.ResearchParticipant))

    attempts = keep(db.query(m.ResearchAttempt), lambda a: a.started_at,
                    lambda a: a.received_at, "attempts")
    counts["attempts"] = _write(os.path.join(out_dir, "attempts.csv"),
                                attempts, _columns(m.ResearchAttempt))

    events = keep(db.query(m.ResearchInteractionEvent), lambda e: e.occurred_at,
                  lambda e: e.received_at, "interaction_events")
    counts["interaction_events"] = _write(os.path.join(out_dir, "interaction_events.csv"),
                                          events, _columns(m.ResearchInteractionEvent))

    advice = keep(db.query(m.ResearchAdviceRequest), lambda r: r.requested_at,
                  lambda r: r.received_at, "advice_requests")
    counts["advice_requests"] = _write(os.path.join(out_dir, "advice_requests.csv"),
                                       advice, _columns(m.ResearchAdviceRequest))

    # 问卷：实例在截止后才到、或截止后又被更新（例如稍后填写 → 最终提交），
    # 都不进本次导出——否则导出的是截止时点并不存在的状态。
    instances = []
    for s in db.query(m.ResearchSurveyInstance):
        if s.participant_id not in ids or s.manifest_id not in windows:
            continue
        if not arrived(s.received_at) or not arrived(s.updated_at):
            late["survey_instances"] += 1
            continue
        instances.append(s)
    counts["survey_instances"] = _write(os.path.join(out_dir, "survey_instances.csv"),
                                        instances, _columns(m.ResearchSurveyInstance))
    inst_ids = {s.survey_instance_id for s in instances}
    counts["survey_answers"] = _write(
        os.path.join(out_dir, "survey_answers.csv"),
        [a for a in db.query(m.ResearchSurveyAnswer) if a.survey_instance_id in inst_ids],
        _columns(m.ResearchSurveyAnswer))

    # 问题报告的自由文字可能含个人信息：研究者须在展示前检查（字典 §12），
    # 故 detail 单独放一个文件，默认发布的主表不含原文
    reports = keep(db.query(m.ResearchIssueReport), lambda r: r.submitted_at,
                   lambda r: r.received_at, "issue_reports")
    counts["issue_reports"] = _write(os.path.join(out_dir, "issue_reports.csv"),
                                     reports, _columns(m.ResearchIssueReport, exclude={"detail"}))
    _write(os.path.join(out_dir, "issue_reports_detail_REVIEW_BEFORE_SHARING.csv"),
           reports, ["report_id", "detail"])

    lexicons = {x.lexicon_version for x in manifests}
    counts["lexemes"] = _write(
        os.path.join(out_dir, "lexemes.csv"),
        [x for x in db.query(m.ResearchLexeme) if x.lexicon_version in lexicons],
        _columns(m.ResearchLexeme))
    counts["manifests"] = _write(os.path.join(out_dir, "manifests.csv"),
                                 manifests, _columns(m.ResearchManifest))

    summary = _summary(ids, participants, attempts, events, advice, instances, reports,
                       manifests, enrolled_total, excluded, include_test)
    with open(os.path.join(out_dir, "summary.json"), "w", encoding="utf-8") as f:
        json.dump(summary, f, ensure_ascii=False, indent=2)

    meta = {
        "export_format_version": EXPORT_FORMAT_VERSION,
        "generated_at": datetime.now(timezone.utc).isoformat(),
        "backend_commit": _backend_commit(),
        "data_cutoff": cutoff.isoformat(),
        "data_cutoff_note": ("只含该时点前到达服务端的资料。之后才到的窗口内离线补传"
                             "未计入，条数见 arrived_after_cutoff；要纳入须重新导出。"),
        "arrived_after_cutoff": dict(late),
        "manifest_ids": sorted(windows),
        "manifests": [{
            "manifest_id": x.manifest_id, "study_id": x.study_id,
            "app_version": x.app_version, "build_number": x.build_number,
            "compatible_builds": x.compatible_builds,
            "lexicon_version": x.lexicon_version, "scoring_version": x.scoring_version,
            "feedback_version": x.feedback_version,
            "advice_policy_version": x.advice_policy_version,
            "survey_version": x.survey_version, "survey_forms": x.survey_forms,
            "consent_version": x.consent_version,
            "eligibility_version": x.eligibility_version,
            "is_test": bool(x.is_test),
        } for x in manifests],
        "windows": {k: [v[0].isoformat(), v[1].isoformat()] for k, v in windows.items()},
        "include_test": include_test,
        "inclusion_rule": ("属于指定配置所在的研究、同意有效、按参与者纳入时所用配置的规则合格（"
                           + "；".join(sorted({f"{x.eligibility_version}：{describe_spec(spec_of(x))}"
                                               for x in manifests}))
                           + "）、is_test=false；记录按发生时间位于研究窗口（左闭右开）、"
                           "配置在指定清单内、截止时点前到达。缺失或未知不推定满足。"),
        "prior_use_policy": ("本轮**不以新旧用户作为纳入条件**（研究者已确认）。"
                             "prior_use_status 如实记录，未实现识别路径时为 unknown，"
                             "**未改写为 new**。样本描述应写「未区分新旧用户」，"
                             "不得写成「新用户样本」。"),
        "withdrawal_policy": ("退出者资料一律排除：保留退出前资料的意向尚待学校要求核对，"
                              "未审定前不自动纳入（字典 §5）。"),
        "interpretation_limits": [
            "人数按独立研究编号（participant_id）去重，不是记录数，也不是词条配对数。",
            "通过与否以记录里的 passed 为准，不得用 metric_value <= 0.5 重算。",
            "metric_value 是形成性反馈指标，不是语言能力测量；参照曲线由设备端 TTS "
            "现场合成，不保证跨设备一致。",
            "反馈显示模式是学习者自选的，不得据此做组间效果比较。",
            "现有事件算不出严谨的任务成功率或操作耗时，本导出不提供这两项。",
        ],
        "csv_conventions": "UTF-8；数组为 JSON；布尔 true/false；NULL 为空单元格（≠ 0 ≠ 空字符串）",
        "not_exported": ["research_identity_map（账号映射）", "录音", "Apple 标识/姓名/邮箱"],
        "row_counts": counts,
        "participants_enrolled_in_these_studies": enrolled_total,
        "participants_included": len(ids),
        "participants_excluded_by_reason": dict(excluded),
        "survey_status_counts": summary["surveys"],
        "warnings": ([] if not include_test else
                     ["⚠ 本次导出含测试账户，仅供验证统计链路，不得用于论文分析"]),
    }
    with open(os.path.join(out_dir, "export_meta.json"), "w", encoding="utf-8") as f:
        json.dump(meta, f, ensure_ascii=False, indent=2)
    meta["summary"] = summary
    return meta


def _summary(ids, participants, attempts, events, advice, instances, reports,
             manifests, enrolled_total, excluded, include_test):
    """研究者核对用的最小汇总。所有数字都只来自**已通过纳入规则的导出行**。"""
    def per_form(form_key):
        rows = [s for s in instances if s.form_key == form_key]
        people = {s.participant_id for s in rows}
        return {
            # 每人每版本至多一份实例，所以实例数即人数；仍按人去重以防多版本并存
            "participants_with_instance": len(people),
            "participants_without_instance": len(ids - people),
            "by_status": dict(Counter(s.status for s in rows)),
            "by_timing_class": dict(Counter(s.timing_class for s in rows)),
            "submitted": len({s.participant_id for s in rows if s.status in SURVEY_SUBMITTED}),
            "explicitly_declined": len({s.participant_id for s in rows
                                        if s.status == "declined"}),
            "by_form_version": dict(Counter(
                f"{s.form_version} | {s.translation_version} | {s.language}" for s in rows)),
        }

    attempt_ids = {a.attempt_id for a in attempts}
    failures = [a for a in attempts if a.status != "succeeded"]
    return {
        "note": ("人数按独立研究编号去重。本文件只做核对，不含任何能力或效果结论。"
                 + ("⚠ 含测试账户，不得用于论文分析。" if include_test else "")),
        "participants": {
            "enrolled_in_these_studies": enrolled_total,
            "included": len(ids),
            "excluded_by_reason": dict(excluded),
            "by_is_test": dict(Counter("test" if p.is_test else "real" for p in participants)),
            "by_prior_use_status": dict(Counter(p.prior_use_status for p in participants)),
        },
        "surveys": {
            "background_v1": per_form("background_v1"),
            "tone_needs_v1": per_form("tone_needs_v1"),
            "usability_short_v1": per_form("usability_short_v1"),
        },
        "attempts": {
            "total": len(attempts),
            "participants_with_any_attempt": len({a.participant_id for a in attempts}),
            "by_status": dict(Counter(a.status for a in attempts)),
            "by_task_type": dict(Counter(a.task_type for a in attempts)),
            "succeeded": sum(1 for a in attempts if a.status == "succeeded"),
            "succeeded_and_result_displayed": sum(
                1 for a in attempts
                if a.status == "succeeded" and a.result_displayed_at is not None),
            "failures_by_status_and_error": dict(Counter(
                f"{a.status}:{a.error_code or '-'}" for a in failures)),
            # 实际判定结果；null = 无有效评分，**不等于未通过**
            "passed": dict(Counter(
                "null" if a.passed is None else str(bool(a.passed)).lower()
                for a in attempts)),
            "by_signal_status": dict(Counter(a.signal_status for a in attempts)),
            "by_time_quality": dict(Counter(a.time_quality for a in attempts)),
            "retries_linked": sum(1 for a in attempts if a.retry_of_attempt_id),
        },
        "events": {
            # event_id 是主键，表内本就唯一；这里的数即去重后的事件数
            "total_distinct": len({e.event_id for e in events}),
            "by_name": dict(Counter(e.event_name for e in events)),
            "by_ui_language": dict(Counter(e.ui_language for e in events)),
            # 事件指向的尝试不在导出里（没传到、被拒、或在窗口外）
            "referencing_attempt_not_in_export": sum(
                1 for e in events if e.attempt_id and e.attempt_id not in attempt_ids),
        },
        "advice_requests": {"total": len(advice)},
        "issue_reports": {"total": len(reports),
                          "by_category": dict(Counter(r.category for r in reports))},
        "versions": {
            "manifests": {x.manifest_id: {
                "app_version": x.app_version, "build_number": x.build_number,
                "lexicon_version": x.lexicon_version, "scoring_version": x.scoring_version,
                "consent_version": x.consent_version,
                "eligibility_version": x.eligibility_version,
                "is_test": bool(x.is_test)} for x in manifests},
            "attempts_by_manifest": dict(Counter(a.manifest_id for a in attempts)),
            "participants_by_enrolled_manifest": dict(Counter(
                p.enrolled_manifest_id or "unknown" for p in participants)),
        },
    }


def _print_summary(meta):
    s = meta["summary"]
    print(f"截止时点 {meta['data_cutoff']}  后端提交 {meta['backend_commit'][:12]}")
    print(f"研究内已纳入 {s['participants']['enrolled_in_these_studies']} 人；"
          f"本次导出纳入 {s['participants']['included']} 人；"
          f"排除：{s['participants']['excluded_by_reason'] or '无'}")
    for key, label in (("background_v1", "背景表"), ("tone_needs_v1", "前置问卷"),
                       ("usability_short_v1", "使用后问卷")):
        f = s["surveys"][key]
        print(f"  {label}：已提交 {f['submitted']} 人，状态 {f['by_status'] or '{}'}，"
              f"时间定位 {f['by_timing_class'] or '{}'}，无实例 {f['participants_without_instance']} 人")
    a = s["attempts"]
    print(f"  尝试 {a['total']} 条：{a['by_status'] or '{}'}；"
          f"失败明细 {a['failures_by_status_and_error'] or '无'}")
    print(f"  事件 {s['events']['total_distinct']} 条（去重后）：{s['events']['by_name'] or '{}'}")
    if meta["arrived_after_cutoff"]:
        print(f"  截止后才到达、未计入：{meta['arrived_after_cutoff']}")
    for k, v in meta["row_counts"].items():
        print(f"  {k}.csv: {v} 行")
    for w in meta["warnings"]:
        print(w)


def main() -> int:
    p = argparse.ArgumentParser(description=__doc__,
                                formatter_class=argparse.RawDescriptionHelpFormatter)
    p.add_argument("--manifest-ids", nargs="+", required=True)
    p.add_argument("--out-dir", required=True)
    p.add_argument("--include-test", action="store_true",
                   help="包含测试账户——仅用于验证统计链路，不得用于论文分析")
    p.add_argument("--cutoff", default=None,
                   help="数据截止时点（ISO8601，带时区）。只导出此前到达服务端的资料；"
                        "默认为运行时刻。定稿导出请显式给出并记录。")
    args = p.parse_args()
    cutoff = None
    if args.cutoff:
        cutoff = datetime.fromisoformat(args.cutoff)
        if cutoff.tzinfo is None:
            print("错误：--cutoff 必须带时区", file=sys.stderr)
            return 1
    db = SessionLocal()
    try:
        meta = export(db, args.manifest_ids, args.out_dir, args.include_test, cutoff)
    finally:
        db.close()
    _print_summary(meta)
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
