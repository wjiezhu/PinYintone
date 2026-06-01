#!/usr/bin/env python3
"""部署后冒烟测试：对线上后端跑一遍核心接口。纯标准库，无需安装依赖。

用法：
    python3 scripts/smoke.py https://your-app.onrender.com
"""
import json
import sys
import urllib.error
import urllib.request

BASE = (sys.argv[1] if len(sys.argv) > 1 else "http://localhost:8000").rstrip("/")


def call(method, path, body=None, token=None):
    url = f"{BASE}{path}"
    data = json.dumps(body).encode() if body is not None else None
    req = urllib.request.Request(url, data=data, method=method)
    if body is not None:
        req.add_header("Content-Type", "application/json")
    if token:
        req.add_header("Authorization", f"Bearer {token}")
    try:
        with urllib.request.urlopen(req, timeout=90) as resp:
            raw = resp.read().decode()
            return resp.status, (json.loads(raw) if raw else {})
    except urllib.error.HTTPError as e:
        return e.code, {"error": e.read().decode()[:200]}


def main():
    print(f"目标：{BASE}\n（Render 免费版首次请求可能冷启动 ~30-60s，请耐心）\n")
    ok = True

    status, body = call("GET", "/health")
    print(f"[health] {status} {body}")
    ok &= status == 200

    import time
    email = f"smoke{int(time.time())}@test.com"
    status, reg = call("POST", "/teacher/register",
                       {"email": email, "password": "pw", "name": "Smoke"})
    print(f"[teacher/register] {status} classCode={reg.get('classCode')}")
    ok &= status == 200
    token, code = reg.get("token"), reg.get("classCode")

    status, _ = call("POST", "/api/sync/session", {
        "id": f"smoke-{int(time.time())}", "deviceID": "smoke-dev", "classCode": code,
        "role": "student", "groupAssignment": "dynamicF0", "lexemeID": "paobu",
        "dtwScore": 0.3, "grade": "good", "attemptNumber": 1,
        "timestamp": "2026-05-21T10:00:00Z"})
    print(f"[sync/session] {status}")
    ok &= status == 200

    if token:
        status, summary = call("GET", "/teacher/class/summary", token=token)
        print(f"[class/summary] {status} {summary}")
        ok &= status == 200

    print("\n" + ("✅ 冒烟测试通过" if ok else "❌ 有接口失败，见上方输出"))
    sys.exit(0 if ok else 1)


if __name__ == "__main__":
    main()
