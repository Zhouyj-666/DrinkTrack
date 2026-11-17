# 小酌场 / SipSession 账号服务（第一期）

本地可运行的注册 / 登录后台。这一期只用**邮箱 + 密码**，不依赖 Apple 开发者计划，也不依赖国内短信资质。

手机 App 仍然可以不登录使用。登录之后，本机已有的饮酒记录会挂上账号 id，方便以后做云端同步。心率、血氧等 HealthKit 数据**不会**上传到这台服务器。

## 目前提供的接口

| 方法 | 路径 | 说明 |
|------|------|------|
| `GET` | `/health` | 健康检查（含数据库是否可达） |
| `POST` | `/v1/auth/register` | 注册（邮箱、密码、可选显示名），成功即登录 |
| `POST` | `/v1/auth/login` | 登录 |
| `POST` | `/v1/auth/logout` | 注销当前会话（需要 `Authorization: Bearer <token>`） |
| `GET` | `/v1/auth/me` | 当前登录用户 |

请求示例：

```json
POST /v1/auth/register
{ "email": "you@example.com", "password": "at-least-8", "display_name": "小酌" }
```

成功时返回会话 token 和用户信息。失败时返回中文 `message`，例如「该邮箱已注册」「邮箱或密码不正确」「邮箱格式不正确」。

## 在这台 Windows 电脑上启动

需要先安装 [Docker Desktop for Windows](https://www.docker.com/products/docker-desktop/)（个人使用免费）。安装完成后确保 Docker 正在运行。

在 `E:\DrinkTrack\server` 目录：

```powershell
copy .env.example .env
# 把 .env 里的 API_SECRET 改成一段足够长的随机字符串
docker compose up --build
```

启动成功后，本机地址是：

- API：`http://127.0.0.1:8000`
- 健康检查：在浏览器打开 `http://127.0.0.1:8000/health`，应看到 `"status": "ok"`

停止：`docker compose down`。数据在 Docker volume `drinktrack_pgdata` 里，不会因为停服务而丢失。若要清空数据库：`docker compose down -v`。

## 让同一 Wi-Fi 下的 iPhone 访问

模拟器可以用 `http://127.0.0.1:8000`。真机不行，因为 127.0.0.1 指向手机自己。

1. 电脑和 iPhone 连同一个 Wi-Fi。
2. 在 PowerShell 里查看电脑的局域网 IP：

```powershell
Get-NetIPAddress -AddressFamily IPv4 |
  Where-Object { $_.IPAddress -notlike "127.*" -and $_.PrefixOrigin -ne "WellKnown" } |
  Select-Object IPAddress, InterfaceAlias
```

常见是 `192.168.x.x`。避开 `172.17` / `172.18` 这类 Docker 虚拟网卡地址。

3. 如有 Windows 防火墙提示，允许 8000 端口入站。可在管理员 PowerShell 里执行：

```powershell
New-NetFirewallRule -DisplayName "DrinkTrack API (local dev)" -Direction Inbound -Protocol TCP -LocalPort 8000 -Action Allow
```

4. 在 App 的登录页把「开发服务器地址」改成 `http://192.168.x.x:8000`（换成你的实际 IP）。
5. 用浏览器在手机上打开 `http://192.168.x.x:8000/health` 先确认能通。

开发阶段 App 已开启 `NSAllowsLocalNetworking`，允许访问局域网 HTTP。这只适合本机调试。

**正式上线必须改用 HTTPS，并部署到一台小的 VPS。** 不要把现在的 HTTP 地址和默认密钥直接暴露到公网。本期没有购买云主机、域名或邮件服务。

## 密码与会话（安全说明）

- 密码只在服务器用 Argon2 哈希存储，永远不以明文落库。
- 登录下发不透明的随机会话 token。数据库里只存 `API_SECRET` 参与的 SHA-256 哈希，不存原始 token。
- 退出登录会把该条会话标记为已撤销（`revoked_at`）。过期时间由 `TOKEN_TTL_DAYS` 控制（默认 30 天）。
- App 把 token 存在 iOS Keychain，不进 UserDefaults。

以后如果要换成有签名的 JWT，仍然建议保留这张 `sessions` 表做撤销。

## 数据表

- `users`：`id`、`email`（唯一）、`password_hash`、`display_name`、`created_at`、`phone`（可空，留给以后的短信登录，本期不用）
- `sessions`：`id`、`user_id`、`token_hash`、`created_at`、`expires_at`、`revoked_at`
- `sync_cursors`：以后做饮酒记录同步的扩展点（`user_id`、`last_pull_at`、`last_push_at`）。本期不写业务数据，也不把 Core Data 迁到云端。HealthKit 样本不会出现在这些表里。

## 以后要接、但本期故意没做的

- 通过 Apple 登录（需要加入 Apple 开发者计划）
- 手机号验证码（需要企业资质和短信签名备案）
- 邮件验证码（避免做一条发不出信的「我们已发送验证码」路径）
- 好友 / 聊天 / 朋友圈
- 完整的云端同步引擎
- 生产环境部署

服务端为以后的登录方式留了注释和 `users.phone` 字段，但 App 里不会放一个点了却没反应的按钮。

## 本地跑接口测试

测试默认使用内存 SQLite，不依赖 Docker：

```powershell
python -m venv .venv
.\.venv\Scripts\Activate.ps1
pip install -r requirements.txt
$env:DATABASE_URL = "sqlite+pysqlite:///:memory:"
$env:API_SECRET = "test-secret"
pytest -q
```
