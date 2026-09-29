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
「记金」进入已有本地持仓页，中央加号复用添加黄金表单。
「我的」提供原生账户登录与注册。订阅推送、记账尚未开放，不会模拟成功。

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

默认根地址为 `https://oryjk.cn/sumly/api/v1`。开发联调在 `project.yml` 的
`targets.Sumly.info.properties` 设置 `SUMLY_API_BASE_URL: http://127.0.0.1:18090/api/v1`，
然后运行 `make generate`。行情与认证共用这个根地址，认证追加 `app/auth/...`，保留反代路径前缀。
认证仅允许 HTTPS 或本机 loopback HTTP；真机请使用可达的 HTTPS 测试后端，不要通过明文局域网传输密码。

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
  Features/Account/         # 我的、登录表单、Apple 原生桥接
    Core/                   # API DTO/服务协议、Keychain、会话状态机、表单校验
  GoldMarket/               # 金价/报价模型、数据源协议与实现
Sumly/Resources/
  Assets.xcassets           # 图标、强调色、启动底色
Tests/                      # Swift Testing 单测
```

## 已知边界

- 持仓记录保存在本地 SwiftData（单机）；登录不上传、不迁移、不删除持仓，尚无云同步
- 深色单主题（`preferredColorScheme(.dark)`），亮色模式待令牌扩展
- 实时报价 3 秒轮询仅在页面驻留时进行，轮询失败静默保留旧值；
  空数据时刷新失败才进入失败态
- 真机运行需在 Xcode 里配置签名团队（模拟器无需）

## 记金页面

记金页按参考图显示账本、总克数、购入总价、预估价值、收益及品牌卡片。估值使用 Go 的 `instruments/au9999/quote`；行情首页仍使用原先的伦敦黄金接口。

支持本地多账本、品牌/备注搜索、盈亏筛选、排序、金额隐藏、购入日历、部分/全部赠卖、迁移及删除确认。保存失败会回滚并提示；持仓仍保存在设备的 SwiftData 中，没有上传到 Go。

`HoldingRecord` 新增字段均提供默认值或为可选字段，供旧数据轻量迁移。赠卖保存原始购入日期和单价，部分处置拆分记录，已处置部分不再计入当前估值。

Debug 可通过启动参数 `--holdings-design-preview` 对照参考图：只使用独立的内存数据库和示例报价，不写入真实持仓。正常启动不加载示例。

### 记金日历

- 日/月/年/全部视图按交易发生日期筛选，支持农历、购入/卖出/赠出标记、关键词与跨账本筛选。
- 底部添加栏使用 safeAreaInset 预留空间，内容可滚动到按钮上方。添加表单带入所选日期和账本。
- extraFee、purchaseChannel、counterparty、purchaseID 为兼容旧记录的新字段；额外费用计入成本，部分赠卖按重量分摊费用，共享原购入编号防止重复计算笔数。
- 购入统计按购入日期，赠卖按处置日期。预估收益率是所选期间购入黄金按当前金价估值，不是历史时点收益或实际交易收益。无报价显示缺省值。
- 旧版本已拆分且未存购入编号的记录无法可靠重建关联，仍各自作为购入记录；新发生的部分赠卖保留关联。


## 原生账户认证

- **Apple**：原生 `SignInWithAppleButton`；服务端 challenge 准备好才可使用。服务端返回的 nonce 原样传给 Apple，独立生成 32 字节随机 state 并验证回传值；identity token 和 authorization code 一并交给后端验证。取消不显示错误；失败/过期后重新获取 challenge，不复用已使用的 challenge。
- **手机号**：当前仅支持中国大陆 +86，6 位验证码，首次验证成功自动注册；发送后使用服务端 `retry_after` 做基于截止时间的倒计时，切换页面不会重置同一目标的冷却。
- **邮箱**：邮箱验证码注册、密码登录、验证码重设密码。注册/重设均需确认密码；密码为 12–128 个 Unicode 码点、最多 512 UTF-8 字节，不裁剪空格、不截断。邮箱仅去首尾空白与转小写，不改写点号或加号。重设成功返回登录，不自动创建会话。注册与重设共享同一规范化邮箱目的地的发送冷却。
- **会话**：`NativeUser.provider`、字符串 `avatar_url`、可空邮箱/手机号与后端保持一致。专属 Keychain service `com.oryjk.sumly.native-auth` 使用 `kSecAttrAccessibleWhenUnlockedThisDeviceOnly` 保存会话；不保存密码/验证码。UserDefaults 只记录非敏感的退出标记，防止 Keychain 暂时不可访问时旧会话在重启后恢复；任何令牌与用户资料均不写入 UserDefaults。访问令牌失败最多刷新一次，刷新采用 single-flight；登录尝试与既有会话各自使用独立代际检查：关闭表单或登录失败只作废待完成的登录，不丢弃已提交的刷新轮换；实际退出或成功替换账户才作废旧会话操作。暂时断网保留已有会话；确实失效或 Apple 撤权则清除。
- **退出/注销**：均有确认；退出先清本地凭据，即使服务端不可达也可退出并提示限制。注销要求最近 5 分钟内主要登录，刷新不重置这个时间；后端 401/403 会要求重新验证，用户仍须再次明确确认注销。注销意图绑定原账户 ID、提供商和独立确认 ID，并在确认框显示掩码标识。重新验证仅开放原提供商，服务端返回其他账户时在保存前拒绝并尽力撤销该次未使用的会话；保留原账户凭据。成功切换账户会清除旧注销意图，重新验证本身不会自动注销。删除失败保留会话。本机游客持仓始终保留。
- **能力发现**：`GET /auth/capabilities` 控制可用方式；旧服务器 404、关闭或缺失提供商配置显示不可用/重试，不假装登录或发送成功。生产路径不包含测试验证码或模拟账户。

### 外部配置与真机验收（本次未执行）

1. 后端先完成原生认证迁移及 HTTPS 路由部署；提供商、Aliyun 签名/模板、SMTP 和 Apple 服务端密钥配置以 [后端 README](../sumly_go/README.md) 为准。客户端不内置这些密钥。
2. Apple Developer 中由项目维护者为 App ID `com.oryjk.sumly` 启用 Sign in with Apple，更新真机 provisioning profile；后端 Apple client ID/audience 必须匹配 bundle ID。Apple team/key ID、`.p8` 私钥和撤权加密密钥只配置在后端。本次没有修改门户、签名团队或 provisioning。
3. entitlement 仅在 `project.yml` 声明，由 `make generate` 输出 `Sumly/Support/Sumly.entitlements`；不手改 `.xcodeproj`。模拟器构建无需新增门户配置，真实 Apple 授权需已配置的环境与测试设备。
4. 在授权的测试环境/专用测试账号验收 Apple 首次/再次登录、取消、challenge 过期、撤权、手机号自动注册、邮箱注册/重复注册/密码重设、OTP 错误/过期/倒计时、断网恢复、退出/刷新竞争、最近登录后注销及 Apple 服务端撤权失败。**不要使用真实生产账户或发送真实消息作为自动化测试。**
5. 退出、切换账户、重设密码、注销前后检查原有 SwiftData 记录不变；检查大字号、键盘遮挡、VoiceOver、错误提示与所有表单。截图验收使用 `xcrun simctl install/launch` 和 `xcrun simctl io booted screenshot /tmp/sumly-account.png`。

### 测试与本次验证边界

`make test` 包含全部 Swift Testing 测试。`make test-auth`（或 `swift test`）仅运行可在 macOS 执行的认证核心测试，使用协议 fake，不触及网络、真实 Keychain 账户或消息提供商。这个子集不能代替完整模拟器回归。

受限执行环境可将 SwiftPM 临时产物写入可写目录：

```bash
CLANG_MODULE_CACHE_PATH=/tmp/sumly-auth-clang swift test --disable-sandbox --scratch-path /tmp/sumly-auth-package
```

2026-09-29 的验证记录分开记录如下：

- **父级 macbook-air，修复前实际结果**：协调者独立运行 `make test`，60 项 Swift 测试通过、零失败，`TEST SUCCEEDED` 时间为本地 **10:29:55**。这是完整模拟器测试的实际通过记录。
- **受限子进程，首轮实现记录**：16 项核心测试通过；该子进程的 CoreSimulator/DerivedData 访问被沙箱限制，不能据此判断项目或父级环境无法构建。该限制不适用于上面的父级验证。本轮不重复排查模拟器沙箱。
- **本轮定向修复**：核心套件 26 项通过，包含修复前实际失败的刷新/取消、注销账户绑定、跨用途邮箱冷却、关闭表单提交及隐私声明回归；保留原有退出竞争、single-flight、重设与能力关闭回归。新增退出标记测试重新创建 UserDefaults、生产 CredentialStore 与 AuthSession，并仅替换 Keychain OS 边界，确认删除失败后新实例也不会恢复旧凭据，解锁后可清除残留。
- **最终修复后的父级完整验证**：`make test` 实际通过 **73 项测试、零失败**（44 项原有功能、26 项认证核心回归、3 项账户/手机登录/邮箱登录渲染检查），随后 `make build` 成功。隐私回归读取实际 host app bundle 的 `PrivacyInfo.xcprivacy` 并通过；隐私清单与 Apple entitlement 的 `plutil -lint` 校验也通过。
- **渲染与人工验收边界**：`Tests/AccountRenderingTests.swift` 使用测试专属服务和内存凭据，生成三张真实 SwiftUI/UIKit 渲染图到测试应用临时目录，测试确认图像有效且尺寸正常；没有调用真实登录供应商。当前文件读取接口不允许访问该模拟器容器路径，因此尚未对这些图像进行人工目视检查。重新验证、注销确认、大字号及 VoiceOver 的人工交互验收仍需在本机 Simulator/真机完成，不把渲染测试等同于完整视觉验收。

### 隐私声明

应用隐私 manifest 声明姓名（Apple 全名作为昵称）、邮箱、手机号和用户标识用于 AppFunctionality，linked=true、tracking=false；保留 no-tracking 和 UserDefaults CA92.1 声明。没有声明远程收集持仓，持仓仍只在本地 SwiftData。运营方须另外更新公开隐私政策和 App Store Connect 隐私披露，使其与实际认证数据用途一致；本轮没有修改门户或发布信息。
