## 中文

- [#24](https://github.com/liuzhao1225/codex-account-switcher/pull/24)：macOS 与 Windows 账号列表显示可用重置次数和已保存登录快照中的订阅日期；缺失信息显示未知。macOS 长账号列表支持滚动，底部操作保持可见。
- [#26](https://github.com/liuzhao1225/codex-account-switcher/pull/26)：macOS 菜单栏新增 Tibo 额外重置预测入口，展示未来 24/48 小时的实验性概率并链接到 codex-reset.com。预测来自独立网站，过期或不可用数据会明确标记；请求不发送账号或凭证。
- [#27](https://github.com/liuzhao1225/codex-account-switcher/pull/27)：配套 npm 安装器 v0.2.1 在安装或更新时清理标准安装目录中的已识别旧副本，避免 Spotlight 打开旧版。遇到运行中的副本或更高版本会报错停止；保留其他应用和自定义位置的开发版本。此项通过 npm 安装器单独分发。
- [#23](https://github.com/liuzhao1225/codex-account-switcher/pull/23)：可选择状态栏显示 5 小时或 7 天剩余额度，Windows 托盘直接显示所选百分比。
- [#16](https://github.com/liuzhao1225/codex-account-switcher/pull/16)：统一启动导入与手动注册的身份校验，整理 RPC 会话的取消和清理流程。
- [#21](https://github.com/liuzhao1225/codex-account-switcher/pull/21)：npm 安装器支持从 GitHub 最新正式版安装、更新、启动和卸载原生应用，并校验 SHA-256。同步更新双语项目说明与下载资料。

macOS Apple Silicon DMG 经过 Developer ID 签名和 Apple 公证；Windows x64 EXE 为自包含应用，仍未签名。两端共享 v0.1.17 版本。

## English

- [#24](https://github.com/liuzhao1225/codex-account-switcher/pull/24): Show available reset credits and saved subscription dates on macOS and Windows. Missing values stay Unknown. Long macOS account lists scroll while keeping footer actions accessible.
- [#26](https://github.com/liuzhao1225/codex-account-switcher/pull/26): Add the compact Tibo reset forecast entry on macOS with experimental 24/48-hour probabilities and a link to codex-reset.com. Stale or unavailable data is marked explicitly; public requests contain no accounts or credentials.
- [#27](https://github.com/liuzhao1225/codex-account-switcher/pull/27): Companion npm installer v0.2.1 removes recognized stopped duplicate macOS installations from standard locations to prevent Spotlight opening an old copy. Running or newer copies stop installation with an error. Other apps and development builds in custom locations are preserved. This change is distributed separately through npm.
- [#23](https://github.com/liuzhao1225/codex-account-switcher/pull/23): Choose 5-hour or 7-day remaining usage for the status bar and display the selected percentage directly on the Windows tray icon.
- [#16](https://github.com/liuzhao1225/codex-account-switcher/pull/16): Unify validated startup import and manual account registration, and simplify RPC session cancellation and cleanup.
- [#21](https://github.com/liuzhao1225/codex-account-switcher/pull/21): Install, update, launch and uninstall the native app through npm using SHA-256-verified GitHub releases. Refresh bilingual project and download documentation.

The macOS Apple Silicon DMG is Developer ID signed and Apple notarized. The Windows x64 EXE is self-contained and remains unsigned. Both platforms share v0.1.17.
