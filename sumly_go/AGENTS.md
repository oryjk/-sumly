# sumly_go - AGENTS

## 项目定位

sumly 小程序的 Go 后端。架构与工程约束沿用 `registration_system_go` 的六边形架构；
当前阶段只实现了微信注册登录与用户资料闭环，后续业务模块按相同模式扩展。

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
- `domain` 不依赖 Gin、pgx、sqlc 或外部 SDK。
- `application` 只依赖 domain 和 ports，负责业务编排和权限规则。
- `ports` 定义模块需要的外部能力，不依赖 adapter。
- Gin 与 `gin.Context` 只能出现在 `adapters/http` 和 `bootstrap`。
- SQL、pgx、sqlc 只能出现在 `adapters/postgres` 和数据库工具中。
- handler 只做协议适配、Actor 提取、DTO 转换和错误映射。
- 用户端与管理端使用独立的 `/api/v1/app`、`/api/v1/admin` 路由组（管理端尚未实现）。
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
