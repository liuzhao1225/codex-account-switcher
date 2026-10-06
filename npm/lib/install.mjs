import { spawn, spawnSync } from "node:child_process";
import { createHash } from "node:crypto";
import { createReadStream, createWriteStream } from "node:fs";
import { copyFile, lstat, mkdir, mkdtemp, readdir, rename, rm, rmdir } from "node:fs/promises";
import os from "node:os";
import path from "node:path";
import { fileURLToPath } from "node:url";
import { Readable, Transform } from "node:stream";
import { pipeline } from "node:stream/promises";

export const assets = {
  macOS: "Codex-Account-Switcher-macos-arm64.dmg",
  windows: "Codex-Account-Switcher-windows-x64.exe",
};
const appName = "Codex Account Switcher.app";
const bundleID = "com.liuzhao.codex-account-switcher";
const windowsName = "Codex Account Switcher.exe";
const launchServices = "/System/Library/Frameworks/CoreServices.framework/Frameworks/LaunchServices.framework/Support/lsregister";

async function statIfExists(target) {
  try { return await lstat(target); }
  catch (error) { if (error.code === "ENOENT") return undefined; throw error; }
}

export async function installTarget({ platform = process.platform, arch = process.arch,
  release = os.release(), home = os.homedir(), localAppData = process.env.LOCALAPPDATA,
  directory } = {}) {
  if (platform === "darwin" && arch === "arm64" && Number(release.split(".")[0]) >= 23) {
    const target = path.resolve(directory ?? path.join(home, "Applications"), appName);
    const standardTargets = [
      path.join(home, "Applications", appName),
      path.join("/Applications", appName),
    ];
    return {
      platform,
      asset: assets.macOS,
      target,
      legacyTargets: standardTargets.filter((candidate) => path.resolve(candidate) !== target),
    };
  }
  if (platform === "win32" && arch === "x64" && Number(release.split(".")[0]) >= 10) {
    if (!directory && !localAppData) throw new Error("LOCALAPPDATA is unavailable; pass --dir <directory>.");
    return { platform, asset: assets.windows, target: path.resolve(directory ?? path.join(localAppData, "Programs", "Codex Account Switcher"), windowsName), legacyTargets: [] };
  }
  throw new Error(`Unsupported system: ${platform}/${arch} (${release}). Requires macOS 14+ with ARM64 Node.js, or Windows 10/11 with x64 Node.js.`);
}

async function responseFor(url, fetchImpl, options = {}) {
  let response;
  try {
    response = await fetchImpl(url, { signal: AbortSignal.timeout(120_000), headers: { "User-Agent": "codex-account-switcher-installer" }, ...options });
  } catch (error) {
    throw new Error(`Request failed for ${url}: ${error.cause?.message ?? error.message}`);
  }
  if (!response.ok) throw new Error(`Download failed: HTTP ${response.status} for ${url}`);
  return response;
}

export async function latestRelease(repository, fetchImpl = fetch) {
  const response = await responseFor(`${repository}/releases/latest`, fetchImpl, { method: "HEAD" });
  const tagPrefix = `${repository}/releases/tag/`;
  const tag = response.url.startsWith(tagPrefix) ? response.url.slice(tagPrefix.length) : "";
  if (!/^v(0|[1-9]\d*)\.(0|[1-9]\d*)\.(0|[1-9]\d*)$/.test(tag)) throw new Error(`GitHub latest did not resolve to an official stable version: ${response.url}`);
  // Resolve latest once, then pin both downloads to that tag to avoid mixed releases.
  return { version: tag.slice(1), downloadBase: `${repository}/releases/download/${tag}` };
}

export async function releaseChecksum(downloadBase, asset, fetchImpl = fetch) {
  const url = `${downloadBase}/${asset}.sha256`;
  const checksum = (await (await responseFor(url, fetchImpl)).text()).trim();
  const match = checksum.match(/^([a-fA-F0-9]{64})\s+\*?([^\r\n]+)$/);
  if (!match || match[2] !== asset) throw new Error(`Invalid SHA-256 file: ${url}`);
  return match[1].toLowerCase();
}

