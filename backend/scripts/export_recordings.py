#!/usr/bin/env python3
"""把录音导出到**本机**目录，供研究者人工听辨或复核评分。

录音能认出人，属于受限数据：
- 只导到本机，不进仓库、不进公开材料、不随论文附件发布；
- 只导出同意仍有效的参与者（退出者的录音在退出时已删除，这里再挡一次）；
- 默认排除测试参与者；
- 文件名只用研究编号与尝试编号，不含任何账号信息。

输出：<out_dir>/<participant_id>/<attempt_id>.aac（AAC 裸流，常见播放器都能直接放），外加 recordings.csv
（尝试编号、任务类型、词条版本、实测流程编号、成绩、是否通过、时长、sha256）。

用法：python3 scripts/export_recordings.py <manifest_id> [<manifest_id> ...] --out DIR
"""
import argparse
import csv
import hashlib
import os
import sys

sys.path.insert(0, os.path.dirname(os.path.dirname(os.path.abspath(__file__))))

from app import research_models as m  # noqa: E402
from app.database import SessionLocal  # noqa: E402
from app.research_rules import has_active_consent  # noqa: E402

COLUMNS = ["participant_id", "attempt_id", "task_type", "lexeme_version_id",
           "field_session_id", "started_at", "metric_value", "passed",
           "duration_ms", "byte_size", "sha256", "file"]


def export_recordings(db, manifest_ids, out_dir, include_test=False) -> int:
    rows = (db.query(m.ResearchRecording, m.ResearchAttempt, m.ResearchParticipant)
            .join(m.ResearchAttempt,
                  m.ResearchAttempt.attempt_id == m.ResearchRecording.attempt_id)
            .join(m.ResearchParticipant,
                  m.ResearchParticipant.participant_id == m.ResearchRecording.participant_id)
            .filter(m.ResearchRecording.manifest_id.in_(manifest_ids))
            .order_by(m.ResearchRecording.participant_id, m.ResearchAttempt.started_at)
            .all())
    os.makedirs(out_dir, exist_ok=True)
    written = 0
    consent_ok: dict[str, bool] = {}
    with open(os.path.join(out_dir, "recordings.csv"), "w", newline="", encoding="utf-8") as f:
        w = csv.writer(f)
        w.writerow(COLUMNS)
        for rec, att, part in rows:
            if part.is_test and not include_test:
                continue
            if part.participant_id not in consent_ok:
                consent_ok[part.participant_id] = has_active_consent(db, part.participant_id)
            if not consent_ok[part.participant_id]:
                continue
            if hashlib.sha256(rec.content).hexdigest() != rec.sha256:
                print(f"警告：{rec.attempt_id} 的录音校验不符，跳过", file=sys.stderr)
                continue
            rel = os.path.join(part.participant_id, f"{rec.attempt_id}.aac")
            os.makedirs(os.path.join(out_dir, part.participant_id), exist_ok=True)
            with open(os.path.join(out_dir, rel), "wb") as audio:
                audio.write(rec.content)
            w.writerow([part.participant_id, att.attempt_id, att.task_type,
                        att.lexeme_version_id, att.field_session_id or "",
                        att.started_at.isoformat(),
                        "" if att.metric_value is None else att.metric_value,
                        "" if att.passed is None else att.passed,
                        rec.duration_ms, rec.byte_size, rec.sha256, rel])
            written += 1
    return written


def main() -> int:
    p = argparse.ArgumentParser(description=__doc__,
                                formatter_class=argparse.RawDescriptionHelpFormatter)
    p.add_argument("manifest_ids", nargs="+")
    p.add_argument("--out", required=True, help="本机输出目录（不要放在仓库里）")
    p.add_argument("--include-test", action="store_true")
    args = p.parse_args()
    db = SessionLocal()
    try:
        n = export_recordings(db, args.manifest_ids, args.out, args.include_test)
    finally:
        db.close()
    print(f"已导出 {n} 段录音到 {args.out}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
