# Product positioning and messaging

## Primary audience

macOS and Windows users who use Codex Desktop with more than one authorized personal, work, or client account. They expect a familiar app installation and prefer visible controls over Terminal commands, scripts, environment variables, or config-file editing.

## Job to be done

Before opening Codex Desktop for the next piece of work, choose the correct account in the macOS menu bar or Windows native window and continue with minimal setup.

## Category

A focused Codex account switcher for macOS and Windows.

## Core promise

**English:** Switch Codex accounts on macOS and Windows. Add accounts once, then choose when you need them. No Terminal commands or config-file editing.

**简体中文：** 在 macOS 和 Windows 上轻松切换 Codex 账号。账号添加一次，之后随时选择。无需终端命令，无需修改配置文件。

## Supporting proof

- One version and one Release with both a signed, Apple-notarized macOS DMG and a portable, currently unsigned Windows EXE.
- macOS installs from a DMG; Windows runs from a self-contained EXE. Both use browser sign-in to add accounts.
- Keeps personal, work, and client accounts clearly labeled in the macOS menu bar or Windows window; the Windows tray reopens the window.
- Completes the Codex Desktop handoff after the user selects and confirms an account.
- Stores saved account data locally and runs without its own proxy or cloud account service.
- Free, MIT licensed and open source. The [v0.1.12 release](https://github.com/liuzhao1225/codex-account-switcher/releases/tag/v0.1.12) includes both platform packages and SHA-256 checksums.
- Shows weekly usage as decision context, with an optional 5-hour row.

## Claim boundaries

| Use | Avoid | Reason |
| --- | --- | --- |
| “Completes the switch after confirmation” | “Automatically rotates accounts” | The user always selects and confirms the target account. |
| “Focused on account switching” | “Only switches accounts” | The app also manages accounts, shows usage, and provides settings. |
| “Native macOS and Windows apps” or a release-specific download size | Unmeasured CPU or memory claims | Read the actual GitHub release asset size when updating copy; broad performance claims require benchmarks. |
| “No Terminal commands or config-file editing” | “Zero setup” | The user still installs the app and signs in to each account once. |
| “For accounts you own or are authorized to use” | Usage-limit bypass language | The product selects identities and does not increase limits or change permissions. |

## SEO topic map

### English

- Primary: `Codex account switcher`, `switch Codex accounts on Mac`, `switch Codex accounts on Windows`
- Intent: `switch Codex accounts without Terminal`, `Codex multiple accounts macOS`, `Codex multiple accounts Windows`
- Supporting: `Codex menu bar app`, `personal and work Codex accounts`, `Codex Desktop account switcher`

### 简体中文

- 核心：`Codex 账号切换器`、`Codex 多账号切换`
- 意图：`Mac 切换 Codex 账号`、`Windows 切换 Codex 账号`、`无需终端切换 Codex 账号`
- 辅助：`Codex 菜单栏应用`、`个人和工作 Codex 账号`、`Codex Desktop 账号切换`

The homepage owns the broad product term. The multiple-account guide owns the task query. The Codex account guide owns identity and authentication explanations. The project facts and creator pages establish the canonical product, repository, and maintainer.

## Community voice

- Write as the maintainer and describe the real workflow being improved.
- Ask where a concrete step creates friction.
- Welcome comparisons that include actual experience and tradeoffs.
- Keep credentials, account files, email addresses, and private screenshots out of public discussions.
- Avoid manufactured testimonials, duplicate self-promotion, and moderator outreach.

## Short descriptions

**GitHub:** Native Codex account switcher for macOS and Windows. Add accounts once, check usage, and confirm each switch. One release includes both downloads.

**中文短介绍：** 支持 macOS 与 Windows 的原生 Codex 多账号切换器。账号添加一次，查看用量并确认切换；同一个 Release 提供两端下载。

## Release and platform wording

- Use one stable version and a single `v<version>` Release containing both platform packages. Release notes describe changes only.
- Rebuild and test both platforms for each release; publish after both pass. The MVP does not reuse older packages or cross-run build caches.
- macOS uses a menu-bar popover. Windows uses a native window with a taskbar entry and tray icon; closing the window hides it, and the tray reopens it.
- Scope signing and Sparkle installation claims to macOS. Windows currently ships an unsigned portable EXE and opens the release page for manual updates.
- Label existing product screenshots as macOS. Product-wide descriptions, requirements, metadata, and download sections cover both platforms.