export async function fileHash(file) {
  const hash = createHash("sha256");
  for await (const chunk of createReadStream(file)) hash.update(chunk);
  return hash.digest("hex");
}

export async function downloadVerified(downloadBase, asset, destination, checksum, fetchImpl = fetch) {
  const response = await responseFor(`${downloadBase}/${asset}`, fetchImpl);
  const hash = createHash("sha256");
  await pipeline(Readable.fromWeb(response.body), new Transform({
    transform(chunk, encoding, callback) { hash.update(chunk); callback(null, chunk); },
  }), createWriteStream(destination, { flags: "wx" }));
  const actual = hash.digest("hex");
  if (actual !== checksum) throw new Error(`SHA-256 mismatch for ${asset}: expected ${checksum}, received ${actual}. Installation stopped.`);
}

function run(command, args, options = {}) {
  const result = spawnSync(command, args, { encoding: "utf8", windowsHide: true, ...options });
  if (result.error) throw result.error;
  if (result.status !== 0) throw new Error(`${command} failed (status ${result.status}, signal ${result.signal}): ${result.stderr.trim()}\n${result.stdout.trim()}`);
  return result.stdout.trim();
}

function appVersion(app, runCommand) {
  const plist = path.join(app, "Contents", "Info.plist");
  const readKey = (key) => runCommand("/usr/bin/plutil", ["-extract", key, "raw", "-o", "-", plist]);
  if (readKey("CFBundleIdentifier") !== bundleID) throw new Error(`Unexpected application identity at ${app}. No files were replaced.`);
  return readKey("CFBundleShortVersionString");
}

function powershell(script, variables = {}) {
  return run("powershell.exe", ["-NoProfile", "-NonInteractive", "-OutputFormat", "Text", "-EncodedCommand", Buffer.from(`$ErrorActionPreference = 'Stop'; $ProgressPreference = 'SilentlyContinue'; [Console]::OutputEncoding = [Text.UTF8Encoding]::new($false); ${script}`, "utf16le").toString("base64")], { env: { ...process.env, ...variables } });
}

async function installedVersion(platform, target) {
  const existing = await statIfExists(target);
  if (!existing) return undefined;
  if (existing.isSymbolicLink() || (platform === "darwin" ? !existing.isDirectory() : !existing.isFile())) {
    throw new Error(`Unexpected installation target: ${target}. No files were replaced.`);
  }
  if (platform === "darwin") return appVersion(target, run);
  const info = JSON.parse(powershell("(Get-Item -LiteralPath $env:CODEX_SWITCHER_TARGET).VersionInfo | Select-Object ProductName, FileVersion | ConvertTo-Json -Compress", { CODEX_SWITCHER_TARGET: target }));
  if (info.ProductName !== "Codex-Account-Switcher-windows-x64") throw new Error(`Unexpected EXE identity at ${target}. No files were replaced.`);
  return info.FileVersion;
}

export function compareVersions(installed, latest) {
  const parse = (value) => {
    const match = value.match(/^(\d+)\.(\d+)\.(\d+)(?:\.0)?(?:\+.*)?$/);
    if (!match) throw new Error(`Unrecognized installed version: ${value}`);
    return match.slice(1, 4).map(Number);
  };
  const left = parse(installed);
  const right = parse(latest);
  for (let i = 0; i < 3; i++) if (left[i] !== right[i]) return Math.sign(left[i] - right[i]);
  return 0;
}

function requireMacClosed(target, runCommand = run) {
  if (runCommand("/bin/ps", ["-axo", "comm="]).split("\n").some((command) => command.trim().startsWith(`${target}/Contents/MacOS/`))) {
    throw new Error(`Quit Codex Account Switcher before changing ${target}. No files were replaced.`);
  }
}

async function sameMacApp(target, runCommand = run) {
  const existing = await statIfExists(target);
  if (!existing) return false;
  if (existing.isSymbolicLink() || !existing.isDirectory()) {
    throw new Error(`Unexpected legacy installation target: ${target}. No files were replaced.`);
  }
  try {
    appVersion(target, runCommand);
  } catch (error) {
    if (error.message.startsWith("Unexpected application identity")) return false;
    throw error;
  }
  return true;
}

