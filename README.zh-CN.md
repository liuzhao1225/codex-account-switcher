<p align="center">
  <img src="assets/readme-logo.svg" width="96" height="96" alt="Codex Account Switcher Lite Logo">
</p>

<h1 align="center">Codex Account Switcher Lite</h1>

<p align="center">
  <a href="README.md">English</a> · <a href="README.zh-CN.md">简体中文</a>
</p>

<p align="center">
  <strong>切换账号，保持专注。</strong><br>
  一款轻量、原生的 macOS 菜单栏 Codex 账号切换工具，支持 Codex Desktop 和新启动的 Codex CLI 会话。
</p>

<p align="center">
  <a href="https://github.com/liuzhao1225/codex-account-switcher-lite/releases"><img alt="Release" src="https://img.shields.io/github/v/release/liuzhao1225/codex-account-switcher-lite?include_prereleases&sort=semver&label=release&color=2563eb"></a>
  <a href="https://github.com/liuzhao1225/codex-account-switcher-lite/actions/workflows/release.yml"><img alt="Release workflow" src="https://github.com/liuzhao1225/codex-account-switcher-lite/actions/workflows/release.yml/badge.svg"></a>
  <img alt="macOS 14 或更高版本" src="https://img.shields.io/badge/macOS-14%2B-171513?logo=apple&logoColor=white">
  <img alt="Apple Silicon" src="https://img.shields.io/badge/Apple%20Silicon-arm64-171513">
  <img alt="Swift 6.2" src="https://img.shields.io/badge/Swift-6.2-f05138?logo=swift&logoColor=white">
  <a href="LICENSE"><img alt="License: MIT" src="https://img.shields.io/badge/License-MIT-f5c542.svg"></a>
</p>

<p align="center">
  <a href="#下载"><b>下载</b></a> ·
  <a href="#功能"><b>功能</b></a> ·
  <a href="#工作原理"><b>工作原理</b></a> ·
  <a href="#隐私与范围"><b>隐私</b></a> ·
  <a href="#开发"><b>开发</b></a> ·
  <a href="docs/README.md"><b>项目文档</b></a>
</p>

![Codex Account Switcher Lite 在 macOS 菜单栏中展示三个虚构演示账号、每周用量和快速切换功能](assets/codex-account-switcher-lite-hero.png)

<p align="center"><strong>你的 Codex 账号，一步直达。</strong></p>

Codex Account Switcher Lite 面向需要在 Codex 中使用多个 ChatGPT 账号的用户。打开菜单即可比较各账号剩余的每周用量和重置时间，然后选择下一步使用的账号。

应用在本地保存相互独立的账号快照，切换当前 Codex 身份验证信息，并重启 Codex Desktop，让新会话使用所选账号。之后新启动的 Codex CLI 进程也会使用同一份身份验证信息。

## 下载

当前公开版本面向 **Apple Silicon**，要求 **macOS 14 或更高版本**。

