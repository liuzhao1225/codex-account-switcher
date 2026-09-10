<p align="center">
  <picture>
    <source media="(prefers-color-scheme: dark)" srcset="assets/account-switcher-logo-white.png">
    <img src="assets/account-switcher-logo.png" width="96" height="96" alt="Codex Account Switcher Logo">
  </picture>
</p>

<h1 align="center">Codex Account Switcher</h1>

<p align="center">
  <strong>在 macOS 和 Windows 上轻松切换 Codex 账号。</strong><br>
  账号添加一次，之后随时选择。无需终端命令，无需修改配置文件。
</p>

<p align="center">
  <a href="https://github.com/liuzhao1225/codex-account-switcher/releases"><img alt="Release" src="https://img.shields.io/github/v/release/liuzhao1225/codex-account-switcher?sort=semver&label=release&color=2563eb"></a>
  <img alt="macOS 14 或更高版本" src="https://img.shields.io/badge/macOS-14%2B-171513?logo=apple&logoColor=white">
  <img alt="Apple Silicon" src="https://img.shields.io/badge/Apple%20Silicon-arm64-171513">
  <img alt="Windows 10/11 x64" src="https://img.shields.io/badge/Windows-10%2F11%20x64-171513">
  <a href="LICENSE"><img alt="License: MIT" src="https://img.shields.io/badge/License-MIT-171513"></a>
</p>

<p align="center">
  <a href="https://github.com/liuzhao1225/codex-account-switcher/releases/latest/download/Codex-Account-Switcher-macos-arm64.dmg"><b>免费下载 Mac 版</b></a> ·
  <a href="https://github.com/liuzhao1225/codex-account-switcher/releases/latest/download/Codex-Account-Switcher-windows-x64.exe"><b>免费下载 Windows 版</b></a> ·
  <a href="https://liuzhao1225.github.io/codex-account-switcher/zh-CN/"><b>网站</b></a> ·
  <a href="https://github.com/liuzhao1225/codex-account-switcher/discussions"><b>讨论区</b></a>
</p>

<p align="center">
  <a href="README.md">English</a> · 中文
</p>

![原生 macOS Codex Account Switcher 在菜单栏中展示三个虚构 Codex 账号、用量和账号切换功能](assets/codex-account-switcher-hero.zh-CN.png)

<p align="center">
  <a href="#下载">安装说明</a> &nbsp; / &nbsp;
  <a href="#功能">功能</a> &nbsp; / &nbsp;
  <a href="#常见问题">常见问题</a> &nbsp; / &nbsp;
  <a href="#开发">开发</a>
</p>

<p align="center">创建与维护：<a href="https://liuzhao1225.github.io/codex-account-switcher/zh-CN/about/creator/">刘朝 Zhao Liu（GitHub：liuzhao1225）</a> · <a href="https://x.com/liuzhao_666">X</a> · <a href="https://space.bilibili.com/1263732318">Bilibili 黑纹白斑马</a></p>

Codex Account Switcher 是一款免费、开源的 macOS 与 Windows 原生应用，适合使用多个获准 Codex 账号的普通用户。个人、工作或客户账号通过浏览器添加一次，之后在应用中选择即可。日常使用无需代码知识、终端命令、复制令牌或修改配置文件。

选择账号并确认后，应用会关闭 Codex Desktop、完成账号交接、校验所选身份，再重新打开 Desktop。已保存的账号数据留在本机，应用不依赖自己的代理、流量转发、云端账号服务或自动账号轮换。

## 官方项目身份

