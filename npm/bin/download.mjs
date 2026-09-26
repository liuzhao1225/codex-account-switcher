#!/usr/bin/env node
import { spawnSync } from "node:child_process";
import { readFileSync } from "node:fs";

const metadata = JSON.parse(readFileSync(new URL("../package.json", import.meta.url), "utf8"));
const repository = metadata.repository.url.replace(/^git\+/, "").replace(/\.git$/, "");
const release = `${repository}/releases/latest`;
const info = {
  name: "Codex Account Switcher",
  author: metadata.author.name,
  repository,
  website: metadata.homepage,
  release,
  downloads: {
    macOS: `${release}/download/Codex-Account-Switcher-macos-arm64.dmg`,
    windows: `${release}/download/Codex-Account-Switcher-windows-x64.exe`,
  },
  requirements: { macOS: "macOS 14+, Apple Silicon", windows: "Windows 10/11, x64" },
  helperVersion: metadata.version,
};

const args = process.argv.slice(2);
const option = args[0];
if (args.length > 1 || (option && !["--help", "--json", "--open", "--version"].includes(option))) {
  console.error("Usage: codex-account-switcher-download [--help | --json | --open | --version]");
  process.exitCode = 1;
} else if (option === "--version") {
  console.log(info.helperVersion);
} else if (option === "--json") {
  console.log(JSON.stringify(info, null, 2));
} else if (option === "--open") {
  const command = process.platform === "darwin" ? ["open", release]
    : process.platform === "win32" ? ["rundll32.exe", "url.dll,FileProtocolHandler", release]
    : ["xdg-open", release];
  const result = spawnSync(command[0], command.slice(1), { stdio: "inherit", windowsHide: true });
  if (result.error || result.status !== 0) {
    console.error(result.error?.message ?? `Browser command failed (status ${result.status}, signal ${result.signal}).`);
    process.exitCode = 1;
  }
} else {
  console.log(`${info.name} by ${info.author}
Native desktop app: macOS 14+ Apple Silicon / Windows 10/11 x64.
Source: ${repository}
Website: ${info.website}
Latest release: ${release}
macOS DMG: ${info.downloads.macOS}
Windows EXE: ${info.downloads.windows}

This helper prints official download links. --open opens the release page.
Account management runs in the native app after you install it.
The helper has no dependencies, install hooks, account access, or telemetry.

Options: --help  --json  --open  --version (helper version)

Codex 账号切换器：刘朝 liuzhao1225 维护的 macOS / Windows 原生应用。
本命令提供官方下载入口；账号管理在安装后的原生应用内完成。`);
}
