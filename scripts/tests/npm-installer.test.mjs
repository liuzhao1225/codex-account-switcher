import assert from "node:assert/strict";
import { cpSync, mkdirSync, writeFileSync } from "node:fs";
import { access, mkdtemp, mkdir, readFile, rm, stat, symlink, writeFile } from "node:fs/promises";
import { createHash } from "node:crypto";
import os from "node:os";
import path from "node:path";
import test from "node:test";
import { assets, compareVersions, downloadVerified, installMac, installTarget, installWindows, latestRelease, macLegacyAppsToRemove, releaseChecksum, removeMacLegacyApps } from "../../npm/lib/install.mjs";

const repository = "https://github.com/liuzhao1225/codex-account-switcher";
const asset = assets.windows;
const digest = (value) => createHash("sha256").update(value).digest("hex");
const fixture = (version) => ({ ok: true, url: `${repository}/releases/tag/v${version}` });
const temporary = async (t) => {
  const dir = await mkdtemp(path.join(os.tmpdir(), "npm-switcher-test-"));
  t.after(() => rm(dir, { recursive: true, force: true }));
  return dir;
};

test("latest is resolved on every invocation without changing the npm version", async () => {
  let release = fixture("0.1.16");
  const fetchImpl = async (url) => {
    assert.equal(url, `${repository}/releases/latest`);
    return release;
  };
  const first = await latestRelease(repository, fetchImpl);
  release = fixture("0.1.17");
  const next = await latestRelease(repository, fetchImpl);
  assert.equal(first.version, "0.1.16");
  assert.equal(next.version, "0.1.17");
  assert.equal(first.downloadBase, `${repository}/releases/download/v0.1.16`);
  assert.equal(next.downloadBase, `${repository}/releases/download/v0.1.17`);
});

test("unresolved, prerelease, foreign and HTTP-error releases fail explicitly", async () => {
  for (const url of [repository + '/releases/latest', repository + '/releases/tag/v0.1.16-beta.1', 'https://example.com/releases/tag/v0.1.16']) {
    await assert.rejects(latestRelease(repository, async () => ({ ok: true, url })), /latest/);
  }
  await assert.rejects(latestRelease(repository, async () => new Response("rate limited", { status: 403 })), /HTTP 403/);
});

test("checksums and downloads use the same resolved version and reject corruption", async (t) => {
  const dir = await temporary(t);
  const base = `${repository}/releases/download/v0.1.16`;
  const data = "native release bytes";
  const urls = [];
  const fetchImpl = async (url) => {
    urls.push(url);
    return new Response(url.endsWith(".sha256") ? `${digest(data)}  ${asset}\n` : data);
  };
  const checksum = await releaseChecksum(base, asset, fetchImpl);
  await downloadVerified(base, asset, path.join(dir, "verified.exe"), checksum, fetchImpl);
  assert.deepEqual(urls, [`${base}/${asset}.sha256`, `${base}/${asset}`]);
  assert.equal(await readFile(path.join(dir, "verified.exe"), "utf8"), data);
  await assert.rejects(downloadVerified(base, asset, path.join(dir, "corrupt.exe"), "0".repeat(64), fetchImpl), /SHA-256 mismatch/);
  await assert.rejects(releaseChecksum(base, asset, async () => new Response(`${digest(data)} wrong.exe`)), /Invalid SHA-256/);
});

test("targets are user-level and unsupported platforms fail before downloading", async () => {
  const home = path.resolve("test-home");
  assert.equal((await installTarget({ platform: "darwin", arch: "arm64", release: "23.0.0", home })).target, path.join(home, "Applications", "Codex Account Switcher.app"));
  assert.equal((await installTarget({ platform: "win32", arch: "x64", release: "10.0.0", localAppData: home })).target, path.join(home, "Programs", "Codex Account Switcher", "Codex Account Switcher.exe"));
  for (const params of [{ platform: "linux", arch: "x64" }, { platform: "darwin", arch: "x64" }, { platform: "darwin", arch: "arm64", release: "22.0.0" }]) {
    await assert.rejects(installTarget(params), /Unsupported system/);
  }
  assert.equal(compareVersions("0.1.16.0", "0.1.16"), 0);
  assert.equal(compareVersions("0.2.0", "0.1.16"), 1);
  assert.equal(compareVersions("0.1.9", "0.1.16"), -1);
});

test("Windows deployment replaces the EXE and leaves neighboring files intact", async (t) => {
  const dir = await temporary(t);
  const source = path.join(dir, "download.exe");
  const target = path.join(dir, "application", "Codex Account Switcher.exe");
  await writeFile(source, "v1");
  await installWindows(source, target);
  await writeFile(path.join(path.dirname(target), "keep.txt"), "user data");
  await writeFile(source, "v2");
  await installWindows(source, target);
  assert.equal(await readFile(target, "utf8"), "v2");
  assert.equal(await readFile(path.join(path.dirname(target), "keep.txt"), "utf8"), "user data");
});

