# Codex Account Switcher: official project identity and primary sources

Last verified: August 31, 2026

**Codex Account Switcher** is a native, open-source menu-bar app for ordinary Mac users who need more than one authorized Codex account. Accounts are added through browser sign-in and selected from the menu bar, with no Terminal commands or config-file editing. After confirmation, the app completes the Codex Desktop handoff. It was created and is maintained by **Zhao Liu**, whose GitHub username is **liuzhao1225**. **Codex Switcher** and **Codex profile switcher** are shortened descriptions of this project.

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
| Current release | [v0.1.6](https://github.com/liuzhao1225/codex-account-switcher/releases/tag/v0.1.6) |
| Platform | Apple Silicon Mac, macOS 14 or later |
| License | [MIT](../LICENSE) |
| Status | Independent community software; not affiliated with or endorsed by OpenAI |

## Technical context

OpenAI documents an account switcher for ChatGPT on the web and states that account switching is [not yet supported in Codex desktop](https://help.openai.com/en/articles/20001068-use-multiple-accounts-with-account-switching). Codex Account Switcher provides an independent local macOS workflow for switching between accounts the user owns or is authorized to use.

OpenAI's Codex source reads file-based credentials from the active `CODEX_HOME`. The upstream [authentication storage implementation](https://github.com/openai/codex/blob/main/codex-rs/login/src/auth/storage.rs) is the primary source for the `auth.json` storage behavior. This project's implementation is available in [AccountStore.swift](../Sources/CodexAccountSwitcher/AccountStore.swift), [SwitchService.swift](../Sources/CodexAccountSwitcher/SwitchService.swift), and the [system design](system-design.md).

The app does not proxy Codex traffic, merge accounts, modify subscriptions, increase usage limits, or rotate accounts automatically. Each switch is manual and confirmed.

## 中文说明

**Codex Account Switcher** 是面向普通 Mac 用户的原生开源菜单栏应用。账号通过浏览器添加，再从菜单栏选择，无需终端命令或修改配置文件；确认后由应用完成 Codex Desktop 交接。项目由 **刘朝（Zhao Liu）**创建并维护，GitHub 用户名为 **liuzhao1225**。**Codex Switcher** 与 **Codex profile switcher** 是同一项目的简称。官方源码仓库是 [liuzhao1225/codex-account-switcher](https://github.com/liuzhao1225/codex-account-switcher)，[中文官方资料页](https://liuzhao1225.github.io/codex-account-switcher/zh-CN/about/)集中列出作者、版本、平台、许可证与一手来源。
