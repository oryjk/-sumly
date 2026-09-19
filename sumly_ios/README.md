# sumly_ios - 记金 iOS 端

SwiftUI 原生实现，首个功能：首页查看国际金价（伦敦金 XAU/USD）**日线走势**。

## 当前首页：高保真 UI + Go 行情

首页保留参考稿的布局、字号、配色、留白和底栏，去除小程序服务胶囊。
大字价格采用 Go `/market/gold/quote` 返回的 `cny_per_gram`，单位元/克。
「实时」使用 `/market/gold/realtime` 最近二十分钟的五秒采样（约240个点），「近一月 / 近三月」
使用 `/market/gold/daily` 的真实日线。实时样本按采样时汇率折算并固定保存，历史日线按最新 `usd_cny` 折算人民币/克，
不是历史人民币成交价或品牌零售金价；页面注明换算口径。
报价与秒级曲线每 5 秒刷新，日线每分钟刷新；切后台暂停，返回前台立即刷新。
首次加载显示带动画的独立加载页面，后台刷新保留已有行情；加载失败提供重试，暂无走势显示空状态。用户文案不展示采样间隔等实现细节，不使用参考数据兜底。上游旧报价保留原时间并显示最近报价时间。
实时图支持选点查看真实价格和服务端采样时间；纵轴留出至少一元的范围，使用半元边界避免微小价格变化拉伸整图。
Go 采样持久化到 PostgreSQL 并保留以最后有效行情为终点的20分钟（停更不会清空）；重启恢复窗口，上游失败不补点。日线按交易日长期保存，由后台每分钟刷新。
「攒金」进入已有本地持仓页，中央加号复用添加黄金表单。
订阅推送、记账和个人中心尚未开放，不会模拟成功。

## 技术选型

| 项 | 选择 | 说明 |
| --- | --- | --- |
| UI | SwiftUI + `@Observable` | iOS 17 起 |
| 图表 | Swift Charts | `chartXSelection` 十字光标、区间最高/最低标注、悬浮气泡 |
| 并发 | Swift 6 严格并发 | async/await，服务层 `Sendable` |
| 工程 | XcodeGen | `project.yml` 声明式生成 `.xcodeproj`（产物不入库） |
| 测试 | Swift Testing | 解析 / 区间切片 / ViewModel 编排 |
| 依赖 | 无 | 零第三方依赖 |

## 视觉方向

「深色 + 金」行情主题（对齐产品参考稿）：近黑底 `#16161A`、金黄强调 `#F5C842`、
胶囊分段选择器、超大圆体数字；涨跌遵循国内习惯红涨绿跌。
全部颜色/形状集中在 `Sumly/Sources/DesignSystem/GoldTheme.swift`，页面禁止散落硬编码。

## 常用命令

```bash
cd sumly_ios
make open      # 生成工程并用 Xcode 打开（推荐日常入口）
make build     # 生成 + 模拟器编译
make test      # 生成 + 模拟器跑单测
make generate  # 仅重新生成 .xcodeproj
```

命令行直连：

```bash
xcodegen generate
xcodebuild -project Sumly.xcodeproj -scheme Sumly \
  -destination 'platform=iOS Simulator,name=iPhone 17' test
```

换模拟器：`make test SIM="iPhone 17 Pro"`。

## 数据源

默认走 `../sumly_go` 后端行情接口（`BackendGoldPriceService`）：

- `GET /api/v1/app/market/gold/quote` 实时报价（含 `usd_cny` 汇率与 `cny_per_gram`
  每克人民币价），行情页与持仓页各以 3 秒轮询，最新价就地写入当日 K 线（跨日自动追加新 bar）
- `GET /api/v1/app/market/gold/daily` 日线序列，启动 / 下拉刷新时拉取

后端负责从新浪财经抓取（hf_XAU + fx_susdcny 实时、日线 JSONP）并做短 TTL 缓存与降级；
iOS 只消费 `{code,message,data}` envelope。`SinaGoldPriceService` 保留为直连新浪的
备用实现（解析逻辑带单测），不在 App 默认链路中使用。

开发联调：模拟器默认连 `http://127.0.0.1:18090/api/v1`（ATS 已放行本地网络）；
真机需把 `BackendGoldPriceService.defaultBaseURL` 改成 Mac 的局域网 IP。

## 功能

- **行情页**：Go 行情驱动的人民币/克报价，分钟线 / 一月日线 / 三月日线，实时报价 3 秒轮询
- **持仓页**：添加持有的黄金克数与买入单价（默认按当前金价），SwiftData 本地保存；
  每条记录带**精确持有时点**（可补录过去时间，为后续走势/收益曲线对齐历史行情预留），
  汇总卡实时计算 购入总价 / 最新估值（克数 × 元/克）/ 预估收益（红涨绿跌），支持左滑删除

## 关键目录

```text
project.yml                 # XcodeGen 工程声明（target/Info.plist/scheme）
scripts/make_appicon.py     # 生成 1024 AppIcon（Pillow，可选）
Sumly/Sources/
  App/                      # 入口（TabView + ModelContainer）
  DesignSystem/             # GoldTheme 令牌 + 卡片/胶囊/主按钮样式
  Features/Home/            # 行情页：视图、ViewModel、区间切片
  Features/Holdings/        # 持仓页：SwiftData 记录、统计计算、ViewModel、视图与表单
  GoldMarket/               # 金价/报价模型、数据源协议与实现
Sumly/Resources/
  Assets.xcassets           # 图标、强调色、启动底色
Tests/                      # Swift Testing 单测
```

## 已知边界

- 持仓记录暂存本地 SwiftData（单机）；后端账号体系就绪后迁移为云端同步
- 深色单主题（`preferredColorScheme(.dark)`），亮色模式待令牌扩展
- 实时报价 3 秒轮询仅在页面驻留时进行，轮询失败静默保留旧值；
  空数据时刷新失败才进入失败态
- 真机运行需在 Xcode 里配置签名团队（模拟器无需）

## 攒金页面

攒金页按参考图显示账本、总克数、购入总价、预估价值、收益及品牌卡片。估值使用 Go 的 `instruments/au9999/quote`；行情首页仍使用原先的伦敦黄金接口。

支持本地多账本、品牌/备注搜索、盈亏筛选、排序、金额隐藏、购入日历、部分/全部赠卖、迁移及删除确认。保存失败会回滚并提示；持仓仍保存在设备的 SwiftData 中，没有上传到 Go。

`HoldingRecord` 新增字段均提供默认值或为可选字段，供旧数据轻量迁移。赠卖保存原始购入日期和单价，部分处置拆分记录，已处置部分不再计入当前估值。

Debug 可通过启动参数 `--holdings-design-preview` 对照参考图：只使用独立的内存数据库和示例报价，不写入真实持仓。正常启动不加载示例。
