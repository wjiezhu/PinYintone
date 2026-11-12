#!/usr/bin/env python3
"""结束一份「不限时间」的研究配置：把采集终点改成当下（或指定时点）。

这是已冻结配置**唯一允许的改动**，而且只能往前收：
- 只改 collection_end_at，其余字段一律不动；
- 新终点不能早于已经到达的任何一条研究记录的发生时间之前——
  否则已经合法入库的数据会落到窗口外；
- 新终点不能晚于原终点（不能借这个脚本延长采集）。

结束时点由研究者决定；脚本默认取运行那一刻。

用法：python3 scripts/close_manifest.py <manifest_id> [--at 2026-12-01T00:00:00+01:00] [--yes]
"""
import argparse
import os
import sys
from datetime import datetime, timezone

sys.path.insert(0, os.path.dirname(os.path.dirname(os.path.abspath(__file__))))

from sqlalchemy import func  # noqa: E402

from app import research_models as m  # noqa: E402
from app.database import SessionLocal  # noqa: E402
from app.research_rules import aware  # noqa: E402


def close(db, manifest_id: str, at: datetime) -> datetime:
    row = db.get(m.ResearchManifest, manifest_id)
    if row is None:
        raise SystemExit(f"配置不存在：{manifest_id}")
    old_end = aware(row.collection_end_at)
    if at >= old_end:
        raise SystemExit(f"新终点 {at.isoformat()} 不早于原终点 {old_end.isoformat()}，"
                         "本脚本只能提前结束，不能延长")
    if at <= aware(row.collection_start_at):
        raise SystemExit("新终点必须晚于采集开始时间")
    latest = [x for x in (
        db.query(func.max(m.ResearchAttempt.started_at)).filter_by(manifest_id=manifest_id).scalar(),
        db.query(func.max(m.ResearchInteractionEvent.occurred_at))
          .filter_by(manifest_id=manifest_id).scalar(),
    ) if x is not None]
    if latest and at <= max(aware(x) for x in latest):
        raise SystemExit("新终点早于已入库记录的发生时间，会把合法数据挤到窗口外")
    row.collection_end_at = at
    db.commit()
    return old_end


def main() -> int:
    p = argparse.ArgumentParser(description=__doc__,
                                formatter_class=argparse.RawDescriptionHelpFormatter)
    p.add_argument("manifest_id")
    p.add_argument("--at", help="结束时点（ISO8601，带时区）；默认现在")
    p.add_argument("--yes", action="store_true", help="不再询问，直接执行")
    args = p.parse_args()
    at = datetime.now(timezone.utc)
    if args.at:
        at = datetime.fromisoformat(args.at)
        if at.tzinfo is None:
            raise SystemExit("--at 必须带时区")
        at = at.astimezone(timezone.utc)
    if not args.yes:
        ans = input(f"把配置 {args.manifest_id} 的采集终点改为 {at.isoformat()}？输入 yes 确认：")
        if ans.strip() != "yes":
            print("已取消")
            return 1
    db = SessionLocal()
    try:
        old = close(db, args.manifest_id, at)
    finally:
        db.close()
    print(f"已结束采集：{old.isoformat()} → {at.isoformat()}（UTC）")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
