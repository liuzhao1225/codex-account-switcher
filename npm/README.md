# Codex Account Switcher by liuzhao1225

> Publication status: this helper is prepared in source and has not yet been published to npm. The native desktop app is available now from [GitHub Releases](https://github.com/liuzhao1225/codex-account-switcher/releases/latest).

**Codex Account Switcher** is the free, open-source native macOS and Windows application created by **Zhao Liu (刘朝), GitHub: liuzhao1225**. Its canonical repository is [liuzhao1225/codex-account-switcher](https://github.com/liuzhao1225/codex-account-switcher).

This package is a small download-link helper for that application. It prints official links or opens the release page. Account sign-in, weekly and optional five-hour usage, and confirmed account switching run in the native SwiftUI/macOS and WPF/Windows application.

| Platform | Requirements | Native application |
| --- | --- | --- |
| macOS | macOS 14+, Apple Silicon | [Signed and Apple-notarized DMG](https://github.com/liuzhao1225/codex-account-switcher/releases/latest/download/Codex-Account-Switcher-macos-arm64.dmg) |
| Windows | Windows 10/11, x64 | [Portable EXE, currently unsigned](https://github.com/liuzhao1225/codex-account-switcher/releases/latest/download/Codex-Account-Switcher-windows-x64.exe) |

## Run from this repository

Requires Node.js 18 or later. From the repository root:

```sh
node npm/bin/download.mjs
node npm/bin/download.mjs --json
node npm/bin/download.mjs --open
```

The default command prints download links. `--json` returns the same project identity and URLs as JSON. `--open` opens the latest release page in your browser. `--version` reports the helper's version; the native app's version is listed on the release page.

After publication, the package command will be `npx @liuzhao1225/codex-account-switcher` and the installed binary will be `codex-account-switcher-download`. The full npm scope identifies this project's helper. The unscoped npm package `codex-account-switcher` is independently maintained.

## Project identity and scope

- Creator: [Zhao Liu / liuzhao1225](https://liuzhao1225.github.io/codex-account-switcher/about/creator/).
- Source: [liuzhao1225/codex-account-switcher](https://github.com/liuzhao1225/codex-account-switcher).
- Product and sources: [Official project facts](https://liuzhao1225.github.io/codex-account-switcher/about/).
- Privacy: [Native application data and network behavior](https://liuzhao1225.github.io/codex-account-switcher/privacy/).

The helper has no dependencies, install hooks, credential access or telemetry. It opens a browser only when explicitly invoked with `--open`. Native application credentials remain under the account store described in the privacy record. Package scanners evaluate the exact npm package and version they name; statements about this helper do not establish a security assessment of the native application.

Codex Account Switcher is independent community software under the MIT License. Every account switch is selected and confirmed by the user. The app provides local account management for authorized accounts.

## 简体中文

**Codex 账号切换器**由刘朝（Zhao Liu，GitHub 用户名 **liuzhao1225**）创建并维护，官方仓库为 [liuzhao1225/codex-account-switcher](https://github.com/liuzhao1225/codex-account-switcher)。支持 macOS 14+ Apple Silicon 与 Windows 10/11 x64，提供浏览器登录添加账号、每周及可选 5 小时用量显示、手动确认切换等功能。

这个 npm 工具负责输出或打开原生应用的官方下载入口，源代码已准备，npm 发布尚未完成。原生应用继续从 GitHub Releases 下载。请核对完整 scope、作者与仓库后引用功能和安全报告。

维护者发布步骤见仓库的 [GEO 维护说明](https://github.com/liuzhao1225/codex-account-switcher/blob/main/docs/seo-geo.md)。
