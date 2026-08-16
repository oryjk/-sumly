# H5 开发测试登录 — 设计文档

日期：2026-08-16
状态：已与需求方确认

## 背景与目标

sumly 目前只有微信登录闭环（`uni.login` → `POST /api/v1/app/auth/wechat/login`）。
H5 环境没有微信 OAuth 通道，`uni.login` 不可用，前端在 H5 下无 token 时降级为游客态
（`sumly_mini/src/stores/appSession.ts` 中 `#ifdef H5` 分支直接返回）。

目标：**仅供开发测试**——在 H5 浏览器里能以任意测试用户身份拿到真实 JWT，
验证依赖用户态的功能（资料修改、后续业务模块）。明确不是面向真实用户的登录方案
（不做公众号网页授权、不做短信验证码）。

## 关键决策（已确认）

- 方案选型：**独立的 dev 登录接口**，而非复用微信登录接口换 dev 版 WechatGateway。
  理由：职责清晰、openapi 自我说明、开关未启用时路由不存在（无配置暗坑）。
- 用户标识：输入任意标识串（如 `test-user-01`），后端加 `dev-` 前缀当 openid，
  复用"查不到就自动注册"路径。理由：可随时造任意多测试用户，复用现有 user 创建闭环。

## 后端设计

### 配置开关

- `internal/bootstrap/config.go`：`Config` 增加 `DevLoginEnabled bool`，
  从 `DEV_LOGIN_ENABLED` 读取（仅 `"true"` 为真），默认 false，不参与必填校验。
- `sumly_go/.env.example` 补充 `DEV_LOGIN_ENABLED` 说明条目。
- 开关未启用时 dev 路由不注册（请求得到 404），生产环境零暴露面。
- 纵深防御：开关启用时启动日志打 warn（"dev login endpoint is enabled"），
  让生产误配在部署日志中可见。显式决策：**误配风险由部署纪律 + 启动 warn 日志兜底，
  不引入第二道开关**；不与 `APP_ENV` 联动（`LoadConfig` 缺省 `APP_ENV` 时按
  production 处理，若做 production 联动会导致本地未设 `APP_ENV` 时 dev 登录静默不可用）。

### Application 层

新文件 `internal/auth/application/dev_login.go`：

- `DevLogin` use case，依赖 `userports.Repository` 和 `ports.TokenService`
  （不依赖 WechatGateway）。
- `Execute(ctx, identifier)` 流程：
  1. trim `identifier`，校验非空、长度 ≤ 120 字符（保证 `dev-` 前缀后仍在
     openid 列 `VARCHAR(128)` 内）；不满足返回 `KindValidation`。
  2. openid = `"dev-" + identifier`。
  3. `FindByOpenID` → 未找到则 `userdomain.NewUser(openid)` + `Create`
     （与微信登录完全相同的自动注册路径）。
  4. `IsActive()` 检查，冻结返回 `KindForbidden`。
  5. `IssueUser` 签发 24h JWT。
- 返回结构复用现有 `WechatLoginResult` 同形结构（`Token` + `User`）；
  为避免语义混淆，定义独立的 `DevLoginResult`（字段相同）。

### HTTP 层

- `internal/auth/adapters/http/handler.go`：
  - `Handler` 增加可选字段 `devLogin`（接口类型，nil 表示未启用）。
  - `NewHandler` 签名扩展传入 devLogin（或新增 `SetDevLogin`，以实现时最小 diff 为准）。
  - 新增 `DevLogin` 方法：请求体 `{ "identifier": "..." }`（`binding:"required"`），
    响应与微信登录同构 `{ token, user }`（复用 `UserResponse`、`mapUserResponse`）。
  - `RegisterPublicRoutes` 内仅当 `devLogin != nil` 时注册
    `POST /auth/dev/login`。
- `internal/bootstrap/dependencies.go`：`config.DevLoginEnabled` 为 true 时才构造
  `DevLogin` use case 并注入 handler。

### OpenAPI