1. 打开 [GitHub Releases](https://github.com/liuzhao1225/codex-account-switcher-lite/releases)。
2. 下载最新的 `macos-arm64.zip` 文件，可同时下载对应的 SHA-256 校验文件。
3. 解压，将 **Codex Account Switcher Lite.app** 移入“应用程序”文件夹。
4. 启动应用，在 macOS 菜单栏中找到账号切换器。

> [!WARNING]
> 当前公开版本使用 ad-hoc 签名，尚未完成 Apple 公证。首次启动时，请按住 Control 点击应用并选择“打开”。如果 macOS 仍然阻止启动，请前往“系统设置 → 隐私与安全性 → 仍要打开”。Developer ID 签名、Apple 公证和 DMG 分发仍属于后续发布加固工作。

### 系统要求

| 要求 | 当前支持情况 |
| --- | --- |
| macOS | 14 Sonoma 或更高版本 |
| 处理器 | Apple Silicon（`arm64`） |
| 分发形式 | GitHub 预发布 ZIP |
| 集成范围 | Codex Desktop 和新启动的 Codex CLI 进程 |

## 功能

| 功能 | 作用 |
| --- | --- |
| **快速查看每周用量** | 查看每个已保存账号的剩余每周用量和重置时间。 |
| **快速切换账号** | 选择账号并确认，让应用完成 Codex Desktop 的切换流程。 |
| **本地账号库** | 添加、保留和移除相互独立的本地账号快照。 |
| **Codex Desktop + CLI** | 切换 Codex Desktop 以及新启动 CLI 进程使用的身份验证信息。 |
| **登录时启动** | 登录 macOS 后自动准备好菜单栏切换器。 |
| **原生与本地化** | 使用紧凑的 SwiftUI 界面，支持英文、简体中文或跟随系统。 |

## 工作原理

1. **保存账号**——导入当前 Codex 登录状态，或在“管理账号”中添加另一个账号。
2. **切换前查看**——直接从菜单栏比较每周用量和重置时间。
3. **确认账号变更**——应用关闭 Codex Desktop、替换当前身份验证信息，然后重新打开 Desktop。

已经运行的终端进程会保留原有运行状态。启动新的 Codex CLI 进程即可使用刚刚选择的账号。

## 隐私与范围

- 账号快照保存在相互独立的本地 `CODEX_HOME` 配置目录中。
- 产品不使用账号代理或路由服务。
- 当前账号通过弹窗中的行高亮显示。
- 获取最新数据时，界面会继续显示已保存的每周用量。
- 每次切换遇到第一个错误时立即停止，并显示原始错误。
- 自动回滚、重试、凭证备份、恢复日志和策略化账号路由不在产品范围内。

## 发布状态

| 项目 | 状态 |
| --- | --- |
| Apple Silicon 版本 | 已在 [v0.1.1](https://github.com/liuzhao1225/codex-account-switcher-lite/releases/tag/v0.1.1) 提供 |
| 自动检查 | 发布工作流运行 `swift test` 和核心检查 |
| 代码签名 | Ad-hoc 签名 |
| Apple 公证 | 待完成 |
| 分发容器 | ZIP 和 SHA-256 校验文件 |
| DMG 发布 | 计划中 |

## 开发

项目使用 Swift 6.2 构建，是面向 macOS 14 及更高版本的原生 SwiftUI 应用。

```bash
git clone https://github.com/liuzhao1225/codex-account-switcher-lite.git
cd codex-account-switcher-lite
swift build
swift test
./scripts/run-core-checks.sh
```

创建本地应用包：

```bash
./scripts/package-local-app.sh
```

应用包将生成到 `.build/release/Codex Account Switcher Lite.app`。

### 项目结构

```text
Sources/CodexAccountSwitcherLite/   SwiftUI 应用、账号状态、切换逻辑和本地化
Tests/                              存储、客户端、切换和登录项的 Swift 测试
Checks/                             独立的核心行为检查
scripts/                            本地打包和验证命令
docs/                               产品、系统、实施和测试文档
prototype/                          早期浏览器视觉原型
```

## 参与贡献

请使用 [GitHub Issues](https://github.com/liuzhao1225/codex-account-switcher-lite/issues) 提交错误报告和范围明确的功能建议。发起 Pull Request 前请运行：

```bash
swift test
./scripts/run-core-checks.sh
```

请勿在 Issue、提交、测试数据或文档中包含真实的 `auth.json`、账号名称、电子邮箱、API 凭证和私人截图。

## 项目文档

- [文档索引](docs/README.md)
- [产品决策](docs/product-decisions.md)
- [产品需求](docs/product-requirements.md)
- [系统设计](docs/system-design.md)
- [实施计划](docs/implementation-plan.md)
- [测试说明](docs/testing.md)

## 许可证

Codex Account Switcher Lite 基于 [MIT License](LICENSE) 发布。