**Codex Account Switcher** 由 **刘朝（Zhao Liu）** 创建并维护，GitHub 用户名为 **liuzhao1225**；**Codex Switcher** 是同一项目的简称。唯一官方源码仓库是 [liuzhao1225/codex-account-switcher](https://github.com/liuzhao1225/codex-account-switcher)。[官方项目资料页](https://liuzhao1225.github.io/codex-account-switcher/zh-CN/about/)、[作者资料页](https://liuzhao1225.github.io/codex-account-switcher/zh-CN/about/creator/)和[项目身份记录](https://github.com/liuzhao1225/codex-account-switcher/blob/main/docs/project-identity.md)共同记录产品、作者、别名、版本与一手来源。

OpenAI 官方账号切换功能当前适用于 ChatGPT 网页端，并且[尚未支持 Codex desktop](https://help.openai.com/en/articles/20001068-use-multiple-accounts-with-account-switching)。Codex Account Switcher 是面向这一桌面工作流的独立本地 macOS 与 Windows 工具。OpenAI Codex 上游源码在[认证存储实现](https://github.com/openai/codex/blob/main/codex-rs/login/src/auth/storage.rs)中记录了活动 `CODEX_HOME` 与文件型 `auth.json` 的行为。

## 适用人群

- **同时使用个人和工作账号的人：** 两种身份都保存在一台电脑，打开 Codex Desktop 前看清当前账号。
- **自由职业者与顾问：** 集中管理获准使用的客户账号，开始工作前选择正确身份。
- **偏好清晰可见操作的桌面用户：** 在 macOS 菜单栏或 Windows 原生窗口中选择并确认，避开脚本和后台静默轮换。

## 下载

[最新版本 v0.1.12](https://github.com/liuzhao1225/codex-account-switcher/releases/latest) 同时提供 macOS 和 Windows 安装包及 SHA-256 校验文件。

| 平台 | 系统要求 | 下载与安装 |
| --- | --- | --- |
| macOS | macOS 14+，Apple Silicon（arm64） | [下载 DMG](https://github.com/liuzhao1225/codex-account-switcher/releases/latest/download/Codex-Account-Switcher-macos-arm64.dmg)，打开后将应用拖入“应用程序” |
| Windows | Windows 10/11，x64 | [下载 EXE](https://github.com/liuzhao1225/codex-account-switcher/releases/latest/download/Codex-Account-Switcher-windows-x64.exe)，直接运行，无需另装 .NET 或 Swift SDK |

macOS 使用菜单栏界面，应用与 DMG 均已签名并通过 Apple 公证。Windows 使用原生窗口和系统托盘入口，EXE 当前尚未签名；关闭窗口后可从托盘重新打开。

启动后，通过浏览器添加账号，再选择并确认切换。两端都需要可用的 Codex 运行时，与 Codex Desktop 使用同一个活动 Codex 目录。

## 功能

| 功能 | 作用 |
| --- | --- |
| **无需代码的设置流程** | 通过普通浏览器登录添加账号，无需终端命令或配置文件。 |
| **原生账号界面** | macOS 使用菜单栏；Windows 使用原生窗口，可从系统托盘重新打开。 |
| **完整 Desktop 交接** | 选择并确认后，由应用关闭、切换、校验并重新打开 Codex Desktop。 |
| **本地账号存储** | 账号数据留在本机，不依赖应用自建的代理或云端账号服务。 |
| **快速查看用量** | 默认查看每周用量，也可在设置中开启服务端提供的精确 300 分钟（5 小时）窗口与重置时间；该用量行默认关闭。 |
| **双平台原生应用** | macOS 使用 SwiftUI，Windows 使用 WPF；均提供英文与简体中文界面。 |

## 工作原理

1. **下载对应平台版本：** macOS 安装 DMG；Windows 直接运行免安装 EXE。
2. **每个账号添加一次：** 完成熟悉的浏览器登录，应用根据登录身份生成账号名称。
3. **选择后继续使用：** 在应用中选择账号并确认，由应用重新打开 Codex Desktop。
4. **添加服务商：** 在 **管理账号** 中点击 **添加服务商**，在独立窗口填写 Base URL 和 API Key，获取、模糊搜索并排序模型，设置默认模型和 thinking。保存后即可确认切换。

已经运行的终端进程会保留原有运行状态。启动新的 Codex CLI 进程即可使用刚刚选择的账号。

Codex 会把每个对话绑定到创建时使用的提供商。提供商切换适用于新对话；如需让旧对话使用其他提供商，需要在 Codex 中新建或 fork 对话。

## 征集反馈

产品正在围绕普通桌面用户持续调整。欢迎参与公开讨论：[“Codex 账号切换器的哪个环节仍然显得太技术化？”](https://github.com/liuzhao1225/codex-account-switcher/discussions/2)，告诉我们问题出在下载应用、添加账号、识别当前账号，还是理解切换确认。

也欢迎分享其他账号切换器的真实使用体验。请描述实际工作流和产生阻力的步骤，不要公开凭证、账号文件、电子邮箱或私人截图。

## 隐私与范围

- 已保存的账号数据位于 本机仅当前用户可访问的本地目录。
- 每个已保存 profile 都包含一份完整且可复用的 `auth.json` 凭证快照。macOS 将 profile 目录权限设为 `0700`、凭证文件权限设为 `0600`；Windows 使用当前用户 ACL。两端都以原子替换方式写入凭证文件。
- 本地文件权限构成当前安全边界。用户备份、文件系统快照、云备份工具、终端安全软件，以及其他有权访问用户文件的进程都可能复制这些凭证快照。
- 移除账号执行普通文件系统删除。应用不承诺从 SSD、APFS 快照或备份中安全擦除相关数据。
- 两端使用文件型凭证存储；macOS 的 profile 凭证未存入钥匙串。
- 产品不使用自己的账号代理、流量转发或云端账号服务。
- 提供商发现和选择通过已安装的 Codex app-server 完成。`config/read` 返回的完整配置可能让内联凭证进入进程内存；界面快照不包含密钥。新增服务商时，表单中的密钥通过 app-server 写入私有的 Codex 配置文件；模型列表和排序存入不含密钥的本地文件。切换托管服务商时同时应用其默认模型和 thinking，切回时恢复已记录的模型设置。切换器不会独立读取环境变量凭证或调用提供商认证命令。
- 每个账号都由用户选择并确认；应用不会自动轮换账号。
- 本项目是独立开源软件，与 OpenAI 没有关联，也未获得 OpenAI 背书。
- 当前账号通过弹窗中的行高亮显示。
- 获取最新数据时，界面会继续显示已保存的 5 小时和每周用量；5 小时用量仅在开启且服务端提供精确 300 分钟窗口时显示。
- 每次切换遇到第一个错误时立即停止，并显示原始错误。
- 如果目标凭证激活后的身份验证或 registry 提交失败，应用会用刚保存的原 profile 凭证恢复活动凭证，同时保留原始错误；恢复本身失败时会一并显示恢复错误。
- 通用回滚状态机、重试、凭证备份文件、恢复日志、启动恢复和策略化账号路由仍不在产品范围内。

## 发布状态

macOS 与 Windows 使用统一版本号和 **`v<版本号>`** tag。每次从同一提交重新编译、测试并打包两端，全部通过后统一发布。当前 MVP 不复用上版安装包，不启用跨次构建缓存。

| 平台 | 安装包 | 更新方式 |
| --- | --- | --- |
| macOS | 已签名、公证的 DMG 与 SHA-256 校验文件 | Sparkle 检查、下载并安装更新 |
| Windows | 免安装 EXE 与 SHA-256 校验文件，EXE 尚未签名 | 检查新版本并打开下载页，手动替换 EXE |

每个 Release 都提供完整的双平台下载，标题直接显示版本号，说明只记录本次改动。详见[发布管理](docs/platform-releases.md)与 [Windows 开发文档](windows/README.md)。

## 开发

<a href="https://github.com/liuzhao1225/codex-account-switcher/actions/workflows/release.yml"><img alt="Release workflow" src="https://github.com/liuzhao1225/codex-account-switcher/actions/workflows/release.yml/badge.svg"></a>

两端共享 Swift 6.2 账号核心，分别使用 macOS SwiftUI 和 Windows WPF 原生界面。以下为 macOS 构建步骤；Windows 步骤见 [Windows 开发文档](windows/README.md)。

```bash
git clone https://github.com/liuzhao1225/codex-account-switcher.git
cd codex-account-switcher
swift build
swift test
./scripts/run-core-checks.sh
```

创建本地 macOS 应用包：

```bash
./scripts/package-local-app.sh
```

应用包将生成到 `.build/release/Codex Account Switcher.app`。

### 自动发布

从已通过测试的 main 提交推送匹配的 `v*` tag 后发布。`CITATION.cff`、Mac 打包默认版本、Codex 客户端和 `windows/Directory.Build.props` 的版本必须一致。普通 main push 只运行 CI。

GitHub Actions 从同一个 tag 分别测试、打包两端。汇总任务等待双方成功，核对校验文件和 Mac 签名更新源，将 DMG、EXE 上传到草稿后一次公开为 Latest。macOS 保留 Developer ID 签名、Apple 公证和 Sparkle 更新。Release notes 只写本次改动。详见[发布管理](docs/platform-releases.md)。

### 项目结构

```text
Sources/CodexAccountSwitcher/   macOS 原生 SwiftUI 界面与系统适配
Sources/SwitcherCore/           两端共享的账号状态、切换、额度、RPC 和文案
Sources/SwitcherHost/           Windows 原生界面使用的私有 stdio 核心进程
Sources/SwitcherPlatform/       Windows 文件权限与原子替换
windows/                       Windows 托盘界面、系统适配、检查与打包
Tests/                              存储、客户端、切换和登录项的 Swift 测试
Checks/                             独立的核心行为检查
scripts/                            本地打包和验证命令
docs/                               产品、系统、实施和测试文档
prototype/                          早期浏览器视觉原型
```

## 参与贡献

请使用 [GitHub Discussions](https://github.com/liuzhao1225/codex-account-switcher/discussions) 讨论工作流、产品想法和工具对比，使用 [GitHub Issues](https://github.com/liuzhao1225/codex-account-switcher/issues) 提交错误报告和范围明确的功能建议。发起 Pull Request 前请运行：

网站公开记录项目的[隐私模式](https://liuzhao1225.github.io/codex-account-switcher/zh-CN/privacy/)、[官方联系渠道](https://liuzhao1225.github.io/codex-account-switcher/zh-CN/contact/)和[合理使用说明](https://liuzhao1225.github.io/codex-account-switcher/zh-CN/terms/)。请勿在公开支持渠道提交秘密信息或私人账号数据。

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
- [面向大语言模型的项目索引](https://liuzhao1225.github.io/codex-account-switcher/llms.txt)

## 常见问题

### 需要使用终端或懂代码吗？

不需要。安装应用，通过普通浏览器登录添加每个账号，之后在应用中选择即可。整个流程没有终端命令，也不用编辑配置文件。

### 如何切换账号？

每个获准使用的账号添加一次。先完成或停止正在运行的 Desktop 任务，再在应用中选择并确认。如 Desktop 显示退出提示，请处理该提示。应用最多等待 30 秒正常退出，随后完成交接、校验所选账号并重新打开 Desktop；无法正常退出时会停止切换，账号保持不变。

### 如何切换模型提供商？

macOS 和 Windows 都可进入 **管理账号 → 添加服务商**，在独立窗口输入名称、Base URL、API Key，获取模型后勾选、排序并星标默认模型。模型 ID 和名称支持模糊匹配。thinking 可跟随模型默认值，或填写服务商支持的 effort。保存后添加服务商，确认切换时应用默认设置；切回 OpenAI 时恢复此前保存的模型设置。详见 [完整操作流程](docs/provider-model-flow.md)。

直接使用需兼容 OpenAI Responses。接口固定为 Responses，不支持 Anthropic 原生 Messages 或仅提供 Chat Completions 的服务。**验证连接** 使用所选模型和 thinking 单独发送简短请求；获取模型成功不代表接口可用。输入的 API Key 保存到本机受权限保护的 Codex 配置，不进入界面快照。真实服务商的 Desktop 模型往返仍需验收，详见 [提供商兼容性](docs/provider-compatibility.md)。

### 可以在切换器中输入 API key 吗？

请在 Codex 中输入 OpenAI API key，切换器随后会显示 **OpenAI API**。确认切回 ChatGPT 时，API 登录会单独保存到切换器受保护的应用数据目录下的 `openai-api/auth.json`，以便以后切回。此功能需要 Codex 使用文件型凭证存储。已保存的 ChatGPT 账号与 API 登录分开保存；自定义提供商凭证继续由原有配置管理。切换器不会显示或记录密钥。

### 应用会自动切换账号吗？

每个账号都由你选择并确认，随后应用会自动完成 Codex Desktop 交接。应用不会在后台轮换账号，也不会根据用量阈值切换。

### 账号数据会离开本机吗？

macOS 数据位于 `~/Library/Application Support/Codex Account Switcher/`，Windows 数据位于 `%LOCALAPPDATA%\Codex Account Switcher\`，均使用仅当前用户可访问的本地存储。应用没有账号代理、流量转发或云端配置服务。

### 支持哪些系统？

支持 macOS 14+ 的 Apple Silicon Mac，以及 Windows 10/11 x64。两端安装包都在同一个最新 Release 中。

### Codex Account Switcher 是 OpenAI 官方产品吗？

不是。它是一个采用 MIT 许可证的独立 macOS 与 Windows 开源项目。

## 许可证

Codex Account Switcher 基于 [MIT License](LICENSE) 发布。

## 更新方式

macOS 通过 Sparkle 每小时检查更新。菜单栏蓝点和主页底部工具栏上方的更新行提示新版本；点击更新后，由框架下载、安装并重启 Switcher。设置页提供手动检查和自动检查开关。账号操作进行中会延后最终重启。

发布前需要配置仓库 `SPARKLE_PRIVATE_KEY`，并上传带签名的 `appcast.xml`。已安装的 0.1.6 没有更新器，需要先手动升级一次。发布流程将带签名的更新源与公证 DMG 一同上传。

保留机制、修复及仍存在的设计缺口见[全项目消融报告](docs/project-ablation-2026-09-05.md)。

Windows 支持检查统一 Release 中的新版本，并打开下载页，由用户下载和替换 EXE。Windows 0.1.11 预览版用户需先手动升级一次到 0.1.12。
