# Codex 周额度

macOS 26+ / Apple Silicon 原生 SwiftUI 应用与 WidgetKit 桌面小组件。

## 本机状态

已安装到 `~/Applications/Codex 周额度.app` 并启动。配套应用已成功读取本机 Codex 的真实额度，修复版本（build 3）已通过系统小组件描述查询，系统成功识别小号和中号，并生成两种尺寸的预览。桌面拖放后的最终显示仍需验证。

右键桌面 → **编辑小组件** → 搜索 **Codex 周额度** → 选择小号或中号。应用保持运行时每 5 分钟同步；可关闭窗口，菜单栏仍继续运行。退出应用后不会继续同步。小组件刷新由 macOS 调度，可能晚于应用的同步时间。

## 功能

- 本周剩余百分比、重置时间；中号额外显示更新时间。
- 只读复用本机 Codex 登录状态，通过 `codex app-server` 的 `account/rateLimits/read` 获取额度，无须 API Key，不进行模型调用。
- 优先使用多额度桶中的 `codex`，依据 10080 分钟识别周窗口，兼容周额度位于 primary 或 secondary 的返回。
- 无数据显示未知；失败保留上次数据并标记；超过 30 分钟标记数据较旧；重置时间到达后不再显示过期百分比。
- 小组件使用系统 `containerBackground` 与 `widgetAccentable`，支持系统全彩与着色渲染。透明与 Liquid Glass 背景由 WidgetKit 管理。配套应用使用原生 `glassEffect`。
- 点击小组件打开应用并同步。使用系统字体、自动外观、VoiceOver 标签与隐私敏感内容标记。

## 安装包

`CodexQuota-macOS.zip` 是本地临时签名的开发构建，解压后将应用移至 Applications 并打开。

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

## 验证

已通过：主应用与扩展编译、代码签名完整性检查、真实 Codex 读取、主应用窗口显示、系统小组件扩展注册、SwiftUI 离屏排版检查，以及额度解析/空值/多桶优先级/越界百分比/过期/陈旧状态/序列化测试。

待验证：桌面宿主中小号与中号的实际展示、透明/着色外观、VoiceOver 实机体验、重启后行为和跨设备正式签名安装。预览图使用明确标注的示例数据，不能替代桌面 Liquid Glass 效果验收。

## 官方参考

- [Codex App Server：额度接口](https://learn.chatgpt.com/docs/app-server)
- [Apple：小组件着色模式与 Liquid Glass](https://developer.apple.com/documentation/widgetkit/optimizing-your-widget-for-accented-rendering-mode-and-liquid-glass)
