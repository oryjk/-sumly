# sumly_mini - AGENTS

## 项目定位

sumly 微信小程序 / H5 端，技术栈 `uni-app + Vue 3 + TypeScript + Vite + @wot-ui/ui`，
对接 `../sumly_go` 后端（响应 envelope 为 `{ code, message, data }`）。

## 常用命令

```bash
cd sumly_mini
bun install
bun run dev:mp-weixin
bun run build:mp-weixin
bun run dev:h5
bun run build:h5
bun run type-check
```

## 关键目录

```text
src/
  api/           # 按业务域封装接口
  components/    # 通用组件（暂空，按需创建）
  config/        # 环境配置（API 根路径）
  mock/          # VITE_USE_MOCK 开发数据（全有或全无）
  pages/         # 小程序页面
  static/        # 静态资源
  stores/        # 模块级 reactive 会话与全局状态
  types/         # 类型定义
  utils/         # 请求、登录态存储、工具方法
```

## 协作约定

- 页面逻辑、接口封装、通用工具保持分层，不要把所有请求直接散落在页面里。
- 新增接口优先放入 `src/api/<domain>.ts`，并补充对应类型（`src/types/`）。
- 登录态只通过 `src/stores/appSession.ts` 与 `src/utils/authStorage.ts` 读写，
  页面不要直接操作 token 存储。
- 修改核心流程时，确认字段与后端真实 JSON 一致；后端契约见 `../sumly_go/docs/openapi.yaml`。
- 小程序环境差异较多，避免随意引入仅适用于 Web 的 API。
- 页面 SFC 默认只承担页面编排：生命周期、加载状态、页面级表单状态、导航和组件事件 wiring。
- 页面专属组件放在 `src/pages/<domain>/components/`；只有稳定跨页面复用的组件才放进 `src/components/`。
- mock 模式必须“全有或全无”：新接口要么补 mock handler，要么明确关闭 `VITE_USE_MOCK`。
- `manifest.json` 的 `mp-weixin.appid` 需替换为真实小程序 appid（当前为占位 `touristappid`），
  且必须与后端 `WECHAT_APP_ID` 一致。
