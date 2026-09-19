# sumly

小程序 / H5 / iOS 多端 + 后端 monorepo（`git@gitee.com:oryjk/sumly.git`），应用中文名「记金」——
记录黄金等个人资产，按最新行情计算市值与每日涨跌。
三个子项目共用同一套工程模式：按子项目分目录、每目录自带 `AGENTS.md` 架构与协作约定、
后端六边形架构 + `{ code, message, data }` 响应 envelope、前端视觉只允许引用设计令牌。

| 子项目 | 说明 |
| --- | --- |
| [`sumly_go/`](sumly_go/) | Go 后端：Gin + PostgreSQL(pgx/goose/sqlc) + JWT，六边形架构 |
| [`sumly_mini/`](sumly_mini/) | 用户端：uni-app + Vue 3 + TypeScript + Vite + @wot-ui/ui |
| [`sumly_ios/`](sumly_ios/) | iOS 原生端：SwiftUI + Swift 6 + Swift Charts + XcodeGen（iOS 17+） |

## 当前完成

- 微信注册登录闭环：`uni.login` → `POST /api/v1/app/auth/wechat/login`（js_code 换 openid，
  用户不存在自动注册）→ 24h JWT → 受保护接口 `GET/PATCH /api/v1/app/users/me`。
- 会话管理：token 本地存储与自动恢复、手动退出阻止静默重登、H5 游客态降级。
- 工程配套：goose 迁移、sqlc 生成、内嵌 OpenAPI 文档（`/api/docs`）、Makefile、Dockerfile、
  单元测试 + 可跳过的 PostgreSQL 集成测试、mock 模式（`VITE_USE_MOCK=true`）。
- 伦敦金行情服务：`GET /api/v1/app/market/gold/{quote,daily}`，六边形 `internal/market`
  模块抓取新浪实时报价（含美元/人民币汇率与每克人民币价）与日线，短 TTL 缓存，
  上游故障退回最近缓存。
- iOS 首页：按参考图高保真还原深色金价界面，展示真实人民币/克报价；
  实时五秒采样（最近二十分钟）/ 近一月 / 近三月均来自 Go 行情接口。
  秒级样本按采样时汇率保存，历史日线按最新汇率折算。
  新增公开分时接口 `GET /api/v1/app/market/gold/intraday`，缓存 15 秒并支持故障回退。
- iOS 持仓页：添加持有的黄金克数与买入单价（精确到时间点，可补录），SwiftData 本地保存，
  按实时「元/克」价自动计算购入总价 / 最新估值 / 预估收益（红涨绿跌），左滑删除。

## 数据库

sumly 的表放在独立 schema `sumly`（`DATABASE_URL` 带 `search_path=sumly`），不占用
public schema，因此可与其他项目安全共用同一个 PostgreSQL 实例，数据与迁移历史完全隔离。
首次接入一个实例需先执行一次 `CREATE SCHEMA IF NOT EXISTS sumly;`。
集成测试通过 `TEST_DATABASE_URL` 指向任意可丢弃的测试库，每个用例创建随机 schema
并在结束时自动回收（`sumly_go/internal/testsupport`）。

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

# iOS（模拟器，详见 sumly_ios/README.md）
cd sumly_ios
make open                 # Xcode 打开后直接 Cmd+R
```

真实微信登录需要把 `sumly_go/.env` 的 `WECHAT_APP_ID/WECHAT_APP_SECRET` 与
`sumly_mini/src/manifest.json` 的 appid 换成同一个真实小程序的值。

各子项目的架构约束与协作约定见各自目录下的 `AGENTS.md`。
