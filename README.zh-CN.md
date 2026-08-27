<p align="center">
  <picture>
    <source media="(prefers-color-scheme: dark)" srcset="assets/account-switcher-logo-white.png">
    <img src="assets/account-switcher-logo.png" width="96" height="96" alt="Codex Account Switcher Logo">
  </picture>
</p>

<h1 align="center">Codex Account Switcher</h1>

<p align="center">
  <strong>从 Mac 菜单栏切换 Codex 账号。</strong><br>
  账号添加一次，之后随时选择。无需终端命令，无需修改配置文件。
</p>

<p align="center">
  <a href="https://github.com/liuzhao1225/codex-account-switcher/releases"><img alt="Release" src="https://img.shields.io/github/v/release/liuzhao1225/codex-account-switcher?include_prereleases&sort=semver&label=release&color=2563eb"></a>
  <a href="https://github.com/liuzhao1225/codex-account-switcher/actions/workflows/release.yml"><img alt="Release workflow" src="https://github.com/liuzhao1225/codex-account-switcher/actions/workflows/release.yml/badge.svg"></a>
  <img alt="macOS 14 或更高版本" src="https://img.shields.io/badge/macOS-14%2B-171513?logo=apple&logoColor=white">
  <img alt="Apple Silicon" src="https://img.shields.io/badge/Apple%20Silicon-arm64-171513">
  <img alt="Swift 6.2" src="https://img.shields.io/badge/Swift-6.2-f05138?logo=swift&logoColor=white">
  <a href="LICENSE"><img alt="License: MIT" src="https://img.shields.io/badge/License-MIT-f5c542.svg"></a>
</p>

<p align="center">
  <a href="https://liuzhao1225.github.io/codex-account-switcher/zh-CN/"><b>网站</b></a> ·
  <a href="#下载"><b>下载</b></a> ·
  <a href="https://github.com/liuzhao1225/codex-account-switcher/discussions"><b>讨论区</b></a>
</p>

<p align="center">
  <a href="README.md">English</a> · 中文
</p>

![原生 macOS Codex Account Switcher 在菜单栏中展示三个虚构 Codex 账号、用量和账号切换功能](assets/codex-account-switcher-hero.zh-CN.png)

<p align="center"><strong>下载。添加账号。从菜单栏选择。</strong></p>

<p align="center">创建与维护：<a href="https://liuzhao1225.github.io/codex-account-switcher/zh-CN/about/creator/">刘朝 Zhao Liu（GitHub：liuzhao1225）</a> · <a href="https://x.com/liuzhao_666">X</a> · <a href="https://space.bilibili.com/1263732318">Bilibili 黑纹白斑马</a></p>

Codex Account Switcher 是一款免费、原生的 Mac 应用，适合使用多个获准 Codex 账号的普通用户。个人、工作或客户账号通过浏览器添加一次，之后从菜单栏选择即可。日常使用无需代码知识、终端命令、复制令牌或修改配置文件。

选择账号并确认后，应用会关闭 Codex Desktop、完成账号交接、校验所选身份，再重新打开 Desktop。已保存的账号数据留在这台 Mac，应用不依赖自己的代理、流量转发、云端账号服务或自动账号轮换。

## 官方项目身份

