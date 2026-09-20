#!/usr/bin/env python3
"""研究统计链路的端到端验证（需求 §8：先用测试账户验证，再正式采集）。

按 **App 真实的请求格式**（ISO8601、带小数秒与 Z）经 HTTP 驱动真实服务，
模拟多个测试用户走完全程，并核对每一步的服务端响应。

用法：python3 scripts/verify_pipeline.py --base-url http://127.0.0.1:8765

所有请求都带 isTest=true，不会混入正式研究数据。
"""
import argparse
import json
import sys
import urllib.error
import urllib.request
import uuid
from datetime import datetime, timedelta, timezone

RESULTS = []


def iso(dt):
    # 与 iOS ResearchJSON.encoder 完全一致：三位小数秒 + Z
    return dt.astimezone(timezone.utc).strftime("%Y-%m-%dT%H:%M:%S.") + \
        f"{dt.microsecond // 1000:03d}Z"


def call(base, method, path, body=None):
    req = urllib.request.Request(base + path, method=method,
                                 headers={"Content-Type": "application/json"},
                                 data=json.dumps(body).encode() if body is not None else None)
    try:
        with urllib.request.urlopen(req) as r:
            return r.status, json.loads(r.read() or b"{}")
    except urllib.error.HTTPError as e:
        return e.code, json.loads(e.read() or b"{}")


def check(name, ok, detail=""):
    RESULTS.append((name, ok, detail))
    print(f"  {'✅' if ok else '❌'} {name}" + (f"  — {detail}" if detail and not ok else ""))


def participant(base, mid, uid, now):
    s, b = call(base, "POST", "/research/enroll", {
        "internalUserID": uid, "manifestID": mid, "consentVersion": "consent-1.0-unpublished",
        "consentLanguage": "zh", "consentOccurredAt": iso(now), "isTest": True})
    return s, b.get("participantID")


def background(base, pid, mid, now, adult="adult", nat="MA", stage="hsk2"):
    ans = lambda q, c: {"questionID": q, "state": "answered", "optionCodes": [c],
                        "answeredAt": iso(now)}
    return call(base, "POST", "/research/surveys", {
        "participantID": pid, "manifestID": mid, "timingClass": "background",
        "qualifyingAttemptsAtInvite": 0,
        "outcome": {"formKey": "background_v1", "formVersion": "background-1.0-draft",
                    "translationVersion": "i18n-1.0", "language": "zh",
                    "answers": [ans("B01", adult), ans("B02", nat), ans("B03", stage)],
                    "status": "complete", "startedAt": iso(now), "submittedAt": iso(now)}})


def attempt(aid, lexeme_version, now, ok=True):
    a = {"attemptID": aid, "sessionID": "sess-verify", "taskType": "fixed_word",
         "lexemeVersionID": lexeme_version, "startedAt": iso(now), "finishedAt": iso(now),
         "timeQuality": "valid", "recordingDurationMs": 1800, "analysisDurationMs": 120}
    if ok:
        a.update(status="succeeded", signalStatus="usable", metricValue=0.31, passed=True,
                 resultDisplayedAt=iso(now))
    else:
        a.update(status="analysis_failed", signalStatus="unusable", errorCode="no_signal")
    return a


def main():
    p = argparse.ArgumentParser()
    p.add_argument("--base-url", required=True)
    p.add_argument("--lexeme-version", required=True,
                   help="research_lexicon.json 里任一 lexemeVersionID")
    args = p.parse_args()
    base = args.base_url.rstrip("/")
    now = datetime.now(timezone.utc)

    print("① 配置下发")
    s, m = call(base, "GET", "/research/manifest/active")
    check("取得生效配置", s == 200, f"HTTP {s}")
    if s != 200:
        return 1
    mid = m["manifestID"]
    check("配置时间带时区", m["collectionStartAt"].endswith(("+00:00", "Z")), m["collectionStartAt"])

    print("② 参与者 A：完整走一遍")
    s, pa = participant(base, mid, "verify-A", now)
    check("纳入成功", s == 200 and pa, f"HTTP {s}")
    s2, pa2 = participant(base, mid, "verify-A", now)
    check("重复纳入返回同一编号（换设备/重装幂等）", pa2 == pa)
    check("背景表上传", background(base, pa, mid, now)[0] == 200)

    atts = [attempt(str(uuid.uuid4()), args.lexeme_version, now + timedelta(minutes=i))
            for i in range(5)]
    atts.append(attempt(str(uuid.uuid4()), args.lexeme_version, now + timedelta(minutes=6), ok=False))
    s, b = call(base, "POST", "/research/attempts",
                {"participantID": pa, "manifestID": mid, "attempts": atts})
    check("6 次尝试入库（5 成功 + 1 失败）", s == 200 and b.get("inserted") == 6, f"{s} {b}")
    s, b = call(base, "POST", "/research/attempts",
                {"participantID": pa, "manifestID": mid, "attempts": atts})
    check("同一批重传不重复入库（上传重试≠新尝试）", b.get("inserted") == 0, f"{b}")

    ev = [{"eventID": str(uuid.uuid4()), "sessionID": "sess-verify",
           "attemptID": atts[0]["attemptID"], "lexemeVersionID": args.lexeme_version,
           "eventName": "feedback_displayed", "occurredAt": iso(now),
           "sessionElapsedMs": 4200, "uiLanguage": "zh", "payload": {"mode": "pitch_curve"}}]
    s, b = call(base, "POST", "/research/events",
                {"participantID": pa, "manifestID": mid, "events": ev})
    check("事件入库（先传尝试再传事件，外键可解）", s == 200 and b.get("inserted") == 1, f"{s} {b}")

    s, _ = call(base, "POST", "/research/issues", {
        "reportID": str(uuid.uuid4()), "participantID": pa, "manifestID": mid,
        "submittedAt": iso(now), "category": "recording_failed", "detail": "测试"})
    check("问题报告入库", s == 200)

    print("③ 参与者 B：撤回")
    s, pb = participant(base, mid, "verify-B", now)
    background(base, pb, mid, now)
    call(base, "POST", "/research/attempts", {"participantID": pb, "manifestID": mid,
                                              "attempts": [attempt(str(uuid.uuid4()),
                                                                   args.lexeme_version, now)]})
    s, _ = call(base, "POST", "/research/withdraw", {
        "participantID": pb, "consentVersion": "consent-1.0-unpublished",
        "consentLanguage": "zh", "occurredAt": iso(now + timedelta(seconds=5))})
    check("撤回成功", s == 200)
    s, _ = call(base, "POST", "/research/attempts", {
        "participantID": pb, "manifestID": mid,
        "attempts": [attempt(str(uuid.uuid4()), args.lexeme_version, now)]})
    check("撤回后离线重传被拒", s == 403, f"HTTP {s}")

    print("④ 契约守卫")
    s, _ = call(base, "POST", "/research/enroll", {
        "internalUserID": "verify-num", "manifestID": mid, "consentVersion": "c",
        "consentLanguage": "zh", "consentOccurredAt": 811472400, "isTest": True})
    check("iOS 默认格式（数字时间戳）被拒而非存成 1995 年", s == 422, f"HTTP {s}")

    passed = sum(1 for _, ok, _ in RESULTS if ok)
    print(f"\n结果：{passed}/{len(RESULTS)} 通过")
    print(json.dumps({"participant_A": pa, "participant_B": pb, "manifest": mid}))
    return 0 if passed == len(RESULTS) else 1


if __name__ == "__main__":
    sys.exit(main())
