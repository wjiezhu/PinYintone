# Pinyintone 后端（FastAPI）

纯数据层：接收 iOS 训练记录、提供教师面板聚合与 CSV 导出。**不做任何音频处理**（F0/DTW/送气检测全部在客户端完成）。

## 技术栈
- FastAPI + Uvicorn
- SQLAlchemy 2.0（默认 SQLite，生产可换 PostgreSQL）
- PyJWT（教师鉴权）+ passlib/bcrypt（密码哈希）

## 快速开始

```bash
cd backend
python3 -m venv .venv && source .venv/bin/activate
pip install -r requirements.txt
cp .env.example .env            # 按需修改
uvicorn app.main:app --reload --port 8000
```

启动后：
- 健康检查：http://localhost:8000/health
- 交互式文档：http://localhost:8000/docs

iOS 端 `APIClient.baseURL` 已指向 `http://localhost:8000`，模拟器可直接联调。

## 路由（与 iOS APIClient 路径严格对齐）

### 鉴权 / 注册
| 方法 | 路径 | 说明 |
|------|------|------|
| POST | `/teacher/register` | 教师注册，服务端生成 6 位唯一班级码（禁全同位），返回 JWT |
| POST | `/teacher/login` | 教师登录 |
| GET  | `/class-code/verify/{code}` | 校验班级码是否存在 → `{valid}` |
| POST | `/student/register` | 学生/游客注册（设备级，不含 PII） |
| PUT  | `/student/bind` | 游客绑定班级码升级为学生 |

### 数据同步（上行）
| 方法 | 路径 | 说明 |
|------|------|------|
| POST | `/api/sync/session` | 声调训练记录（按 id 幂等 upsert） |
| POST | `/api/sync/aspiration` | 送气训练记录 |
| POST | `/api/sync/freetext` | 自由文本记录 |

### 教师面板（需 `Authorization: Bearer <token>`）
| 方法 | 路径 | 说明 |
|------|------|------|
| GET | `/teacher/class/summary` | 人数 / 平均 DTW / 通关率 |
| GET | `/teacher/class/comparison` | A/B 两组 DTW 均值对比 |
| GET | `/teacher/class/tone-breakdown` | T1–T4 偏误率（按 lexemeID 查声调聚合） |
| GET | `/teacher/students` | 学生列表（练习数/近期通关率/最后活跃） |
| GET | `/teacher/students/{device_id}` | 个体 DTW 时序 + 高频偏误词 |
| GET | `/teacher/export/csv` | 导出班级训练数据 CSV（供 SPSS/R 分析） |

## 已知契约注意点（与现有 iOS 客户端对齐）
- **上行时间** `timestamp` 为 ISO8601 字符串（iOS 同步 DTO 即如此）。
- **下行 `lastActiveAt`** 以 **Apple 参考时间(秒)** 的数字返回，匹配 iOS `JSONDecoder` 默认 `.deferredToDate`。
- 通关线 `DTW ≤ 0.5`、班级码 6 位纯数字且禁全同位，均遵循 `CLAUDE.md`。
- 游客记录 `classCode = null` 不丢弃，进入"未绑定班级"池（论文辅助数据）。

## 部署

已附部署配置：`Procfile`、`railway.json`、`Dockerfile`、`runtime.txt` / `.python-version`（固定 Python 3.12，避免新版 wheel 缺失）。
`DATABASE_URL` 会自动把云平台注入的 `postgres://` / `postgresql://` 适配为 SQLAlchemy 所需的 `postgresql+psycopg2://`；服务监听 `$PORT`。

### Railway（推荐）
1. 把仓库推到 GitHub（已完成）。
2. Railway → New Project → Deploy from GitHub repo，选本仓库。
3. **Root Directory 设为 `backend`**（仓库根是 iOS 工程，后端在子目录）。
4. 添加插件 **PostgreSQL**：Railway 会自动注入 `DATABASE_URL`。
5. 在 Variables 里加 **`JWT_SECRET`**（用 `python -c "import secrets;print(secrets.token_hex(32))"` 生成）。
6. 部署完成后在 Settings → Networking 生成公网域名，例如 `https://xxx.up.railway.app`。
7. 验证：`GET https://xxx.up.railway.app/health` → `{"status":"ok"}`；`/docs` 看交互文档。

> Render / Fly.io 同理：Root=`backend`，加 Postgres，设 `JWT_SECRET`，Start = `uvicorn app.main:app --host 0.0.0.0 --port $PORT`。
> 或用 `Dockerfile` 一键容器部署。

### iOS 指向生产后端
App 默认连 `http://localhost:8000`。上线后在 **Info.plist 增加键 `PT_API_BASE_URL`**，值填生产域名（如 `https://xxx.up.railway.app`），无需改代码（`APIClient` 已优先读取该键）。

### 环境变量
| 变量 | 必填 | 说明 |
|------|------|------|
| `DATABASE_URL` | 生产必填 | Railway Postgres 自动注入；本地缺省 SQLite |
| `JWT_SECRET` | 生产必填 | ≥32 字节随机串 |
| `PORT` | 平台注入 | 监听端口 |

## 待完善（骨架未覆盖）
- Alembic 数据库迁移（当前用 `create_all` 开发建表，生产首部署即建表）
- `weeklyNewStudents` 周新增统计
- `POST /api/feedback/llm`（后期接入 Qwen3-Omni 动态反馈，替换模板库）
- 速率限制 / 生产级鉴权细化 / HTTPS 由平台终结
