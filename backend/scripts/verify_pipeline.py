#!/usr/bin/env python3
"""研究统计链路的接口级验证（需求 §7 验证层次 3）。

按 **App 真实的请求格式**（ISO8601、带小数秒与 Z）经 HTTP 驱动真实服务，
模拟多个测试用户走完全程，并核对每一步的服务端响应；给了 --export-dir 时
再对同一个数据库跑一次导出，逐项核对导出里的人数与条数。

用法（先起一个指向**测试库**的服务，并冻结一份测试配置、灌入词库）：

    python3 scripts/verify_pipeline.py --base-url http://127.0.0.1:8765 \\
        --app-version 1.0 --build 17 --lexeme-version <lexemeVersionID> \\
        --export-dir /tmp/verify-export

所有请求都带 isTest=true，且只认测试配置，不会混入正式研究数据。

⚠ 本脚本**直接调纳入接口**，绕过了 App 端的资格判定与界面流程。
它能证明接口契约、幂等与导出口径，**不能**证明「真实 App 里合格的人能被纳入」
——那一条（验收 A03）必须用真实 App 操作来验。
"""
import argparse
import csv
import json
import os
import sys
import urllib.error
import urllib.parse
import urllib.request
import uuid
from datetime import datetime, timedelta, timezone

RESULTS = []
RUN = uuid.uuid4().hex[:8]     # 每次运行用新的账号后缀，脚本可重复跑


def iso(dt):
    # 与 iOS ResearchJSON.encoder 完全一致：三位小数秒 + Z
    return dt.astimezone(timezone.utc).strftime("%Y-%m-%dT%H:%M:%S.") + \
        f"{dt.microsecond // 1000:03d}Z"


def call(base, method, path, body=None, raw=None):
    data = raw.encode() if raw is not None else (
        json.dumps(body).encode() if body is not None else None)
    req = urllib.request.Request(base + path, method=method,
                                 headers={"Content-Type": "application/json"}, data=data)
    try:
        with urllib.request.urlopen(req) as r:
            return r.status, json.loads(r.read() or b"{}")
    except urllib.error.HTTPError as e:
        try:
            return e.code, json.loads(e.read() or b"{}")
        except ValueError:
            return e.code, {}


def check(name, ok, detail=""):
    RESULTS.append((name, ok, detail))
    print(f"  {'✅' if ok else '❌'} {name}" + (f"  — {detail}" if detail and not ok else ""))


def register(base, device, apple=None):
    return call(base, "POST", "/student/register",
                {"deviceID": device, "role": "student", "appleUserID": apple})[0]


def enroll(base, cfg, device, now, **kw):
    body = {"internalUserID": device, "manifestID": cfg["manifestID"],
            "consentVersion": cfg["consentVersion"], "consentLanguage": "fr",
            "consentOccurredAt": iso(now), "eligibilityStatus": "eligible",
            "eligibilityVersion": cfg["eligibilityVersion"],
            "priorUseStatus": "unknown", "priorUseEvidence": "insufficient",
            "isTest": True}
    body.update(kw)
    s, b = call(base, "POST", "/research/enroll", body)
    return s, b.get("participantID"), b


def survey(base, cfg, pid, form, status, timing, now, *, instance, answers=(), n=0,
           invited=None, submitted=None):
    spec = (cfg.get("surveyForms") or {}).get(form) or {
        "form_version": f"{form}-verify", "translation_version": "verify"}
    final = status in ("complete", "partial", "declined")
    return call(base, "POST", "/research/surveys", {
        "participantID": pid, "manifestID": cfg["manifestID"],
        "surveyInstanceID": instance, "timingClass": timing,
        "qualifyingAttemptsAtInvite": n, "invitedAt": iso(invited or now),
        "outcome": {"formKey": form, "formVersion": spec["form_version"],
                    "translationVersion": spec["translation_version"], "language": "fr",
                    "answers": list(answers), "status": status,
                    "startedAt": iso(now) if status != "invited" else None,
                    "submittedAt": iso(submitted or now) if final else None}})


def answered(q, *codes, now, text=None):
    a = {"questionID": q, "state": "answered", "optionCodes": list(codes),
         "answeredAt": iso(now)}
    if text is not None:
        a["textValue"] = text
    return a


def background_answers(now, adult="adult", nat="MA", stage="hsk2"):
    return [answered("B01", adult, now=now), answered("B02", nat, now=now),
            answered("B03", stage, now=now), {"questionID": "B04", "state": "skipped"},
            {"questionID": "B05", "state": "not_answered"}]


