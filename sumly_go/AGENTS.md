# sumly_go - AGENTS

## 项目定位

sumly 的 Go 后端，六边形架构：`internal/<module>/{domain,application,ports,adapters}`
分层，具体约束见下「架构约束」。当前已实现认证（微信/开发登录，以及原生 Apple、
+86 手机验证码、邮箱注册/密码登录/重置）、用户资料与黄金行情模块。

本项目最低工具链为 Go 1.26.5。

## 推荐定位位置

1. `internal/bootstrap` 和目标模块 `adapters/http`
2. HTTP DTO / handler
3. application use case
4. ports
5. adapters/postgres 与 `db/queries`
6. `db/migrations`

## 架构约束

- 按业务模块组织：`internal/<module>/domain|application|ports|adapters`。
- 新功能优先形成小而高内聚的 use case，不建立全局巨型 service。
- `domain` 不依赖 Gin、pgx、sqlc 或外部 SDK。
- `application` 只依赖 domain 和 ports，负责业务编排和权限规则。
- `ports` 定义模块需要的外部能力，不依赖 adapter。
- Gin 与 `gin.Context` 只能出现在 `adapters/http` 和 `bootstrap`。
- SQL、pgx、sqlc 只能出现在 `adapters/postgres` 和数据库工具中。
- handler 只做协议适配、Actor 提取、DTO 转换和错误映射。
- 用户端与管理端使用独立的 `/api/v1/app`、`/api/v1/admin` 路由组（管理端尚未实现）。
- 开发测试专用登录：`POST /api/v1/app/auth/dev/login`（identifier 加 `dev-` 前缀当 openid，
  自动注册并签发 JWT），仅 `DEV_LOGIN_ENABLED=true` 时注册路由，生产环境必须保持关闭。
- 原生认证需迁移 `00004_native_auth.sql` 后显式开启 `NATIVE_AUTH_ENABLED`；提供商配置缺失时
  关闭对应能力，不允许生产假验证码或控制台明文验证码。
- `/auth` 原生契约见 `docs/openapi.yaml`。身份来自独立 verified identities，不得用可编辑资料
  字段或 Apple 邮箱相等来合并账户。OTP/配额/会话必须数据库原子操作，不用进程内状态替代。
- 原生 JWT 必须经过实时会话校验；旧微信/开发 JWT 解析必须拒绝原生标记。刷新历史关联会话族，
  防止刷新已提交后携旧 token 退出仍残留有效会话。重置密码撤销全部原生会话。
- Apple nonce、code、JWT、短信/邮件验证码、refresh token 和密码均不得记录日志或返回调试值。
- 响应统一使用 `{ code, message, data }` envelope（`shared/http/response.go`）。

## 开发约束

- 后端业务行为按 TDD 推进：先确认失败测试，再写最小实现。
- 新增 SQL 前先确认 migration 和现有 query，禁止臆造字段。
- 不使用重型 ORM；查询通过 sqlc 生成类型（`make generate`）。
- 日常 schema 变更用 `go run ./cmd/dbmigrate`（不要用 `go run goose@version`，CLI 驱动依赖不在 go.sum）。
- Go 模块下载使用 `GOPROXY=https://goproxy.cn,direct`，校验使用 `GOSUMDB=sum.golang.google.cn`；不要关闭公开依赖的 checksum 校验。
- 不记录 JWT、微信 code、AppSecret、数据库连接串等敏感信息。
- PostgreSQL 集成测试通过 `internal/testsupport` 为每个用例创建独立随机 schema，任何测试都不得 TRUNCATE 共享业务表。
- PostgreSQL 集成测试只使用显式 `TEST_DATABASE_URL`，不得回退连接 `DATABASE_URL` 或为测试启动 Docker。

## 验证

```bash
gofmt -w .
go test ./...
go vet ./...
go build -o /tmp/sumly-go-api ./cmd/api
```

未运行的验证必须在最终回复中说明原因。