`docs/openapi.yaml` 增加 `POST /api/v1/app/auth/dev/login` 定义，描述明确标注
"仅开发测试，需后端 `DEV_LOGIN_ENABLED=true`，生产环境不注册该路由"；
validation 错误响应按 422 文档化（与现有 wechat login 定义风格一致，
`WriteError` 把 `KindValidation` 映射为 422）。
现有 `openapi_test.go` 保证 yaml 可解析。

## 前端设计

### API 封装

- `src/api/auth.ts`：新增 `devLogin(identifier: string)`，POST
  `/auth/dev/login`，复用现有登录响应类型（`src/types/`）。

### 会话逻辑

- `src/stores/appSession.ts`：新增并导出 `loginWithDevIdentifier(identifier)`：
  1. `sessionVersion` 快照 + `clearManualLogout()`；
  2. 调 `devLogin(identifier)`；
  3. `setAccessToken(token)`、`currentUser = user`（复用 `assertSessionVersion` 守卫）。
- 登录成功后由页面侧 `uni.$emit("session:login-completed")`，与现有微信登录按钮
  行为对齐。

### 页面

- `src/pages/home/index.vue`：`#ifdef H5` 条件下，游客卡片把"微信登录"按钮替换为
  "标识输入框（placeholder 如 `test-user-01`）+ 开发登录"按钮；空标识点击时 toast
  提示。`#ifndef H5`（小程序端）完全不变。
  **mock 模式遵循"全有或全无"约定**：`isMockEnabled()` 为 true 时不渲染开发登录入口
  （mock 模式下会话由 `bootstrapMockSession` 自动建立，该入口无意义；不补
  `/auth/dev/login` 的 mock handler）。
  首页底部 hint 文案（当前写死"登录走 …/auth/wechat/login"）在 `#ifdef H5`
  分支同步改为说明 dev 登录接口。
- `src/pages/user/index.vue`：未登录提示文案按平台区分——H5 提示使用首页开发登录入口，
  小程序保持"微信登录"文案。

## 错误处理

| 场景 | 行为 |
| --- | --- |
| `DEV_LOGIN_ENABLED` 未启用 | 路由不注册，请求返回 404 |
| identifier 为空 / 超长 | 422 validation（`WriteError` 把 `KindValidation` 映射为 422），`{ code, message }` envelope |
| 标识对应用户已冻结 | 403 forbidden（与微信登录一致） |
| 前端 H5 输入为空 | 不发请求，toast 提示 |
| 登录中重复点击 | 按钮 loading 态防重 |

## 测试计划

后端（TDD，先写失败测试）：

- `internal/auth/application/dev_login_test.go`（fake Repository / TokenService）：
  - 新标识 → 自动创建用户并签发 token，openid 带 `dev-` 前缀；
  - 已有标识 → 直接登录，不重复建用户；
  - 空 identifier / 超长 identifier → validation 错误；
  - 冻结用户 → forbidden。
- `internal/auth/adapters/http/handler_test.go`：dev 登录成功响应结构、
  缺 identifier 422、use case 错误映射。
- `internal/bootstrap/router_test.go`：开关开/关两种情形下 dev 路由存在性。
- `internal/bootstrap/config_test.go`（新文件，表驱动）：`DEV_LOGIN_ENABLED` 解析——
  仅 `"true"` 为真、缺省/其他值为 false。

前端：`bun run type-check` 通过；无单测框架，手动验证。

验证清单：

```bash
# sumly_go
gofmt -w . && go test ./... && go vet ./... && go build -o /tmp/sumly-go-api ./cmd/api
# sumly_mini
bun run type-check
```

手动联调：后端 `DEV_LOGIN_ENABLED=true` 启动，`bun run dev:h5`，浏览器输入标识登录 →
改昵称 → 刷新会话保持 → 退出后换标识再登（模拟多用户）。

## 明确不做（YAGNI）

- 不做真实用户的 H5 登录（公众号授权 / 短信验证码）。
- 不做 dev 用户的批量预置、删除或管理界面。
- 不改动小程序端任何登录行为。
- 不引入新的环境区分机制（沿用单一 `DEV_LOGIN_ENABLED` 开关，不与 `APP_ENV` 耦合，
  避免"development 自动开启"的隐式行为）。