def attempt(aid, lexeme_version, now, kind="ok", **kw):
    a = {"attemptID": aid, "sessionID": f"sess-{RUN}", "taskType": "fixed_word",
         "lexemeVersionID": lexeme_version, "startedAt": iso(now),
         "finishedAt": iso(now + timedelta(seconds=3)),
         "timeQuality": "valid", "recordingDurationMs": 1800, "analysisDurationMs": 120}
    if kind == "ok":
        a.update(status="succeeded", signalStatus="usable", metricValue=0.31, passed=True,
                 resultDisplayedAt=iso(now + timedelta(seconds=3)))
    elif kind == "low":   # 有效但未通过：仍是一次合格练习
        a.update(status="succeeded", signalStatus="usable", metricValue=0.92, passed=False,
                 resultDisplayedAt=iso(now + timedelta(seconds=3)))
    elif kind == "no_signal":
        a.update(status="analysis_failed", signalStatus="unusable", errorCode="no_signal")
    elif kind == "cancelled":
        a.update(status="cancelled", signalStatus="unknown")
    a.update(kw)
    return a


def post_attempts(base, cfg, pid, attempts):
    return call(base, "POST", "/research/attempts",
                {"participantID": pid, "manifestID": cfg["manifestID"], "attempts": attempts})


def event(name, now, attempt_id=None, lexeme_version=None, payload=None, eid=None):
    return {"eventID": eid or str(uuid.uuid4()), "sessionID": f"sess-{RUN}",
            "attemptID": attempt_id, "lexemeVersionID": lexeme_version,
            "eventName": name, "occurredAt": iso(now), "sessionElapsedMs": 4200,
            "uiLanguage": "fr", "payload": payload or {}}


def post_events(base, cfg, pid, events):
    return call(base, "POST", "/research/events",
                {"participantID": pid, "manifestID": cfg["manifestID"], "events": events})