export async function removeMacLegacyApps(targets, runCommand = run) {
  const removable = [];
  for (const target of targets) {
    if (await sameMacApp(target, runCommand)) {
      requireMacClosed(target, runCommand);
      removable.push(target);
    }
  }
  for (const target of removable) {
    await rm(target, { recursive: true });
    configureLauncher("darwin", target, true, runCommand);
  }
  return removable;
}

export function configureLauncher(platform, target, remove = false, runCommand = run) {
  if (platform === "darwin") return runCommand(launchServices, [remove ? "-u" : "-f", target]);
  return powershell(`
    $link = Join-Path ([Environment]::GetFolderPath('Programs')) 'Codex Account Switcher.lnk';
    Add-Type -Path $env:CODEX_SWITCHER_SHORTCUT_SOURCE;
    if ($env:CODEX_SWITCHER_REMOVE -eq 'true') {
      if ((Test-Path -LiteralPath $link) -and [SwitcherShortcut]::Read($link) -eq $env:CODEX_SWITCHER_TARGET) { Remove-Item -LiteralPath $link }
    } else {
      if (!(Test-Path -LiteralPath $env:CODEX_SWITCHER_TARGET)) { throw 'Shortcut target does not exist' }
      [SwitcherShortcut]::Write($env:CODEX_SWITCHER_TARGET, $link);
    }
  `, { CODEX_SWITCHER_TARGET: target, CODEX_SWITCHER_REMOVE: String(remove), CODEX_SWITCHER_SHORTCUT_SOURCE: fileURLToPath(new URL("./windows-shortcut.cs", import.meta.url)) });
}

function checkMacApp(app, runCommand) {
  runCommand("/usr/bin/codesign", ["--verify", "--deep", "--strict", app]);
  runCommand("/usr/sbin/spctl", ["--assess", "--type", "execute", app]);
}

async function cleanup(directory, failure) {
  try { await rm(directory, { recursive: true, force: true }); }
  catch (error) { throw new Error(`${failure ? `${failure.message}\n` : ""}Temporary file cleanup failed at ${directory}: ${error.message}`); }
  if (failure) throw failure;
}

export async function installMac(dmg, target, version, temporary, runCommand = run) {
  const mount = path.join(temporary, "mounted");
  await mkdir(mount);
  runCommand("/usr/bin/hdiutil", ["attach", "-readonly", "-nobrowse", "-mountpoint", mount, dmg]);
  let failure;
  let staging;
  try {
    const source = path.join(mount, appName);
    if (appVersion(source, runCommand) !== version) throw new Error("The DMG's app version does not match GitHub latest.");
    checkMacApp(source, runCommand);
    await mkdir(path.dirname(target), { recursive: true });
    staging = await mkdtemp(path.join(path.dirname(target), ".codex-account-switcher-"));
    const prepared = path.join(staging, appName);
    runCommand("/usr/bin/ditto", [source, prepared]);
    checkMacApp(prepared, runCommand);
    const existing = await statIfExists(target);
    if (existing) {
      if (!existing.isDirectory() || existing.isSymbolicLink()) throw new Error(`Expected an app directory at ${target}. No files were replaced.`);
      appVersion(target, runCommand);
      requireMacClosed(target, runCommand);
      await rm(target, { recursive: true });
    }
    await rename(prepared, target);
  } catch (error) { failure = error; }
  try { runCommand("/usr/bin/hdiutil", ["detach", mount]); }
  catch (error) { failure = new Error(`${failure ? `${failure.message}\n` : ""}Could not detach ${mount}: ${error.message}`); }
  if (staging) await cleanup(staging, failure);
  else if (failure) throw failure;
}

export async function installWindows(executable, target) {
  const existing = await statIfExists(target);
  if (existing && (!existing.isFile() || existing.isSymbolicLink())) throw new Error(`Expected an EXE file at ${target}. No files were replaced.`);
  await mkdir(path.dirname(target), { recursive: true });
  const staging = await mkdtemp(path.join(path.dirname(target), ".codex-account-switcher-"));
  let failure;
  try {
    const prepared = path.join(staging, assets.windows);
    await copyFile(executable, prepared);
    await rename(prepared, target);
  } catch (error) { failure = new Error(`${error.message}\nQuit Codex Account Switcher before updating, and check write permission for ${target}.`); }
  await cleanup(staging, failure);
}