test("macOS deployment removes obsolete app files, preserves neighbors, and blocks a running app", async (t) => {
  const dir = await temporary(t);
  const target = path.join(dir, "Applications", "Codex Account Switcher.app");
  await mkdir(target, { recursive: true });
  await writeFile(path.join(target, "old-resource"), "old");
  await writeFile(path.join(path.dirname(target), "keep.txt"), "user data");
  let running = true;
  let detachCount = 0;
  const fakeRun = (command, args) => {
    if (command.endsWith("plutil")) return args[1] === "CFBundleIdentifier" ? "com.liuzhao.codex-account-switcher" : "0.1.16";
    if (command.endsWith("ditto")) cpSync(args[0], args[1], { recursive: true });
    if (command.endsWith("ps")) return running ? `${target}/Contents/MacOS/CodexAccountSwitcher` : "";
    if (command.endsWith("hdiutil") && args[0] === "detach") detachCount++;
    return "";
  };
  for (let pass = 0; pass < 2; pass++) {
    const temp = path.join(dir, `download-${pass}`);
    const source = path.join(temp, "mounted", "Codex Account Switcher.app");
    await mkdir(temp);
    const run = (command, args) => {
      if (command.endsWith("hdiutil") && args[0] === "attach") {
        mkdirSync(source, { recursive: true });
        writeFileSync(path.join(source, "new-resource"), "new");
      }
      return fakeRun(command, args);
    };
    if (running) {
      await assert.rejects(installMac("test.dmg", target, "0.1.16", temp, run), /Quit Codex/);
      assert.equal(await readFile(path.join(target, "old-resource"), "utf8"), "old");
      running = false;
    } else {
      await installMac("test.dmg", target, "0.1.16", temp, run);
      await assert.rejects(readFile(path.join(target, "old-resource")), { code: "ENOENT" });
      assert.equal(await readFile(path.join(target, "new-resource"), "utf8"), "new");
      assert.equal(await readFile(path.join(path.dirname(target), "keep.txt"), "utf8"), "user data");
    }
  }
  assert.equal(detachCount, 2);
});

test("macOS legacy cleanup removes only recognized, stopped app bundles", async (t) => {
  const dir = await temporary(t);
  const oldApp = path.join(dir, "Applications", "Codex Account Switcher.app");
  const unrelatedApp = path.join(dir, "Applications", "Other Switcher.app");
  await mkdir(path.join(oldApp, "Contents"), { recursive: true });
  await mkdir(path.join(unrelatedApp, "Contents"), { recursive: true });
  const run = (command, args) => {
    if (command.endsWith("plutil")) {
      const recognized = args.at(-1).startsWith(oldApp);
      return args[1] === "CFBundleIdentifier"
        ? (recognized ? "com.liuzhao.codex-account-switcher" : "com.example.other")
        : "0.1.14";
    }
    if (command.endsWith("ps")) return "";
    return "";
  };
  const options = { targets: [oldApp, unrelatedApp], selectedTarget: path.join(dir, "Current.app"), version: "0.2.0" };
  assert.deepEqual(await macLegacyAppsToRemove(options, run), [oldApp]);
  await access(oldApp);
  const removed = await removeMacLegacyApps(options, run);
  assert.deepEqual(removed, [oldApp]);
  await assert.rejects(readFile(oldApp), { code: "ENOENT" });
  await access(unrelatedApp);
});

test("macOS cleanup preserves the selected app through a symlinked installation directory", async (t) => {
  const home = await temporary(t);
  const applications = path.join(home, "Applications");
  const alias = path.join(home, "apps-alias");
  const app = path.join(applications, "Codex Account Switcher.app");
  await mkdir(path.join(app, "Contents"), { recursive: true });
  await symlink(applications, alias, process.platform === "win32" ? "junction" : "dir");
  const { target, legacyTargets } = await installTarget({ platform: "darwin", arch: "arm64", release: "23.0.0", home, directory: alias });
  assert.ok(legacyTargets.includes(app));
  const options = { targets: [app], selectedTarget: target, version: "0.2.0" };
  const run = () => assert.fail("The selected app must be excluded before command execution");
  assert.deepEqual(await removeMacLegacyApps(options, run), []);
  await access(target);
  await access(app);
});

test("macOS cleanup preserves case aliases of the selected app", { skip: process.platform !== "darwin" }, async (t) => {
  const home = await temporary(t);
  const app = path.join(home, "Applications", "Codex Account Switcher.app");
  await mkdir(path.join(app, "Contents"), { recursive: true });
  const selectedTarget = path.join(home, "applications", "Codex Account Switcher.app");
  let alias;
  try { alias = await stat(selectedTarget); }
  catch (error) {
    if (error.code === "ENOENT") { t.skip("The test filesystem is case-sensitive"); return; }
    throw error;
  }
  assert.equal(alias.ino, (await stat(app)).ino);
  assert.deepEqual(await removeMacLegacyApps({ targets: [app], selectedTarget, version: "0.2.0" },
    () => assert.fail("A case alias must never be scheduled for removal")), []);
  await access(app);
});

for (const scenario of ["newer", "running"]) {
  test(`macOS cleanup rejects a ${scenario} copy before deleting any app`, async (t) => {
    const dir = await temporary(t);
    const oldApp = path.join(dir, "Old.app");
    const protectedApp = path.join(dir, "Protected.app");
    const selectedTarget = path.join(dir, "Selected.app");
    for (const app of [oldApp, protectedApp, selectedTarget]) await mkdir(app);
    const run = (command, args) => {
      if (command.endsWith("plutil")) {
        if (args[1] === "CFBundleIdentifier") return "com.liuzhao.codex-account-switcher";
        return scenario === "newer" && args.at(-1).startsWith(protectedApp) ? "0.3.0" : "0.1.16";
      }
      if (command.endsWith("ps")) return scenario === "running" ? `${protectedApp}/Contents/MacOS/CodexAccountSwitcher` : "";
      assert.fail("No launcher should be unregistered after preflight fails");
    };
    const options = { targets: [oldApp, protectedApp], selectedTarget, version: "0.2.0" };
    const expected = scenario === "newer" ? /refusing to remove/ : /Quit Codex/;
    await assert.rejects(macLegacyAppsToRemove(options, run), expected);
    await assert.rejects(removeMacLegacyApps(options, run), expected);
    for (const app of [oldApp, protectedApp, selectedTarget]) await access(app);
  });
}
