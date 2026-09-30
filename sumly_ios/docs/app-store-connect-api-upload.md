# App Store Connect API Key 自动上传

项目使用 App Store Connect API Key 进行命令行上传，不依赖 Xcode GUI 的 Apple Account 会话。

## 本机私有配置

优先读取仓库外配置：

`~/.config/sumly/appstore-connect.env`

如果不存在，则读取项目内、但已被 Git 忽略的：

`.appstore-connect.env`

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

## 验证鉴权

在 `sumly_ios` 目录：

```bash
make upload-auth-check
```

这个命令只读取 App Store Connect 的 App 列表，不上传 build。

## 上传

在 `sumly_ios` 目录：

```bash
make upload
```

脚本会：

1. 读取当前 `project.yml` 生成的版本号和 build number。
2. 使用 API Key 进行 Release Archive。
3. 使用本机 Apple Distribution 证书和匹配的 App Store 描述文件签名，通过 API Key 上传到 App Store Connect。
4. 保持项目中的 build number，不让上传流程自动改号。

入口脚本：`scripts/upload_app_store.sh`。

## 分发签名

当前 API Key 可以管理证书和描述文件，但云签名请求返回 403，因此导出采用本地签名。

- 登录钥匙串已安装 `Apple Distribution: RUI WANG (237PA3LEYJ)`。
- 本机已安装 `Sumly API App Store Distribution` 描述文件，匹配 `com.oryjk.sumly`。
- 证书私钥保存在仓库外 `~/.private_keys/sumly-distribution/`，目录权限 `700`，私钥权限 `600`。
- 证书与描述文件于 2027-09-30 到期；更换证书后需要同步更新 `ExportOptions-upload.plist` 中的证书指纹。

换电脑时需要安装匹配的证书私钥及描述文件；仅复制 API Key 不能完成本地签名。