export async function installApp({ repository, directory, log = console.log }) {
  const { platform, asset, target, legacyTargets = [] } = await installTarget({ directory });
  const { version, downloadBase } = await latestRelease(repository);
  log(`GitHub latest: v${version}`);
  const checksum = await releaseChecksum(downloadBase, asset);
  const existing = await installedVersion(platform, target);
  if (existing) {
    if (compareVersions(existing, version) > 0) throw new Error(`Installed v${existing} is newer than GitHub latest v${version}; refusing to downgrade ${target}.`);
    const current = platform === "darwin" ? compareVersions(existing, version) === 0 : await fileHash(target) === checksum;
    if (current) {
      if (platform === "darwin") checkMacApp(target, run);
      // Keep the standard installation locations single-valued even when the
      // selected target is already current. Without this cleanup, an older
      // /Applications copy can remain visible in Spotlight forever.
      if (platform === "darwin") await removeMacLegacyApps(legacyTargets);
      configureLauncher(platform, target);
      log(`Already up to date: Codex Account Switcher v${version} at ${target}`);
      return target;
    }
  }
  const temporary = await mkdtemp(path.join(os.tmpdir(), "codex-account-switcher-"));
  let failure;
  try {
    const artifact = path.join(temporary, asset);
    log(`Downloading ${downloadBase}/${asset}`);
    await downloadVerified(downloadBase, asset, artifact, checksum);
    log(`SHA-256 verified: ${checksum}`);
    if (platform === "darwin") {
      // Check legacy locations before replacing anything so a running old copy
      // stops the update without leaving a partially migrated installation.
      for (const legacyTarget of legacyTargets) {
        if (await sameMacApp(legacyTarget)) requireMacClosed(legacyTarget);
      }
      await installMac(artifact, target, version, temporary);
      await removeMacLegacyApps(legacyTargets);
    }
    else await installWindows(artifact, target);
  } catch (error) { failure = error; }
  // A failed detach must not make recursive cleanup traverse a mounted image.
  if (platform === "darwin" && run("/sbin/mount", []).includes(` on ${path.join(temporary, "mounted")} (`)) {
    throw new Error(`${failure?.message ?? "Installation stopped."}\nTemporary files remain at ${temporary}; detach the image before removing them.`);
  }
  await cleanup(temporary, failure);
  configureLauncher(platform, target);
  log(`${existing ? "Updated" : "Installed"} Codex Account Switcher v${version}: ${target}`);
  log(platform === "darwin" ? `Open the app from Finder: ${path.dirname(target)}` : `Open the EXE to start the app: ${target}`);
  return target;
}

export async function openApp({ directory }) {
  const { platform, target } = await installTarget({ directory });
  if (!await installedVersion(platform, target)) throw new Error(`Application not installed at ${target}. Run codex-account-switcher install first.`);
  if (platform === "darwin") run("/usr/bin/open", [target]);
  else await new Promise((resolve, reject) => {
    const child = spawn(target, [], { detached: true, stdio: "ignore", cwd: path.dirname(target) });
    child.once("error", reject);
    child.once("spawn", () => { child.unref(); resolve(); });
  });
}

export async function uninstallApp({ directory, log = console.log }) {
  const { platform, target } = await installTarget({ directory });
  if (!await installedVersion(platform, target)) { log(`Application is not installed at ${target}.`); return; }
  if (platform === "darwin") requireMacClosed(target);
  // Remove only this app and its launcher. Account data is stored elsewhere and is never touched.
  await rm(target, { recursive: platform === "darwin" });
  configureLauncher(platform, target, true);
  if (platform === "win32" && (await readdir(path.dirname(target))).length === 0) await rmdir(path.dirname(target));
  log(`Uninstalled ${target}. Saved accounts and preferences were preserved.`);
}
