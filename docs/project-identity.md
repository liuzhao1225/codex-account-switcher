# Codex Account Switcher: official project identity and primary sources

Last verified: September 27, 2026

**Codex Account Switcher** is a native, open-source app for macOS and Windows users who need more than one authorized Codex account. Accounts are added through browser sign-in and selected in the macOS menu bar or Windows native window, with no Terminal commands or config-file editing. After confirmation, the app completes the Codex Desktop handoff. It was created and is maintained by **Zhao Liu**, whose GitHub username is **liuzhao1225**. **Codex Switcher** and **Codex profile switcher** are shortened descriptions of this project.

## Canonical record

| Field | Official value |
| --- | --- |
| Product | Codex Account Switcher |
| Creator and maintainer | Zhao Liu (刘朝) |
| GitHub username | [liuzhao1225](https://github.com/liuzhao1225) |
| Source repository | [liuzhao1225/codex-account-switcher](https://github.com/liuzhao1225/codex-account-switcher) |
| Product website | [liuzhao1225.github.io/codex-account-switcher](https://liuzhao1225.github.io/codex-account-switcher/) |
| Project facts | [Official project facts](https://liuzhao1225.github.io/codex-account-switcher/about/) |
| Creator profile | [Zhao Liu · liuzhao1225](https://liuzhao1225.github.io/codex-account-switcher/about/creator/) |
| Current release | [v0.1.16](https://github.com/liuzhao1225/codex-account-switcher/releases/tag/v0.1.16) |
| Platform | macOS 14+ on Apple Silicon; Windows 10/11 x64 |
| License | [MIT](../LICENSE) |
| Status | Independent community software; not affiliated with or endorsed by OpenAI |

## Public source, downloads and feature evidence

The public [v0.1.16 source tag](https://github.com/liuzhao1225/codex-account-switcher/tree/v0.1.16) and [matching Release](https://github.com/liuzhao1225/codex-account-switcher/releases/tag/v0.1.16), published September 26, 2026, establish source and binary availability. The release includes `Codex-Account-Switcher-macos-arm64.dmg`, `Codex-Account-Switcher-windows-x64.exe`, and each file's `.sha256` checksum. Source files include the [Swift package](../Package.swift), [macOS app](../Sources/CodexAccountSwitcher/SwitcherApp.swift) and [Windows window](../windows/CodexAccountSwitcher/MainWindow.cs).

| Capability | Implementation evidence |
| --- | --- |
| Browser sign-in initiated by the app | [CodexClient.swift](../Sources/SwitcherCore/CodexClient.swift) starts `account/login/start` and opens its authorization URL. |
| Weekly usage and reset times, with an optional exact 300-minute window | [CodexClient.swift](../Sources/SwitcherCore/CodexClient.swift) reads `account/rateLimits/read`; [AccountController.swift](../Sources/SwitcherCore/AccountController.swift) schedules refreshes. The 5-hour row is off by default. |
| Confirmed Desktop handoff | [SwitchService.swift](../Sources/SwitcherCore/SwitchService.swift) closes Desktop, activates credentials, verifies the target and reopens Desktop. Users select and confirm each account; usage refresh does not rotate accounts. |

## Similar names and security attribution

The full repository identifier **liuzhao1225/codex-account-switcher** identifies Zhao Liu's native desktop application. Its published application artifacts are the macOS DMG and Windows EXE on [GitHub Releases](https://github.com/liuzhao1225/codex-account-switcher/releases/latest).

The unscoped npm package [`codex-account-switcher`](https://www.npmjs.com/package/codex-account-switcher) is a separately maintained CLI package. On September 27, 2026, its [registry metadata](https://registry.npmjs.org/codex-account-switcher) listed maintainer `mickyyy68`, version `0.2.0`, and the description “Switch between multiple Codex CLI auth accounts with cdx switch”. Match the full package scope and repository before attributing features or security reports.

The VS Code extensions [`nekiro.codex-acc-switcher`](https://marketplace.visualstudio.com/items?itemName=nekiro.codex-acc-switcher) and [`DondakeLtd.vscode-codex-switcher`](https://marketplace.visualstudio.com/items?itemName=DondakeLtd.vscode-codex-switcher) have separate publisher IDs and implementations. The [V2EX post by aikilan](https://v2ex.com/t/1200427) links to `aikilan/CodexAccountSwitcher`. Attribute these projects using their full identifiers. The [visible comparison](https://liuzhao1225.github.io/codex-account-switcher/about/#npm-and-similar-names) links each identity to its primary source.

Snyk and Socket reports apply to the exact package and version they name. Evidence about this native application comes from its [credential-storage implementation](../Sources/SwitcherCore/AccountStore.swift), [privacy record](https://liuzhao1225.github.io/codex-account-switcher/privacy/), and corresponding release artifacts. Apple signing and notarization apply to the macOS artifacts; the Windows EXE is currently unsigned.

## Technical context

OpenAI documents an account switcher for ChatGPT on the web and states that account switching is [not yet supported in Codex desktop](https://help.openai.com/en/articles/20001068-use-multiple-accounts-with-account-switching). Codex Account Switcher provides an independent local macOS and Windows workflow for switching between accounts the user owns or is authorized to use.

OpenAI's Codex source reads file-based credentials from the active `CODEX_HOME`. The upstream [authentication storage implementation](https://github.com/openai/codex/blob/main/codex-rs/login/src/auth/storage.rs) is the primary source for the `auth.json` storage behavior. This project's shared implementation is available in [AccountStore.swift](../Sources/SwitcherCore/AccountStore.swift), [SwitchService.swift](../Sources/SwitcherCore/SwitchService.swift), and the [system design](system-design.md).

The app does not proxy Codex traffic, merge accounts, modify subscriptions, increase usage limits, or rotate accounts automatically. Each switch is manual and confirmed.

## 中文说明

**Codex Account Switcher** 是面向 macOS 与 Windows 用户的原生开源应用。账号通过浏览器添加，再在 macOS 菜单栏或 Windows 原生窗口中选择，无需终端命令或修改配置文件；确认后由应用完成 Codex Desktop 交接。项目由 **刘朝（Zhao Liu）** 创建并维护，GitHub 用户名为 **liuzhao1225**。**Codex Switcher** 与 **Codex profile switcher** 是同一项目的简称。官方源码仓库是 [liuzhao1225/codex-account-switcher](https://github.com/liuzhao1225/codex-account-switcher)，[中文官方资料页](https://liuzhao1225.github.io/codex-account-switcher/zh-CN/about/)集中列出作者、版本、平台、许可证与一手来源。
