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
| POST | `/student/email/request-code` | 邮箱登录第 1 步：`{email}` → 发 6 位验证码。不论邮箱是否注册过，返回都一样 |
| POST | `/student/email/login` | 邮箱登录第 2 步：`{email, code, deviceID, role, nickname?, nativeLanguage?, spokenLanguages?}`，成功后与 Apple / Google 同一套建档 |

### 数据同步（上行）
| 方法 | 路径 | 说明 |
|------|------|------|
| POST | `/api/sync/session` | 声调训练记录（按 id 幂等 upsert） |
| POST | `/api/sync/aspiration` | 送气训练记录 |
| POST | `/api/sync/freetext` | 自由文本记录 |

### 新版本检查（不需要登录）
| 方法 | 路径 | 说明 |
|------|------|------|
| GET | `/api/app-version/android` | Android 直接分发：最新版本号、最低支持版本号、下载地址（只放行 https）、各语言更新说明。值全部来自 `ANDROID_*` 环境变量；没配好时 `published = false`，App 不提示 |

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
| `APPLE_BUNDLE_IDS` | 生产必填 | 逗号分隔；Apple identityToken 的 aud，即 iOS App 的 bundle id（`Joy.PinYintone`） |
| `GOOGLE_CLIENT_IDS` | Android 上线前必填 | 逗号分隔；Google ID token 的 aud。Credential Manager 下是传给 `serverClientId` 的 **Web** client id（可同时列 Android client id） |
| `ALLOW_LEGACY_UNVERIFIED_APPLE` | 选填，默认 `true` | 过渡开关：没带 identityToken 的 Apple 登录（线上旧版 iOS）是否放行。关掉的时机由人决定，见下 |
| `JWKS_CACHE_SECONDS` | 选填，默认 21600 | Apple / Google 公钥缓存时长 |
| `APP_ENV` | 选填 | `development` / `production`。留空时 PostgreSQL = 生产、其余 = 开发。生产环境里发信器没配好，邮箱登录一律 503，不会退回 console |
| `EMAIL_SENDER` | 邮箱登录上线前必填 | `console`（只写日志，开发默认，生产拒用）/ `resend` / `smtp` |
| `EMAIL_FROM` | `resend` / `smtp` 必填 | 发件人，如 `Pinyintone <login@mail.你的域名>`；域名须已在服务商处验证 |
| `RESEND_API_KEY` | `resend` 必填 | Resend 后台生成，只给 Sending access |
| `SMTP_HOST` / `SMTP_PORT` / `SMTP_USERNAME` / `SMTP_PASSWORD` / `SMTP_SECURITY` | `smtp` 用 | 阿里云邮件推送、Amazon SES 等的 SMTP 接口；`SMTP_SECURITY` 为 `ssl`（默认，465）或 `starttls`（587） |
| `EMAIL_CODE_PER_EMAIL_PER_HOUR` | 选填，默认 5 | 同一邮箱每小时最多发几次验证码 |
| `EMAIL_CODE_PER_IP_PER_HOUR` | 选填，默认 30 | 同一 IP 每小时最多发几次。一个教室常共用出口 IP，别设太小 |
| `TRUSTED_PROXY_HOPS` | 选填，默认 1 | 取客户端 IP 时信任几层反向代理（`X-Forwarded-For` 从右数）。Railway / Render 取 1，直接对外暴露取 0 |
| `ANDROID_LATEST_VERSION_CODE` / `ANDROID_LATEST_VERSION_NAME` | 发 Android 新版时填 | 最新安装包的 versionCode（整数，比较用）与显示用的版本名；versionCode 为 0 = 不提示 |
| `ANDROID_MIN_VERSION_CODE` | 选填，默认 0 | 低于它的 App 提示「必须更新」（提示不能关，但不拦练习）。不会高于最新版本 |
| `ANDROID_DOWNLOAD_URL` | 发 Android 新版时填 | 安装包下载页，必须 `https://`；App 用系统浏览器打开，自己不下载 |
| `ANDROID_RELEASE_NOTES_ZH` / `_EN` / `_FR` / `_AR` | 选填 | 更新说明，按界面语言显示，缺的语言依次退到 en、zh |
| `PORT` | 平台注入 | 监听端口 |

