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
| POST | `/student/register` | 学生注册（设备级，只填名字）；服务端**均衡随机**分配 A/B 并返回 `{experimentGroup}`，幂等 |

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

## 部署（Render + Neon，免费）

已附配置：`render.yaml`、`Procfile`、`Dockerfile`、`runtime.txt` / `.python-version`（固定 Python 3.12，避免新版 wheel 缺失）。
`DATABASE_URL` 会自动把 `postgres://` / `postgresql://` 适配为 SQLAlchemy 所需的 `postgresql+psycopg2://`（兼容 Neon 的 `?sslmode=require`）；服务监听 `$PORT`。

### 第 1 步：免费 Postgres（Neon）
1. 注册 [neon.tech](https://neon.tech)（免费、不过期、无需信用卡）。
2. 建一个 Project，复制连接串（形如 `postgresql://user:pass@ep-xxx.region.aws.neon.tech/dbname?sslmode=require`）。
   - 用 **non-pooled / direct** 连接串即可；若日志报 `channel_binding` 相关错误，从串尾删掉 `&channel_binding=require`。

### 第 2 步：部署后端（Render）
**蓝图方式（最快）**：Render → New → **Blueprint** → 选本仓库 → 它读**仓库根**的 `render.yaml`（Blueprint Path 留空即可，默认根目录；该文件用 `rootDir: backend` 指向后端）。
随后只需在生成的服务里把 **`DATABASE_URL`** 填成第 1 步的 Neon 连接串（`JWT_SECRET` 已自动生成）。

> 报「Blueprint file render.yaml not found」= 蓝图文件不在仓库根。本仓库已放在根目录，点 **Retry** 即可。

**手动方式（不依赖蓝图）**：Render → New → **Web Service** → 连本仓库：
- **Root Directory**：`backend`（仓库根是 iOS 工程，后端在子目录）
- **Build**：`pip install -r requirements.txt`
- **Start**：`uvicorn app.main:app --host 0.0.0.0 --port $PORT`
- **Plan**：Free
- Environment 加：`DATABASE_URL`=Neon 连接串、`JWT_SECRET`=`python -c "import secrets;print(secrets.token_hex(32))"`、`PYTHON_VERSION`=`3.12.7`

### 第 3 步：验证
```bash
python3 scripts/smoke.py https://你的服务.onrender.com
```
脚本会跑 health → 教师注册 → 班级码校验 → 同步 → 教师概览。
（Render 免费版闲置会休眠，首次请求冷启动 ~30–60s，属正常。）

### 第 4 步：iOS 指向生产后端
App 默认连 `http://localhost:8000`。上线后在 **Info.plist 增加键 `PT_API_BASE_URL`**，值填生产域名（如 `https://你的服务.onrender.com`），无需改代码（`APIClient` 已优先读取该键）。

### 其他平台
`Dockerfile` 可直接用于任意容器平台（Fly.io / HF Space 等）；`Procfile` 兼容 Heroku 风格平台。

### 环境变量
| 变量 | 必填 | 说明 |
|------|------|------|
| `DATABASE_URL` | 生产必填 | Neon Postgres 连接串；本地缺省 SQLite |
| `JWT_SECRET` | 生产必填 | ≥32 字节随机串（Render 蓝图自动生成） |
| `PORT` | 平台注入 | 监听端口 |

## 待完善（骨架未覆盖）
- Alembic 数据库迁移（当前用 `create_all` 开发建表，生产首部署即建表）
- `weeklyNewStudents` 周新增统计
- `POST /api/feedback/llm`（后期接入 Qwen3-Omni 动态反馈，替换模板库）
- 速率限制 / 生产级鉴权细化 / HTTPS 由平台终结
