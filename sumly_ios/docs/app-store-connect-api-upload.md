# App Store Connect API Key 自动上传

项目使用 App Store Connect API Key 进行命令行上传，不依赖 Xcode GUI 的 Apple Account 会话。

## 本机私有配置

配置文件固定放在仓库外：

`~/.config/sumly/appstore-connect.env`

内容：

```bash
ASC_KEY_ID=<Key ID>
ASC_ISSUER_ID=<Issuer ID>
ASC_KEY_PATH=$HOME/.private_keys/AuthKey_<Key ID>.p8
```

私钥放在：

`~/.private_keys/AuthKey_<Key ID>.p8`

建议权限：

```bash
chmod 600 ~/.config/sumly/appstore-connect.env
chmod 600 ~/.private_keys/AuthKey_<Key ID>.p8
```

不要把 `.p8`、Key 内容或本机配置提交到 Git。

## 上传

在 `sumly_ios` 目录：

```bash
make upload
```

脚本会：

1. 读取当前 `project.yml` 生成的版本号和 build number。
2. 使用 API Key 进行 Release Archive。
3. 使用同一 API Key 自动签名并上传到 App Store Connect。
4. 保持项目中的 build number，不让上传流程自动改号。

入口脚本：`scripts/upload_app_store.sh`。
