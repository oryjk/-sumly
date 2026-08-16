# sumly

小程序 + 后端一体化 monorepo（`git@gitee.com:oryjk/sumly.git`），应用中文名「记金」——
记录黄金等个人资产，按最新行情计算市值与每日涨跌。
技术栈与架构完全沿用 `registration_system` 项目的工程模式：

| 子项目 | 说明 | 参考项目 |
| --- | --- | --- |
| [`sumly_go/`](sumly_go/) | Go 后端：Gin + PostgreSQL(pgx/goose/sqlc) + JWT，六边形架构 | `registration_system_go` |
| [`sumly_mini/`](sumly_mini/) | 用户端：uni-app + Vue 3 + TypeScript + Vite + @wot-ui/ui | `registration_system_mini` |

## 当前完成

- 微信注册登录闭环：`uni.login` → `POST /api/v1/app/auth/wechat/login`（js_code 换 openid，
  用户不存在自动注册）→ 24h JWT → 受保护接口 `GET/PATCH /api/v1/app/users/me`。
- 会话管理：token 本地存储与自动恢复、手动退出阻止静默重登、H5 游客态降级。
- 工程配套：goose 迁移、sqlc 生成、内嵌 OpenAPI 文档（`/api/docs`）、Makefile、Dockerfile、
  单元测试 + 可跳过的 PostgreSQL 集成测试、mock 模式（`VITE_USE_MOCK=true`）。

## 数据库

与 `registration_system_go` 共用同一个 PostgreSQL 实例与 database，sumly 的表放在独立
schema `sumly`（`DATABASE_URL` 带 `search_path=sumly`），两边数据与迁移历史完全隔离。
集成测试使用实例上现成的 `registration_go_test` 库（每用例随机 schema，自动回收）。

## 本地联调

```bash
# 后端（需本地 PostgreSQL，详见 sumly_go/README.md）
cd sumly_go
cp .env.example .env   # 已有占位 .env，可直接试用
make migrate-up
make run               # 默认 :18090

# 小程序
cd sumly_mini
bun install
bun run dev:h5            # H5 调试
bun run dev:mp-weixin     # 产物 dist/dev/mp-weixin，用微信开发者工具打开
```

真实微信登录需要把 `sumly_go/.env` 的 `WECHAT_APP_ID/WECHAT_APP_SECRET` 与
`sumly_mini/src/manifest.json` 的 appid 换成同一个真实小程序的值。

各子项目的架构约束与协作约定见各自目录下的 `AGENTS.md`。
