# sumly_ios - AGENTS

## 项目定位

sumly 的 iOS 原生端，`SwiftUI + Swift 6 + Swift Charts + XcodeGen`，iOS 17 起。
当前功能：首页国际金价（伦敦金 XAU/USD）日线走势；行情暂直连新浪财经，
登录与资产能力后续接 `../sumly_go`。

## 常用命令

```bash
cd sumly_ios
make generate   # 改完 project.yml 后重新生成 .xcodeproj（不要手改工程文件）
make build      # 模拟器编译
make test       # 模拟器跑单测（Swift Testing）
make open       # 生成并用 Xcode 打开
```

## 关键目录

```text
project.yml                # 工程声明（改 target/依赖/Info.plist 在这里）
Sumly/Sources/
  App/                     # 应用入口
  DesignSystem/            # GoldTheme 令牌 + 通用卡片/胶囊样式
  Features/Home/           # 首页（视图、ViewModel、PriceRange 切片）
  GoldMarket/              # 金价模型 + GoldPriceServicing 协议与实现
Sumly/Resources/           # Assets.xcassets
Tests/                     # 单测（解析/切片/ViewModel）
scripts/make_appicon.py    # AppIcon 生成脚本（Pillow，可选）
```

## 协作约定

- 工程由 XcodeGen 生成，`.xcodeproj` 不入库：新增/删除文件后必须 `make generate`，
  工程结构改动只改 `project.yml`。
- 视觉只允许引用 `DesignSystem/GoldTheme.swift` 的令牌（深色 + 金行情风），
  页面禁止硬编码颜色/形状；涨跌配色遵守国内习惯：红涨（`up`）绿跌（`down`）。
- 行情默认走后端 `BackendGoldPriceService`（`/api/v1/app/market/gold/*`），
  实时报价由各页 ViewModel 每 3 秒轮询（行情页写入尾根 K 线，持仓页用于元/克估值）；
  `SinaGoldPriceService` 为直连新浪的备用实现。数据源改动只动协议实现与注入处，
  不要在视图里直接发请求。
- 持仓记录用 SwiftData（`Features/Holdings/HoldingRecord`），`timestamp` 是用户指定的
  精确持有时点（可补录历史），改字段需考虑本地迁移；汇总/收益计算集中在
  `HoldingsStats` 纯函数，别在视图里散落算式。
- 新功能目录 `Sumly/Sources/Features/<Name>/`：View + ViewModel（`@MainActor @Observable`）
  + 纯逻辑类型分离，纯逻辑（解析、切片等）必须有对应单测。
- Swift 6 严格并发：服务层 `Sendable`，可变共享状态用 actor，不用 `NSLock`。
- 日期一律存「当地时区当天正午」的 `Date`（见 `SinaGoldPriceService.parseDay`），
  避免时区/夏令时导致的日期漂移。
- 单测用 Swift Testing（`import Testing`），mock 服务实现协议放测试文件内。
- 模拟器验证：`xcrun simctl install/launch` + `io screenshot` 截图目视检查新 UI。
