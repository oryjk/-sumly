# sumly_go

sumly 小程序后端。Go 1.26.5 + Gin + PostgreSQL（pgx/v5 + goose 迁移 + sqlc 代码生成），
六边形架构：`internal/<module>/{domain,application,ports,adapters}`。架构与工程约定见 [AGENTS.md](AGENTS.md)。
模块路径：`gitee.com/oryjk/sumly/sumly_go`（monorepo：`gitee.com/oryjk/sumly`）。

## 当前能力

- `POST /api/v1/app/auth/wechat/login`：微信登录（js_code 换 openid，用户不存在自动注册，签发 24h JWT）
- `GET /api/v1/app/users/me`：获取当前用户（需 Bearer Token）
- `PATCH /api/v1/app/users/me`：更新昵称 / 真实姓名（需 Bearer Token）
- `GET /health`：健康检查
- `GET /api/docs`：内嵌 OpenAPI 文档（Swagger UI）

## 快速开始

```bash
# 1. 配置环境
cp .env.example .env
# 编辑 .env：DATABASE_URL 密码、JWT_SECRET（≥32 字节）、WECHAT_APP_ID、WECHAT_APP_SECRET

# 2. 执行迁移
make migrate-up

# 3. 启动服务（默认 :18090）
make run
```

### 数据库说明（重要）

与 `registration_system_go` **共用同一个 PostgreSQL 实例和 database**
（`211.154.18.252:15432/registration_system_go`），但所有表放在**独立 schema `sumly`**：

- `DATABASE_URL` 通过 `search_path=sumly` 指定 schema，迁移版本表（goose_db_version）也落在该 schema；
- 首次接入前需在该实例执行一次 `CREATE SCHEMA IF NOT EXISTS sumly;`（已执行过）；
- 参考项目自己的表在 public schema，两边互不可见、互不影响；
- DSN 含 `&`，`.env` 里的值必须加双引号，否则 make source 时会被 shell 拆断。

`.env` 已含本地开发占位值，可直接 `make migrate-up` / `make run` 跑通健康检查；
要真实微信登录，需把 `WECHAT_APP_ID` / `WECHAT_APP_SECRET` 换成小程序后台的真实值，
且 appid 必须与小程序端 `sumly_mini/src/manifest.json` 一致。

## 常用命令

```bash
make generate      # 按 db/queries/*.sql 重新生成 sqlc 代码
make migrate-up    # 前向迁移（cmd/dbmigrate）
make test          # 单元测试（集成测试需显式 TEST_DATABASE_URL，未配置自动跳过）
make verify        # generate + fmt + test + vet + build
```

## 目录结构

```text
cmd/api/            # HTTP 服务入口
cmd/dbmigrate/      # goose 前向迁移入口
db/migrations/      # 数据库迁移
db/queries/         # sqlc 查询
docs/               # 内嵌 OpenAPI 规范
internal/bootstrap/ # 配置、依赖装配、路由、CORS、OpenAPI 挂载
internal/shared/    # 跨模块共享：Actor、错误、响应 envelope、httpapi、configenv
internal/auth/      # 微信登录用例 + JWT/微信/HTTP 适配器
internal/user/      # 用户领域、资料用例、HTTP/Postgres 适配器
internal/testsupport/ # 集成测试独立 schema 支撑
```
