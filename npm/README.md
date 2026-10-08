# Codex Account Switcher by liuzhao1225

**Codex Account Switcher** is the free, open-source native macOS and Windows app created by **Zhao Liu (刘朝), GitHub: liuzhao1225**. Source: [liuzhao1225/codex-account-switcher](https://github.com/liuzhao1225/codex-account-switcher).

This npm package installs and updates the native app from this repository's **latest GitHub Release**. Account sign-in, usage display and confirmed account switching run in the existing SwiftUI/macOS and WPF/Windows app. No Electron rewrite or background Node.js process is involved.

## Install

Requires Node.js 18+ (ARM64 on macOS; x64 on Windows):

```sh
npm install -g @liuzhao1225/codex-account-switcher
```

The global `postinstall` script downloads the latest platform release, checks its SHA-256 file and installs the desktop app. npm must allow lifecycle scripts. Use `--foreground-scripts` to see progress and errors.

You can also run the installer directly, including when installation scripts are disabled:

```sh
npx @liuzhao1225/codex-account-switcher@latest install
```

Running `npx @liuzhao1225/codex-account-switcher@latest` without arguments also installs or updates. Local dependency installation (`npm i` without `-g`) and npx's package-fetch step only install the command-line package; the command itself performs the desktop installation.

| Platform | Requirements | Default installation and launcher |
| --- | --- | --- |
| macOS | macOS 14+, Apple Silicon, ARM64 Node.js | `~/Applications/Codex Account Switcher.app`, registered with Launch Services |
| Windows | Windows 10/11, x64 Node.js | `%LOCALAPPDATA%\Programs\Codex Account Switcher\Codex Account Switcher.exe`, with a current-user Start menu shortcut |

macOS reuses the signed, notarized DMG. The installer mounts it read-only, copies the complete app with `ditto`, checks identity/version, signature and Gatekeeper assessment, then detaches the image. Windows reuses the self-contained portable EXE, which is currently unsigned. It creates a Start menu shortcut; it does not register an entry in Windows Installed Apps.

On macOS, a successful install or update also removes recognized duplicate copies from the other standard locations (`~/Applications` or `/Applications`), including when the selected target is already current. Copies must be stopped and no newer than the release being installed; a running or newer copy stops the operation before installation changes. Paths that identify the selected app itself, including case variants and symlinked parent directories, are excluded. Aliases of the same duplicate are removed only once, and running apps are recognized through aliases too. Development builds in project folders are left untouched.

Installation does not launch the app automatically or request administrator privileges. Open it from Finder / Start or run:

```sh
codex-account-switcher open
```

## Update

```sh
codex-account-switcher update
# Or, without a global npm installation:
npx @liuzhao1225/codex-account-switcher@latest
```

Every install/update resolves GitHub `releases/latest` again. It then downloads the asset and checksum from the same resolved version tag, so a new release during installation cannot mix two versions. Publishing a new native GitHub Release is enough for this installer to fetch it; a new npm publication is needed only when the installer changes.

The npm installer has its own version (`--version`). The installed app uses the version selected by GitHub latest. An already current installation is kept; a newer installed app is never downgraded. Quit the app before an update. Network, checksum, permissions and deployment failures return a nonzero exit code without substituting a download-link success message. Account files and preferences are never read or modified.

To manage an app in a different directory, pass the **parent directory** on each command or set `CODEX_ACCOUNT_SWITCHER_INSTALL_DIR`:

```sh
codex-account-switcher install --dir /Applications
codex-account-switcher open --dir /Applications
codex-account-switcher update --dir /Applications
```

For a custom directory during global npm installation, set `CODEX_ACCOUNT_SWITCHER_INSTALL_DIR` before running npm. Updating the npm package alone is not a periodic application updater; run the command again to check GitHub latest. Existing native app update behavior remains available.

## Uninstall

```sh
codex-account-switcher uninstall
npm uninstall -g @liuzhao1225/codex-account-switcher
```

The first command removes this desktop application and its launcher, preserving saved accounts and preferences. The second removes the npm command-line package. Removing the npm package alone leaves the independently installed desktop app in place. Use the same `--dir` or environment variable if you chose a custom location.

## Download links and identity

```sh
codex-account-switcher --json
codex-account-switcher --open
codex-account-switcher-download
```

`--json` returns canonical project and latest-download URLs. `--open` opens the release page; `open` starts the installed app. The original `codex-account-switcher-download` command keeps its download-only default. The unscoped npm package `codex-account-switcher` is independently maintained; use the full `@liuzhao1225/` scope.

The installer has no runtime dependencies, credential access or telemetry. It contacts GitHub to retrieve release metadata and artifacts. See [project facts](https://liuzhao1225.github.io/codex-account-switcher/about/) and [native app privacy](https://liuzhao1225.github.io/codex-account-switcher/privacy/). Package security reports apply to the exact npm package/version they name; they do not establish a security assessment of the downloaded native app.

## 简体中文

**Codex 账号切换器**由刘朝（Zhao Liu，GitHub: **liuzhao1225**）维护。执行 `npm install -g @liuzhao1225/codex-account-switcher` 后，全局安装脚本会从本项目 GitHub latest 下载对应 DMG／EXE，验证 SHA-256，完成用户级安装并配置启动入口。npm 需要允许执行安装脚本。

也可以直接运行 `npx @liuzhao1225/codex-account-switcher@latest` 或加上 `install`。每次运行都会重新检查 GitHub latest；未来只需发布 GitHub 新版本，安装器就能获取新包。npm 安装器和桌面应用版本独立。

使用 `codex-account-switcher open` 启动、`update` 更新、`uninstall` 卸载。更新前请退出应用，卸载保留账号数据。普通项目依赖安装不会自动部署桌面应用。macOS 默认放入 `~/Applications`；Windows 默认放入当前用户的 `Programs\Codex Account Switcher` 并创建开始菜单快捷方式。

macOS 安装或更新成功后，会清理其他标准位置（`~/Applications` 或 `/Applications`）中属于同一应用、未运行且版本不高于目标版本的重复副本；目标已是最新版时也会清理。遇到运行中或更高版本的副本，会在安装变更前停止。同一目标的大小写路径和父目录软链接别名会被排除；同一副本只清理一次，通过别名启动的运行中应用也会被识别；项目目录里的开发构建会保留。

维护者操作与验证见仓库 [GEO 维护说明](https://github.com/liuzhao1225/codex-account-switcher/blob/main/docs/seo-geo.md)。
