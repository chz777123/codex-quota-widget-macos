# Codex 周额度

macOS 26+ / arm64 + x86_64 原生 SwiftUI 应用与 WidgetKit 桌面小组件。

## 当前版本

1.1.2（build 9）。修复新版 ChatGPT 内置 Codex 路径变化；连接设置使用 macOS 原生选择窗口，支持选择应用或 CLI，详见「安装说明.md」。

应用保持运行时每 5 分钟同步，可关闭窗口继续后台运行。小组件刷新由 macOS 调度，可能晚于应用同步。

## 功能

- 本周剩余百分比、重置时间；中号额外显示更新时间。
- 只读复用本机 Codex 登录状态，通过 `codex app-server` 的 `account/rateLimits/read` 获取额度，无须 API Key，不进行模型调用。
- 优先使用多额度桶中的 `codex`，依据 10080 分钟识别周窗口，兼容周额度位于 primary 或 secondary 的返回。
- 无数据显示未知；失败保留上次数据并标记；超过 30 分钟标记数据较旧；重置时间到达后不再显示过期百分比。
- 小组件使用系统 `containerBackground` 与 `widgetAccentable`，支持系统全彩与着色渲染。透明与 Liquid Glass 背景由 WidgetKit 管理。配套应用使用原生 `glassEffect`。
- 点击小组件打开应用并同步。使用系统字体、自动外观、VoiceOver 标签与隐私敏感内容标记。

## 安装包

`CodexQuota-最新版安装包.zip` 是本地临时签名的开发构建，解压后将应用移至 Applications 并打开。

当前机器没有 Apple 开发者签名证书；本包未进行 Developer ID 签名与公证，不能视为适合向其他用户分发的正式版本。如果另一台 Mac 的系统拒绝加载扩展，应使用有效开发者签名重建。不要关闭系统安全检查。

## 编译

需包含 macOS 26 SDK 的 Apple 命令行开发工具及 Python 3，本次已使用 Swift 6.3.3 编译成功，不依赖第三方包。

```sh
./test.sh
./build.sh
```

编译产物写入终端打印的临时目录，以避免云同步目录附加的 Finder 元数据破坏代码签名。默认使用本地临时签名。如有开发者签名身份：

```sh
SIGN_IDENTITY='Apple Development: Your Name (TEAMID)' ./build.sh
```

正式分发需要按 Apple 开发者账号配置应用标识符和签名证书，并完成公证。配套应用未启用沙盒，因为它需要启动已安装的 Codex CLI；WidgetKit 扩展启用沙盒与网络客户端权限。配套应用仅监听 `127.0.0.1:52743`，小组件通过该本机地址读取不含凭据的额度快照；双方分别在自己的 Application Support 目录缓存快照，不再依赖 App Group。此端口不监听局域网；本机其他进程可读取该额度快照。此架构面向本机/Developer ID 分发，未声称符合 Mac App Store 审核要求。

## 本次修复

- 修正扩展可执行文件入口为 `_NSExtensionMain`；普通 `_main` 会在 macOS 26 上完成初始化后退出，导致系统拿不到小组件描述。
- 移除当前临时签名无权访问的共享组，改用仅本机的额度同步服务。
- 已确认系统返回 `CodexWeeklyQuota`，支持 `systemSmall`、`systemMedium`，两种尺寸预览均被系统接受。

## 1.1.1 验证记录

已通过额度解析与路径回归测试、主应用及扩展构建、严格签名验证。已在本机 macOS 27 使用新版 ChatGPT 内置 CLI 成功读取真实额度；安装后主应用本地服务与小组件缓存的成功时间和额度一致。扩展重新注册成功。

本次自动化工具没有辅助功能权限，因此选择窗口点击、取消、隐藏图标和重启后的完整 UI 回归尚未自动验证。后台图标设置及重新打开逻辑保持原实现。其他机器仍需独立验收签名与 WidgetKit 展示。

## 官方参考

- [Codex App Server：额度接口](https://learn.chatgpt.com/docs/app-server)
- [Apple：小组件着色模式与 Liquid Glass](https://developer.apple.com/documentation/widgetkit/optimizing-your-widget-for-accented-rendering-mode-and-liquid-glass)

## 迁移与正式分发

`build.sh` 构建 Universal 应用和扩展并开启 Hardened Runtime；没有指定 SIGN_IDENTITY 时仍是临时签名开发包。用户包只含应用、安装/刷新工具和说明；不携带凭据、缓存或个人配置。安装工具提供 `--check` 只读检查模式。

正式分发必须使用自己的 Developer ID Application 证书及已配置的 notarytool Keychain profile。不要在脚本中写入密码或私钥：

```sh
SIGN_IDENTITY='Developer ID Application: Your Name (TEAMID)' ./build.sh
NOTARY_PROFILE='your-existing-profile' ./scripts/notarize.sh '/absolute/build/path/Codex 周额度.app'
./scripts/package.sh '/absolute/build/path/Codex 周额度.app' '/absolute/output/CodexQuota-最新版安装包.zip'
```

先等待公证 Accepted、stapler 验证和 Gatekeeper 评估通过，再打最终安装包。本机没有可用签名证书，因此此流程尚未实际完成；不能声称当前 zip 已公证。还需在另一台无既有安装/许可记录的 Mac 上验收。

### 1.1.2 验证记录

主应用和扩展的 arm64 / x86_64 构建、签名完整性、系统库依赖检查、打包解压与安装前检查均通过。Hardened Runtime 构建已在本机运行，主应用服务和桌面小组件缓存的同步记录一致。公证脚本会拒绝临时签名应用，已验证该保护。没有第二台 Mac / Intel 实机，因此没有声称完成跨设备实测或 Apple 公证。

## 日常维护

源码与版本历史以私有仓库 [chz777123/codex-quota-widget](https://github.com/chz777123/codex-quota-widget) 为准；安装包从 [GitHub Releases](https://github.com/chz777123/codex-quota-widget/releases) 获取。

每次维护先确认工作区状态，再 `git pull --ff-only`；修改并完成相关验证后，提交并 `git push`。存在未提交修改或分叉时先安全处理，不使用强制覆盖。只保留一个本地工作目录，不长期保留源码备份和重复构建包。详细约定见 [AGENTS.md](AGENTS.md)。
