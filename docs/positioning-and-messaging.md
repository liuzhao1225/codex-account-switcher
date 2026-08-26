# Product positioning and messaging

## Primary audience

Ordinary Mac users who use Codex Desktop with more than one authorized personal, work, or client account. They expect a familiar app installation and prefer visible controls over Terminal commands, scripts, environment variables, or config-file editing.

## Job to be done

Before opening Codex Desktop for the next piece of work, choose the correct account from a visible Mac menu and continue with minimal setup.

## Category

A focused Codex account switcher for the Mac menu bar.

## Core promise

**English:** Switch Codex accounts from your Mac menu bar. Add accounts once, then choose when you need them. No Terminal commands or config-file editing.

**简体中文：** 从 Mac 菜单栏切换 Codex 账号。账号添加一次，之后随时选择。无需终端命令，无需修改配置文件。

## Supporting proof

- Distributed as a signed and Apple-notarized DMG.
- Installs like a normal Mac app and uses browser sign-in to add accounts.
- Keeps personal, work, and client accounts clearly labeled in the menu bar.
- Completes the Codex Desktop handoff after the user selects and confirms an account.
- Stores saved account data locally and runs without its own proxy or cloud account service.
- Free, MIT licensed, open source, and about 2 MB for the current Apple Silicon release.
- Shows weekly usage as optional decision context.

## Claim boundaries

| Use | Avoid | Reason |
| --- | --- | --- |
| “Completes the switch after confirmation” | “Automatically rotates accounts” | The user always selects and confirms the target account. |
| “Focused on account switching” | “Only switches accounts” | The app also manages accounts, shows usage, and provides settings. |
| “Small native Mac app” or “about 2 MB download” | Unmeasured CPU or memory claims | Download size and native implementation are verified; broad performance claims require benchmarks. |
| “No Terminal commands or config-file editing” | “Zero setup” | The user still installs the app and signs in to each account once. |
| “For accounts you own or are authorized to use” | Usage-limit bypass language | The product selects identities and does not increase limits or change permissions. |

## SEO topic map

### English

- Primary: `Codex account switcher`, `switch Codex accounts on Mac`
- Intent: `switch Codex accounts without Terminal`, `Codex multiple accounts macOS`
- Supporting: `Codex menu bar app`, `personal and work Codex accounts`, `Codex Desktop account switcher`

### 简体中文

- 核心：`Codex 账号切换器`、`Codex 多账号切换`
- 意图：`Mac 切换 Codex 账号`、`无需终端切换 Codex 账号`
- 辅助：`Codex 菜单栏应用`、`个人和工作 Codex 账号`、`Codex Desktop 账号切换`

The homepage owns the broad product term. The multiple-account guide owns the task query. The Codex account guide owns identity and authentication explanations. The project facts and creator pages establish the canonical product, repository, and maintainer.

## Community voice

- Write as the maintainer and describe the real workflow being improved.
- Ask where a concrete step creates friction.
- Welcome comparisons that include actual experience and tradeoffs.
- Keep credentials, account files, email addresses, and private screenshots out of public discussions.
- Avoid manufactured testimonials, duplicate self-promotion, and moderator outreach.

## Short descriptions

**GitHub:** Simple Codex account switcher for everyday Mac users. Apple-notarized menu-bar app with no Terminal commands or config-file editing.

**中文短介绍：** 给普通 Mac 用户的 Codex 多账号切换器。账号添加一次，之后从菜单栏选择；无需终端命令或修改配置文件。