**Codex Account Switcher** 由 **刘朝（Zhao Liu）**创建并维护，GitHub 用户名为 **liuzhao1225**；**Codex Switcher** 是同一项目的简称。唯一官方源码仓库是 [liuzhao1225/codex-account-switcher](https://github.com/liuzhao1225/codex-account-switcher)。[官方项目资料页](https://liuzhao1225.github.io/codex-account-switcher/zh-CN/about/)、[作者资料页](https://liuzhao1225.github.io/codex-account-switcher/zh-CN/about/creator/)和[项目身份记录](docs/project-identity.md)共同记录产品、作者、别名、版本与一手来源。

OpenAI 官方账号切换功能当前适用于 ChatGPT 网页端，并且[尚未支持 Codex desktop](https://help.openai.com/en/articles/20001068-use-multiple-accounts-with-account-switching)。Codex Account Switcher 是面向这一桌面工作流的独立本地 macOS 工具。OpenAI Codex 上游源码在[认证存储实现](https://github.com/openai/codex/blob/main/codex-rs/login/src/auth/storage.rs)中记录了活动 `CODEX_HOME` 与文件型 `auth.json` 的行为。

## 适用人群

- **同时使用个人和工作账号的人：** 两种身份都保存在一台 Mac，打开 Codex Desktop 前看清当前账号。
- **自由职业者与顾问：** 清晰标记获准使用的客户账号，开始工作前选择正确身份。
- **偏好清晰可见操作的 Mac 用户：** 使用菜单栏选择与确认，避开脚本和后台静默轮换。

如果你正在搜索 **Codex 账号切换器**、**Codex 多账号切换**、**Codex profile switcher**，或者希望在 **Mac 上无需终端设置即可切换多个 Codex 账号**，这个项目提供了专注 Codex Desktop 的本地工作流。

## 下载

当前公开版本面向 **Apple Silicon**，要求 **macOS 14 或更高版本**。

1. [下载 Codex Account Switcher v0.1.5 Mac 版](https://github.com/liuzhao1225/codex-account-switcher/releases/download/v0.1.5/Codex-Account-Switcher-v0.1.5-macos-arm64.dmg)。
2. 打开 DMG，将 **Codex Account Switcher.app** 移入“应用程序”文件夹。
3. 启动应用，在 macOS 菜单栏中找到账号切换器。
4. 通过浏览器添加每个账号一次，之后选择需要的账号。

> [!NOTE]
> 当前 DMG 和应用均已使用 Developer ID Application 证书签名、完成 Apple 公证并附加离线票据。将应用复制到“应用程序”后，即可按 macOS 正常启动流程打开。

### 系统要求

| 要求 | 当前支持情况 |
| --- | --- |
| macOS | 14 Sonoma 或更高版本 |
| 处理器 | Apple Silicon（`arm64`） |
| 分发形式 | GitHub Releases DMG |
| 下载体积 | 约 2 MB |
| 主要用途 | 切换 Codex Desktop 账号 |

## 功能

| 功能 | 作用 |
| --- | --- |
| **无需代码的设置流程** | 通过普通浏览器登录添加账号，无需终端命令或配置文件。 |
| **菜单栏选择账号** | 把个人、工作和客户账号清晰标记在一个 Mac 菜单中。 |
| **完整 Desktop 交接** | 选择并确认后，由应用关闭、切换、校验并重新打开 Codex Desktop。 |
| **本地账号存储** | 账号数据留在这台 Mac，不依赖应用自建的代理或云端账号服务。 |
| **快速查看用量** | 默认查看每周用量，也可在设置中开启服务端提供的精确 300 分钟（5 小时）窗口与重置时间；该用量行默认关闭。 |
| **体积小的原生 Mac 应用** | 安装已完成 Apple 公证的 DMG，使用英文或简体中文 SwiftUI 界面。 |

## 工作原理

1. **下载 Mac 应用：** 打开已完成 Apple 公证的 DMG，把应用拖入“应用程序”。
2. **每个账号添加一次：** 完成熟悉的浏览器登录，并给每个账号设置清晰名称。
3. **选择后继续使用：** 从菜单栏选择账号并确认，由应用重新打开 Codex Desktop。

已经运行的终端进程会保留原有运行状态。启动新的 Codex CLI 进程即可使用刚刚选择的账号。

## 征集反馈

产品正在围绕普通 Mac 用户持续调整。欢迎参与公开讨论：[“Codex 账号切换器的哪个环节仍然显得太技术化？”](https://github.com/liuzhao1225/codex-account-switcher/discussions/2)，告诉我们问题出在下载应用、添加账号、识别当前账号，还是理解切换确认。

也欢迎分享其他账号切换器的真实使用体验。请描述实际工作流和产生阻力的步骤，不要公开凭证、账号文件、电子邮箱或私人截图。

## 隐私与范围

- 已保存的账号数据位于 Mac 上仅当前用户可访问的本地目录。
- 每个已保存 profile 都包含一份完整且可复用的 `auth.json` 凭证快照。应用将 profile 目录权限设为 `0700`、凭证文件权限设为 `0600`，并通过同目录临时文件与重命名实现凭证文件的原子替换。
- 本地文件权限构成当前安全边界。用户备份、文件系统快照、云备份工具、终端安全软件，以及其他有权访问用户文件的进程都可能复制这些凭证快照。
- 移除账号执行普通文件系统删除。应用不承诺从 SSD、APFS 快照或备份中安全擦除相关数据。
- 当前版本使用文件型凭证存储，profile 凭证未存入 macOS 钥匙串。
- 产品不使用自己的账号代理、流量转发或云端账号服务。
- 每个账号都由用户选择并确认；应用不会自动轮换账号。
- 本项目是独立开源软件，与 OpenAI 没有关联，也未获得 OpenAI 背书。
- 当前账号通过弹窗中的行高亮显示。
- 获取最新数据时，界面会继续显示已保存的 5 小时和每周用量；5 小时用量仅在开启且服务端提供精确 300 分钟窗口时显示。
- 每次切换遇到第一个错误时立即停止，并显示原始错误。
- 如果目标凭证激活后的身份验证或 registry 提交失败，应用会用刚保存的原 profile 凭证恢复活动凭证，同时保留原始错误；恢复本身失败时会一并显示恢复错误。
- 通用回滚状态机、重试、凭证备份文件、恢复日志、启动恢复和策略化账号路由仍不在产品范围内。

## 发布状态

| 项目 | 状态 |
| --- | --- |
| Apple Silicon 版本 | 已在 [v0.1.5](https://github.com/liuzhao1225/codex-account-switcher/releases/tag/v0.1.5) 提供 |
| 自动检查 | PR、`main` 和发布工作流运行 `swift test` 与核心检查 |
| 代码签名 | Developer ID Application |
| Apple 公证 | 应用和 DMG 均已公证并附加票据 |
| 分发容器 | DMG 和 SHA-256 校验文件 |
| DMG 发布 | 已在 v0.1.5 提供 |

## 开发

项目使用 Swift 6.2 构建，是面向 macOS 14 及更高版本的原生 SwiftUI 应用。

```bash
git clone https://github.com/liuzhao1225/codex-account-switcher.git
cd codex-account-switcher
swift build
swift test
./scripts/run-core-checks.sh
```

创建本地应用包：

```bash
./scripts/package-local-app.sh
```

应用包将生成到 `.build/release/Codex Account Switcher.app`。

### 项目结构

```text
Sources/CodexAccountSwitcher/   SwiftUI 应用、账号状态、切换逻辑和本地化
Tests/                              存储、客户端、切换和登录项的 Swift 测试
Checks/                             独立的核心行为检查
scripts/                            本地打包和验证命令
docs/                               产品、系统、实施和测试文档
prototype/                          早期浏览器视觉原型
```

## 参与贡献

请使用 [GitHub Discussions](https://github.com/liuzhao1225/codex-account-switcher/discussions) 讨论工作流、产品想法和工具对比，使用 [GitHub Issues](https://github.com/liuzhao1225/codex-account-switcher/issues) 提交错误报告和范围明确的功能建议。发起 Pull Request 前请运行：

```bash
swift test
./scripts/run-core-checks.sh
```

请勿在 Issue、提交、测试数据或文档中包含真实的 `auth.json`、账号名称、电子邮箱、API 凭证和私人截图。

## 项目文档

- [文档索引](docs/README.md)
- [官方项目身份与一手来源](docs/project-identity.md)
- [产品定位与宣传口径](docs/positioning-and-messaging.md)
- [产品决策](docs/product-decisions.md)
- [产品需求](docs/product-requirements.md)
- [系统设计](docs/system-design.md)
- [实施计划](docs/implementation-plan.md)
- [测试说明](docs/testing.md)

## 常见问题

### 需要使用终端或懂代码吗？

不需要。安装应用，通过普通浏览器登录添加每个账号，之后从菜单栏选择即可。整个流程没有终端命令，也不用编辑配置文件。

### 如何切换账号？

每个获准使用的账号添加一次，从菜单栏选择并确认。应用会关闭 Codex Desktop、完成交接、校验所选账号，再重新打开 Desktop。

### 应用会自动切换账号吗？

每个账号都由你选择并确认，随后应用会自动完成 Codex Desktop 交接。应用不会在后台轮换账号，也不会根据用量阈值切换。

### 账号数据会离开我的 Mac 吗？

已保存的账号数据位于 `~/Library/Application Support/Codex Account Switcher/` 下仅当前用户可访问的本地文件夹。应用没有账号代理、流量转发或云端配置服务。

### 需要什么 Mac？

当前版本支持运行 macOS 14 Sonoma 或更高版本的 Apple Silicon Mac。下载文件是已签名并完成 Apple 公证的 DMG。

### Codex Account Switcher 是 OpenAI 官方产品吗？

不是。它是一个采用 MIT 许可证的独立 macOS 开源项目。

## 许可证

Codex Account Switcher 基于 [MIT License](LICENSE) 发布。