### 学生登录身份
账号身份是 (登录方式, 用户号)：`users.auth_provider / auth_subject`，`account_identities`
存它到研究用 `account_id` 的对应。用户号取自服务端验过签的凭证（`app/identity.py`），
不信客户端直接传的 ID。错误码在 `detail` 的「：」之前：`identity_token_required`、
`identity_token_invalid`、`identity_token_expired`、`identity_token_audience`、
`identity_subject_mismatch`（401）；`unsupported_provider`（400）；
`identity_not_configured`、`identity_provider_unavailable`（503）。

### 邮箱验证码登录（provider = email）
给用不了 Google 的 Android 手机（中国大陆的参与者）用。实现见 `app/email_login.py`、`app/email_sender.py`。

- 用户号 `auth_subject` = 规范化邮箱（去首尾空格、转小写；**不**做 Gmail 去点 / 去 `+tag`）的 SHA-256，
  库里不存邮箱明文。同一邮箱换设备 = 同一个 `account_id`；同一设备换邮箱 = 另一位参与者。
- 同一个人用 Google 和邮箱各登一次 = 两个账号，**不按邮箱自动合并**（已接受的局限）。
- 验证码：6 位数字，10 分钟有效，只存 HMAC（密钥 `JWT_SECRET` + 每条随机盐），每个最多试 5 次，
  用过即作废，新码发出时旧码作废。同一邮箱 60 秒冷却；同一邮箱、同一 IP 每小时各有上限。
- 登录过的设备补送资料 / 改名字，仍可用 `/student/register`（`provider = email`，不带凭证）。
- 删除账号时，该邮箱的身份、全部验证码和发送流水一起删掉。

错误码（`detail` 的「：」之前）：
| 状态 | code |
|---|---|
| 400 | `email_invalid`、`email_code_format` |
| 401 | `email_code_invalid`（还剩几次在说明里）、`email_code_expired`、`email_code_attempts_exceeded`；`/student/register` 想直接认邮箱身份时 `email_login_required` |
| 429 | `email_code_cooldown`、`email_code_rate_limited`（都带 `Retry-After`） |
| 503 | `email_not_configured`（发信器没配好）、`email_send_failed`（服务商拒收 / 连不上；这次不占冷却和配额） |

本地开发不用配任何东西：`EMAIL_SENDER` 留空即 `console`，验证码打印在后端日志里（`[console 发信器，未真正发送]`）。