def main():
    p = argparse.ArgumentParser(description=__doc__,
                                formatter_class=argparse.RawDescriptionHelpFormatter)
    p.add_argument("--base-url", required=True)
    p.add_argument("--app-version", required=True, help="与测试配置绑定的 App 版本")
    p.add_argument("--build", required=True, help="与测试配置绑定的构建号")
    p.add_argument("--lexeme-version", required=True,
                   help="已入库、属于该配置词库的任一 lexemeVersionID")
    p.add_argument("--export-dir", default=None,
                   help="给出则对同一数据库（由 DATABASE_URL 指定）跑导出并对账")
    args = p.parse_args()
    base = args.base_url.rstrip("/")
    now = datetime.now(timezone.utc)
    lv = args.lexeme_version
    q = urllib.parse.urlencode({"appVersion": args.app_version, "build": args.build})

    print("① 配置下发")
    s, _ = call(base, "GET", "/research/manifest/active")
    check("不报版本的客户端拿不到配置（旧构建不进研究）", s == 404, f"HTTP {s}")
    s, _ = call(base, "GET", f"/research/manifest/active?{q}")
    check("正式客户端看不到测试配置", s == 404, f"HTTP {s}")
    s, cfg = call(base, "GET", f"/research/manifest/active?{q}&test=true")
    check("测试客户端取得测试配置", s == 200 and cfg.get("isTest") is True, f"HTTP {s} {cfg}")
    if s != 200:
        return 1
    check("配置时间带时区", cfg["collectionStartAt"].endswith(("+00:00", "Z")),
          cfg["collectionStartAt"])
    check("配置下发各材料版本供客户端自检",
          all(cfg.get(k) for k in ("lexiconVersion", "eligibilityVersion", "consentVersion",
                                   "buildNumber")), str(cfg))

    print("② 账号先于纳入、资格与身份")
    dev_a, dev_a2 = f"verify-A-{RUN}", f"verify-A2-{RUN}"
    s, _, b = enroll(base, cfg, f"verify-noacct-{RUN}", now)
    check("未注册账号不能纳入", s == 409 and "account_required" in b.get("detail", ""), f"{s} {b}")
    register(base, dev_a, apple=f"apple-A-{RUN}")
    s, _, b = enroll(base, cfg, dev_a, now, eligibilityStatus="pending")
    check("端侧未判合格不能纳入", s == 409, f"{s} {b}")
    s, _, b = enroll(base, cfg, dev_a, now, consentLanguage="fr_MA")
    check("系统区域不能冒充界面语言", s == 400, f"{s} {b}")
    s, pa, _ = enroll(base, cfg, dev_a, now)
    check("成年 MA HSK2、使用史 unknown：纳入成功", s == 200 and bool(pa), f"HTTP {s}")
    s, pa2, b = enroll(base, cfg, dev_a, now)
    check("纳入重试返回同一编号", pa2 == pa and b.get("alreadyEnrolled") is True)
    register(base, dev_a2, apple=f"apple-A-{RUN}")
    s, pa3, _ = enroll(base, cfg, dev_a2, now)
    check("同一账号换设备仍是同一位参与者", pa3 == pa, f"{pa3} != {pa}")

    print("③ 背景表与问卷生命周期")
    s, b = survey(base, cfg, pa, "background_v1", "complete", "background", now,
                  instance=f"bg-{RUN}", answers=background_answers(now))
    check("背景表入库", s == 200 and b.get("updated") is True, f"{s} {b}")
    s, b = survey(base, cfg, pa, "background_v1", "complete", "background", now,
                  instance=f"bg-{RUN}", answers=background_answers(now, adult="minor"))
    check("背景表重传幂等、不改写", s == 200 and b.get("alreadySubmitted") is True, f"{s} {b}")

    pre_done = now + timedelta(seconds=30)
    s, b = survey(base, cfg, pa, "tone_needs_v1", "complete", "before_first_attempt",
                  pre_done, instance=f"pre-{RUN}",
                  answers=[answered("PRE01", "often", now=pre_done),
                           answered("PRE02", "other", now=pre_done, text="verify")])
    check("前置问卷（练习前完成）入库", s == 200 and b.get("status") == "complete", f"{s} {b}")

    print("④ 尝试、事件与幂等")
    t0 = now + timedelta(minutes=1)
    ids = [str(uuid.uuid4()) for _ in range(8)]
    atts = [attempt(ids[i], lv, t0 + timedelta(minutes=i)) for i in range(3)]
    atts.append(attempt(ids[3], lv, t0 + timedelta(minutes=3), kind="low"))
    atts.append(attempt(ids[4], lv, t0 + timedelta(minutes=4), retryOfAttemptID=ids[3]))
    atts.append(attempt(ids[5], lv, t0 + timedelta(minutes=5), kind="no_signal"))
    atts.append(attempt(ids[6], lv, t0 + timedelta(minutes=6), kind="cancelled"))
    s, b = post_attempts(base, cfg, pa, atts)
    check("7 次尝试入库（5 有效含 1 低分 + 1 技术失败 + 1 取消）",
          s == 200 and b.get("inserted") == 7 and not b.get("rejected"), f"{s} {b}")
    s, b = post_attempts(base, cfg, pa, atts)
    check("同一批重传不重复入库", b.get("inserted") == 0 and b.get("duplicates") == 7, f"{b}")
    s, b = post_attempts(base, cfg, pa, [attempt(ids[7], lv, t0, kind="no_signal",
                                                 metricValue=0.0, passed=False)])
    check("技术失败不得带零分", s == 400, f"HTTP {s}")
    s, b = post_attempts(base, cfg, pa, [attempt(str(uuid.uuid4()), "no-such-lexeme", t0)])
    check("未知词条版本被单条拒收而不阻塞整批",
          s == 200 and b.get("rejected", [{}])[0].get("reason") == "unknown_lexeme_version", f"{b}")
    s, b = post_attempts(base, cfg, pa, [attempt(str(uuid.uuid4()), lv,
                                                 now - timedelta(days=400))])
    check("窗口外产生的尝试被拒收",
          s == 200 and b.get("rejected", [{}])[0].get("reason") == "outside_window", f"{b}")
    s, _ = call(base, "POST", "/research/attempts", raw=json.dumps({
        "participantID": pa, "manifestID": cfg["manifestID"],
        "attempts": [attempt(str(uuid.uuid4()), lv, t0)]}).replace("0.31", "NaN"))
    check("NaN 成绩被拒", s in (400, 422), f"HTTP {s}")

    evs = [event("task_opened", t0, lexeme_version=lv, payload={"task_type": "fixed_word"}),
           event("model_audio_started", t0, lexeme_version=lv)]
    for i in (0, 1, 2, 3, 4):
        evs.append(event("feedback_displayed", t0 + timedelta(minutes=i, seconds=3),
                         attempt_id=ids[i], lexeme_version=lv, payload={"mode": "pitch_curve"}))
    evs.append(event("learner_audio_started", t0 + timedelta(minutes=1), attempt_id=ids[0],
                     lexeme_version=lv))
    s, b = post_events(base, cfg, pa, evs)
    check("8 条事件入库", s == 200 and b.get("inserted") == 8, f"{s} {b}")
    s, b = post_events(base, cfg, pa, evs)
    check("事件重传去重", b.get("inserted") == 0 and b.get("duplicates") == 8, f"{b}")

    s, b = call(base, "POST", "/research/advice", {
        "participantID": pa, "manifestID": cfg["manifestID"], "requests": [{
            "requestID": f"adv-{RUN}", "attemptID": ids[3],
            "requestedAt": iso(t0 + timedelta(minutes=3, seconds=10)),
            "status": "succeeded", "generatedAt": iso(t0 + timedelta(minutes=3, seconds=10)),
            "displayedAt": iso(t0 + timedelta(minutes=3, seconds=10)),
            "sourceType": "rule_feedback", "evidenceCodes": ["overall_metric"],
            "evidenceSnapshot": {"metric_name": "normalized_dtw", "metric_value": "0.92"},
            "outputLanguage": "fr", "outputText": "verify"}]})
    check("练习建议点击记录入库", s == 200 and b.get("inserted") == 1, f"{s} {b}")

    s, _ = call(base, "POST", "/research/issues", {
        "reportID": f"issue-{RUN}", "participantID": pa, "manifestID": cfg["manifestID"],
        "submittedAt": iso(t0), "category": "recording_failed", "detail": "verify"})
    check("问题报告入库", s == 200)

    print("⑤ 使用后问卷：邀请 → 稍后填写 → 提交 → 重传")
    inv = t0 + timedelta(minutes=5)
    post = dict(instance=f"post-{RUN}", n=5, invited=inv)
    s, b = survey(base, cfg, pa, "usability_short_v1", "invited", "after_practice", inv, **post)
    check("邀请入库", s == 200 and b.get("status") == "invited", f"{s} {b}")
    s, b = survey(base, cfg, pa, "usability_short_v1", "deferred", "after_practice", inv, **post)
    check("稍后填写更新同一份实例", b.get("status") == "deferred"
          and b.get("surveyInstanceID") == f"post-{RUN}", f"{b}")
    final = [answered("POST01", "agree", now=inv), answered("POST02", "cannot_judge", now=inv),
             {"questionID": "POST03", "state": "skipped"},
             answered("POST04", "none", now=inv), {"questionID": "POST05", "state": "not_answered"}]
    s, b = survey(base, cfg, pa, "usability_short_v1", "partial", "after_practice",
                  inv + timedelta(minutes=2), answers=final, **post)
    check("稍后填写之后的最终答案进得来", b.get("status") == "partial" and b.get("updated"), f"{b}")
    s, b = survey(base, cfg, pa, "usability_short_v1", "deferred", "after_practice", inv, **post)
    check("迟到的旧状态不让答案倒退", b.get("status") == "partial" and not b.get("updated"), f"{b}")

    print("⑥ 参与者 B：低分也计次的人；参与者 C：退出")
    dev_b, dev_c = f"verify-B-{RUN}", f"verify-C-{RUN}"
    register(base, dev_b, apple=f"apple-B-{RUN}")
    _, pb, _ = enroll(base, cfg, dev_b, now, priorUseStatus="returning",
                      priorUseEvidence="verified_account_history")
    check("旧用户与新用户同一纳入口径", bool(pb) and pb != pa)
    survey(base, cfg, pb, "background_v1", "complete", "background", now,
           instance=f"bg-b-{RUN}", answers=background_answers(now, stage="hsk1"))
    survey(base, cfg, pb, "tone_needs_v1", "partial", "late_pre", t0 + timedelta(minutes=9),
           instance=f"pre-b-{RUN}", n=1,
           answers=[answered("PRE01", "rarely", now=t0)])
    post_attempts(base, cfg, pb, [attempt(str(uuid.uuid4()), lv, t0, kind="low")])

    register(base, dev_c, apple=f"apple-C-{RUN}")
    _, pc, _ = enroll(base, cfg, dev_c, now)
    survey(base, cfg, pc, "background_v1", "complete", "background", now,
           instance=f"bg-c-{RUN}", answers=background_answers(now))
    post_attempts(base, cfg, pc, [attempt(str(uuid.uuid4()), lv, t0)])
    wd = {"participantID": pc, "consentVersion": cfg["consentVersion"],
          "consentLanguage": "fr", "occurredAt": iso(t0 + timedelta(minutes=10))}
    s, b = call(base, "POST", "/research/withdraw", wd)
    check("退出成功", s == 200 and b.get("alreadyWithdrawn") is False, f"{s} {b}")
    s, b = call(base, "POST", "/research/withdraw", wd)
    check("退出指令重试不重复记录", b.get("alreadyWithdrawn") is True, f"{b}")
    s, _ = post_attempts(base, cfg, pc, [attempt(str(uuid.uuid4()), lv, t0)])
    check("退出后尝试重传被拒", s == 403, f"HTTP {s}")
    s, _ = post_events(base, cfg, pc, [event("history_opened", t0)])
    check("退出后事件重传被拒", s == 403, f"HTTP {s}")
    s, _ = survey(base, cfg, pc, "tone_needs_v1", "complete", "before_first_attempt", now,
                  instance=f"pre-c-{RUN}")
    check("退出后问卷被拒", s == 403, f"HTTP {s}")
    s, _, b = enroll(base, cfg, dev_c, now)
    check("退出后本轮不重新纳入", s == 409, f"{s} {b}")

    print("⑦ 契约守卫")
    # 已纳入者重试会直接返回原编号；用未纳入的新账号验证数字时间戳
    dev_n = f"verify-N-{RUN}"
    register(base, dev_n)
    s, _, _ = enroll(base, cfg, dev_n, now, consentOccurredAt=811472400)
    check("iOS 默认格式（数字时间戳）被拒而非存成 1995 年", s == 422, f"HTTP {s}")

    if args.export_dir:
        print("⑧ 导出对账（同一数据库）")
        sys.path.insert(0, os.path.dirname(os.path.dirname(os.path.abspath(__file__))))
        from app.database import SessionLocal
        from scripts.export_research import export
        db = SessionLocal()
        try:
            default = export(db, [cfg["manifestID"]], os.path.join(args.export_dir, "default"))
            meta = export(db, [cfg["manifestID"]], os.path.join(args.export_dir, "with_test"),
                          include_test=True)
        finally:
            db.close()
        check("默认导出排除全部测试数据",
              default["participants_included"] == 0
              and default["row_counts"]["attempts"] == 0, str(default["row_counts"]))

        def rows(name):
            with open(os.path.join(args.export_dir, "with_test", name), encoding="utf-8") as f:
                return list(csv.DictReader(f))

        mine = {pa, pb, pc}
        people = {r["participant_id"] for r in rows("participants.csv")}
        check("含测试导出：A、B 纳入，退出者 C 排除",
              pa in people and pb in people and pc not in people,
              f"{sorted(people & mine)}")
        a_rows = [r for r in rows("attempts.csv") if r["participant_id"] == pa]
        by = {}
        for r in a_rows:
            by[r["status"]] = by.get(r["status"], 0) + 1
        check("A 的尝试：5 有效 + 1 技术失败 + 1 取消",
              by == {"succeeded": 5, "analysis_failed": 1, "cancelled": 1}, str(by))
        check("失败与取消的成绩是空单元格，不是 0",
              all(r["metric_value"] == "" and r["passed"] == ""
                  for r in a_rows if r["status"] != "succeeded"))
        check("低分的有效尝试 passed=false 且计入已显示结果",
              sum(1 for r in a_rows if r["passed"] == "false"
                  and r["result_displayed_at"]) == 1)
        check("A 的事件 8 条（去重后）",
              sum(1 for r in rows("interaction_events.csv") if r["participant_id"] == pa) == 8)
        inst = {r["form_key"]: r for r in rows("survey_instances.csv")
                if r["participant_id"] == pa}
        check("A 的三份问卷各一份",
              sorted(inst) == ["background_v1", "tone_needs_v1", "usability_short_v1"],
              str(sorted(inst)))
        check("使用后问卷保留邀请时的合格次数与最终状态",
              inst.get("usability_short_v1", {}).get("status") == "partial"
              and inst.get("usability_short_v1", {}).get("qualifying_attempts_at_invite") == "5")
        b_pre = [r for r in rows("survey_instances.csv")
                 if r["participant_id"] == pb and r["form_key"] == "tone_needs_v1"]
        check("B 的前置问卷保持 late_pre", b_pre and b_pre[0]["timing_class"] == "late_pre")
        check("导出不含账号映射与设备号",
              not any(dev in open(os.path.join(args.export_dir, "with_test", f),
                                  encoding="utf-8").read()
                      for f in os.listdir(os.path.join(args.export_dir, "with_test"))
                      for dev in (dev_a, dev_b, f"apple-A-{RUN}")))
        check("含测试导出带醒目警告", any("测试账户" in w for w in meta["warnings"]))

    passed = sum(1 for _, ok, _ in RESULTS if ok)
    print(f"\n结果：{passed}/{len(RESULTS)} 通过")
    print(json.dumps({"participant_A": pa, "participant_B": pb, "participant_C": pc,
                      "manifest": cfg["manifestID"], "run": RUN}))
    return 0 if passed == len(RESULTS) else 1


if __name__ == "__main__":
    sys.exit(main())
