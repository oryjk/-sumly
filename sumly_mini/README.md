# sumly_mini

sumly 微信小程序端。uni-app + Vue 3 + TypeScript + Vite，UI 组件库 @wot-ui/ui，
架构与工程约定见 [AGENTS.md](AGENTS.md)（沿用 registration_system_mini 的分层模式）。

## 当前能力

- 首页：微信登录（`uni.login` → js_code 换 token，自动注册）、退出登录、会话状态展示
- 我的：当前用户资料展示（`GET /users/me`）、修改昵称（`PATCH /users/me`）
- 会话管理：token 本地存储、已存 token 自动恢复、手动退出后阻止静默重登
- mock 模式：`VITE_USE_MOCK=true` 时不请求后端，全部走 `src/mock/`

## 快速开始

```bash
bun install

# H5 开发（默认连本地 sumly_go，见 .env.development）
bun run dev:h5

# 微信小程序开发（产物在 dist/dev/mp-weixin，用微信开发者工具打开该目录）
bun run dev:mp-weixin
```

真机/开发者工具里使用微信登录前：

1. 把 `src/manifest.json` 的 `mp-weixin.appid` 换成真实 appid；
2. `../sumly_go/.env` 的 `WECHAT_APP_ID` / `WECHAT_APP_SECRET` 填同一小程序的密钥；
3. 开发者工具中开启「不校验合法域名」（本地 HTTP 调试）。

## 环境变量

| 变量 | 说明 |
| --- | --- |
| `VITE_API_BASE_URL` | Go App API 根路径，必须以 `/api/v1/app` 结尾 |
| `VITE_USE_MOCK` | `true` 时启用 mock 数据（全有或全无） |
| `VITE_PUBLIC_BASE` | H5 部署子路径（如 `/mini/`） |