#### 接入 Resend（上线前人工做）
1. 在 [resend.com](https://resend.com) 注册，**先买 / 准备一个自己的域名**。建议专门用一个子域发信（如 `mail.你的域名`），不影响主域的信誉。
2. Resend → Domains → Add Domain，按它给出的记录在域名的 DNS 里添加：
   - **SPF**：子域（Resend 用的是 `send.mail.你的域名`）的 TXT 与 MX 记录，按后台原样填；
   - **DKIM**：`resend._domainkey...` 的 TXT 记录；
   - **DMARC**：自己加一条 `_dmarc.你的域名` TXT，起步用 `v=DMARC1; p=none; rua=mailto:你的邮箱`，送达稳定后再收紧到 `quarantine`。
   等 Resend 后台显示 Verified。
3. API Keys → 新建一个只有 **Sending access**、限定该域名的 key。
4. 在部署平台设置 `EMAIL_SENDER=resend`、`RESEND_API_KEY=…`、`EMAIL_FROM=Pinyintone <login@mail.你的域名>`（生产环境建议同时设 `APP_ENV=production`）。
5. 上线前用 **Gmail、Outlook、QQ 邮箱、163 邮箱**各收一次验证码：看是否进收件箱（不是垃圾箱）、到达用了多久、三种语言是否显示正常。国内邮箱若进垃圾箱或延迟大，考虑换阿里云邮件推送（见下）。
6. 注意 Resend 免费档的日 / 月发送上限，研究开始前确认够用。

#### 换别的服务商
阿里云邮件推送、Amazon SES 等都有 SMTP 接口，只改环境变量：`EMAIL_SENDER=smtp`、`SMTP_HOST`、`SMTP_PORT`、
`SMTP_USERNAME`、`SMTP_PASSWORD`、`SMTP_SECURITY`、`EMAIL_FROM`（同样要先在该服务商处验证发信域名并配 SPF / DKIM / DMARC）。
只有 HTTP API 的服务商：在 `app/email_sender.py` 写一个带 `send_code` 的类并登记到 `_FACTORIES`。

决定什么时候关 `ALLOW_LEGACY_UNVERIFIED_APPLE` 时，看最近还有多少设备靠它登录：

```sql
SELECT count(*) FROM users WHERE legacy_login_at > now() - interval '30 days';
```

启动时 `app/migrations.py` 会把旧表 `account_links`（只认 Apple）抄进
`account_identities`（provider = apple，`account_id` 不变），SQLite 与 PostgreSQL 都跑。
这一步**只做一次**，做完在 `app_migrations` 表里记一行 `account_links_to_account_identities`。

**旧表 `account_links` 保留，确认无误后手动清理。** 迁移之后代码不再读写它（没有它的模型）。
注意：迁移之后删除的账号，其 Apple 用户号仍留在旧表里，直到手动清理——别拖太久。

清理前核对（PostgreSQL；只读）：

```sql
-- 1. 迁移确实做过
SELECT * FROM app_migrations WHERE name = 'account_links_to_account_identities';

-- 2. 旧表每一行在新表里都有，且 account_id 一致。
--    「新表里没有」只应是迁移之后删除的账号：对应的 users 行也应已不存在
SELECT l.apple_user_id, l.account_id AS old_account_id, i.account_id AS new_account_id,
       EXISTS (SELECT 1 FROM users u WHERE u.auth_provider = 'apple'
               AND u.auth_subject = l.apple_user_id) AS still_has_devices
FROM account_links l
LEFT JOIN account_identities i ON i.provider = 'apple' AND i.subject = l.apple_user_id
WHERE i.account_id IS DISTINCT FROM l.account_id;
-- 期望：0 行；或只有 new_account_id 为空且 still_has_devices = false 的行（已删除的账号）。
-- 出现 new_account_id 不为空却与 old_account_id 不同的行 = 研究身份变了，**停下排查，不要清理**

-- 3. 行数对照：旧表行数 = 新表里来自旧表的 apple 行 + 迁移后删除的账号
SELECT (SELECT count(*) FROM account_links) AS old_rows,
       (SELECT count(*) FROM account_links l JOIN account_identities i
          ON i.provider = 'apple' AND i.subject = l.apple_user_id
          AND i.account_id = l.account_id) AS matched_rows;

-- 4. 研究侧引用的编号都还在新表里（应为 0；account_id 只在设备行上的旧式档案除外）
SELECT count(*) FROM research_identity_map m
WHERE m.internal_user_id IN (SELECT account_id FROM account_links)
  AND m.internal_user_id NOT IN (SELECT account_id FROM account_identities);
```

核对无误、并先做过数据库备份后，清理：

```sql
DROP TABLE account_links;
```

`app_migrations` 那一行不要删：删了之后旧表若还在，下次启动会再抄一遍。

## 待完善（骨架未覆盖）
- Alembic 数据库迁移（当前用 `create_all` 开发建表，生产首部署即建表）
- `weeklyNewStudents` 周新增统计
- `POST /api/feedback/llm`（后期接入 Qwen3-Omni 动态反馈，替换模板库）
- 速率限制 / 生产级鉴权细化 / HTTPS 由平台终结
