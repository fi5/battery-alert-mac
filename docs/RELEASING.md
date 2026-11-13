# 发布流程

1. 更新 `VERSION`，运行 `python3 scripts/test.py`。
2. 运行 `python3 scripts/build.py`，确认两种架构均编译通过。
3. 在桌面会话中打开构建出的 App，检查菜单栏、通知权限、通知测试、阈值保存和登录时启动。退出后确认菜单栏图标消失。
4. 运行 `python3 scripts/package.py`。在另一目录打开 DMG，确认 App、Applications 快捷方式及安装说明均存在。
5. 将包含 VERSION 更新的提交推送到 main。
6. Release 工作流会重新测试、构建通用 App，生成 DMG、ZIP、校验文件，并创建对应的 tag 和 Release。已存在的版本会跳过，不会覆盖发行包。

发布工作流也可在 Actions 手动运行，读取 main 分支的 VERSION；创建公开仓库后首次上传 VERSION 也会触发发行。

## 签名与公证

默认使用临时签名，仅提供代码完整性检查，不提供已验证开发者身份。不要将临时签名版本称为已通过 Apple 公证。

使用 Developer ID 时，在本机配置证书，然后：

```sh
CODESIGN_IDENTITY="Developer ID Application: Your Name (TEAMID)" python3 scripts/build.py
```

此模式启用 hardened runtime 和签名时间戳。正式分发前，还需使用自己的 Apple 开发者账号将 App 提交到 notary service，等待成功并 staple，再制作 DMG。证书、私钥和公证凭据不得加入仓库。

```sh
APP_PATH="$(cat build/latest-app.txt)"
ditto -c -k --keepParent "$APP_PATH" build/Notarization.zip
xcrun notarytool submit build/Notarization.zip --keychain-profile YOUR_PROFILE --wait
xcrun stapler staple "$APP_PATH"
python3 scripts/package.py
```

每次发行后检查下载到的 DMG 校验值。已存在的发行文件不会被本地打包脚本覆盖；修改 VERSION 或选择新的输出目录。
