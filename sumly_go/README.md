# sumly_go

sumly 小程序后端。Go 1.26.5 + Gin + PostgreSQL（pgx/v5 + goose 迁移 + sqlc 代码生成），
六边形架构：`internal/<module>/{domain,application,ports,adapters}`。架构与工程约定见 [AGENTS.md](AGENTS.md)。
模块路径：`gitee.com/oryjk/sumly/sumly_go`（monorepo：`gitee.com/oryjk/sumly`）。

## 当前能力

- `POST /api/v1/app/auth/wechat/login`：微信登录（js_code 换 openid，用户不存在自动注册，签发 24h JWT）
- `GET /api/v1/app/users/me`：获取当前用户（需 Bearer Token）
- `PATCH /api/v1/app/users/me`：更新昵称 / 真实姓名（需 Bearer Token）
- `GET /api/v1/app/market/gold/quote`：伦敦金实时报价（公开接口；服务端短 TTL 缓存，
  上游故障时退回最近一次缓存）
- `GET /api/v1/app/market/gold/daily`：伦敦金日 K 线（2006 年至今，公开接口）
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

所有表放在**独立 schema `sumly`**，不占用 public schema，因此可与其他项目安全共用
同一个 PostgreSQL 实例（连接信息见 `.env` 的 `DATABASE_URL`）：

- `DATABASE_URL` 通过 `search_path=sumly` 指定 schema，迁移版本表（goose_db_version）也落在该 schema；
- 首次接入某个实例前，需执行一次 `CREATE SCHEMA IF NOT EXISTS sumly;`；
- 各项目的表互不可见、互不影响；
- DSN 含 `&` 时，`.env` 里的值必须加双引号，否则 make 目标以 shell 方式加载 `.env` 时会被拆断。

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

### 黄金分时接口

`GET /api/v1/app/market/gold/intraday` 返回最新交易日分钟线：
`{code:0,message:"ok",data:{symbol:"XAUUSD",points:[{time:"RFC3339",price:4350}]}}`。
价格单位美元/盎司；服务端缓存 15 秒，失败返回原时间戳缓存，无缓存时报错。
客户端可结合 quote 的 usd_cny 折算，最新汇率折算值不代表历史人民币成交价。

### 黄金五秒采样

`GET /api/v1/app/market/gold/realtime` 返回 `{symbol,unit:"CNY/g",interval_seconds:5,window_seconds:1200,points}`。
服务启动后持续每5秒读取一次真实上游报价，按采样时汇率折算，每个5秒切片最多保留一条。
每点有服务端采样 `time`、上游时间 `source_time` 和人民币/克 `price`，上游时间可能只有分钟精度。
请求失败不创建新点，报价超过120秒不采入，历史样本不会随最新汇率变化。
采样持久化到 `gold_realtime_samples`，保留以最新有效行情时间为终点的20分钟。清理依据数据库中的最新行情时间，停更、休市或重启不会让最后窗口过期；新行情到来后窗口才推进。
停更时接口末点使用上游最后报价时间及价格。若该窗口没有可用秒级走势，回退到上游真实分钟记录并返回 `interval_seconds:60`，按最新可用汇率折算；不插值、不写入五秒采样库。正常采样返回 `interval_seconds:5`。
日线写入 `gold_daily_bars`，按交易日幂等更新 OHLC，不自动删除历史。后台启动即同步上游可用历史，之后每分钟刷新当日数据；无需客户端访问。
历史日线单位仍为美元/盎司；秒级样本为采样时汇率折算的人民币/克。服务停机期间的秒级数据无法补采，日线恢复连接后可补齐上游提供的数据。

### 多品种黄金接口

`GET /api/v1/app/market/gold/instruments` 返回品种目录。每个品种有明确的 `kind`、`currency`、`unit`、`quote_source`、`daily_source`、`delay_seconds`；只有已核实的期货才返回 `exchange` 与 `contract`。

| ID | 品种 | 报价源 / 日线源 | 原始单位 |
| --- | --- | --- | --- |
| `au9999` | 上金所 Au99.99 现货 | 新浪 `gds_AU9999` / 上金所 `graph/Dailyhq` | `CNY/g` |
| `xauusd` | 伦敦现货 XAU/USD | 新浪 `hf_XAU` / 新浪 XAU 日线 | `USD/troy_oz` |
| `comex-gold` | COMEX 2026年12月期货 GCZ26 | Yahoo `GCZ26.CMX` / 同一合约日线 | `USD/troy_oz` |

接口：

- `GET /api/v1/app/market/gold/instruments/{id}/quote`
- `GET /api/v1/app/market/gold/instruments/{id}/realtime`
- `GET /api/v1/app/market/gold/instruments/{id}/daily`

每个响应包含 `instrument` 元数据。`quote.price` 是原始单位价格；`cny_per_gram` 是辅助折算（国内为原价，美元品种汇率缺失时为0）。走势图和日线保持该品种原始单位。未知 ID 返回404，不接受用户传入上游地址。

采样写入独立的 `gold_native_samples`，按品种的最新有效事件时间保留20分钟；日线按 `symbol + trading_date` 长期保存。停更及重启不清空最后窗口。国内尚无可确认绝对时间的分钟历史回退，首次启动时不能补造过去的五秒样本；可能只有最后报价一个点。伦敦及 COMEX 可以回退到真实分钟记录，返回 `interval_seconds:60`。

COMEX 数据源为延迟报价，标记 `delay_seconds:1800`，不是交易所实时流。重复轮询延迟报价不生成新事件，采样时间使用实际行情时间。当前固定为经核实的 `GCZ26.CMX`，不自动换月、不称为“主力连续”；后续换约需更换 bootstrap 中的合约配置，数据库会按新的合约代码隔离历史。参考 [Yahoo 合约页](https://finance.yahoo.com/quote/GCZ26.CMX/) 与 [数据延迟说明](https://help.yahoo.com/kb/SLN2310.html)。

旧 `/market/gold/{quote,realtime,daily,intraday}` 仍表示伦敦黄金，旧实时图仍为 `CNY/g`，供现有 iOS 使用；本次未更改前端。旧报价开盘字段同时纠正为新浪第8项（第2项实际是买价）。

六边形职责：`domain` 描述品种、报价与窗口；`application` 编排行情缓存、采样、窗口及历史；`ports` 描述报价、日线、分时与存储能力；`adapters/sina|sge|yahoo` 请求供应商，`adapters/feed` 组合不同来源，`adapters/postgres` 使用 sqlc，`adapters/http` 只处理协议与 DTO；`bootstrap` 完成注入及采集生命周期管理。
