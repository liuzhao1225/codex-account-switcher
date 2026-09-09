import assert from 'node:assert/strict';
import test from 'node:test';
import fs from 'node:fs/promises';
import os from 'node:os';
import path from 'node:path';
import { latestMacRelease, validateMacFeed, prepareMacFeed } from '../prepare-macos-feed.mjs';

const mac = (tag, extra = {}) => ({ tag_name: tag, draft: false, prerelease: false,
  assets: [{ name: 'appcast.xml' }, { name: 'Codex-Account-Switcher-macos-arm64.dmg' }], ...extra });
const feed = tag => `<rss><channel><item><enclosure url="https://github.com/liuzhao1225/codex-account-switcher/releases/download/${tag}/Codex-Account-Switcher-macos-arm64.dmg" sparkle:edSignature="fixture" /></item></channel></rss>`;

test('macOS ignores newer Windows releases, drafts, previews and incomplete releases', () => {
  const releases = [mac('windows-v99.0.0'), mac('macos-v3.0.0', { draft: true }),
    mac('macos-v2.0.0', { prerelease: true }), mac('macos-v1.2.0', { assets: [] }),
    mac('macos-v1.0.9'), mac('macos-v1.0.10'), mac('v0.9.0')];
  assert.equal(latestMacRelease(releases).tag_name, 'macos-v1.0.10');
  assert.equal(latestMacRelease([mac('v0.1.10')]).tag_name, 'v0.1.10');
});

test('feed validation rejects another platform, unsigned assets and mixed enclosures', () => {
  validateMacFeed(feed('macos-v1.0.0'), 'macos-v1.0.0');
  assert.throws(() => validateMacFeed(feed('windows-v9.0.0'), 'macos-v1.0.0'));
  assert.throws(() => validateMacFeed(feed('macos-v1.0.0').replace('sparkle:edSignature', 'signature'), 'macos-v1.0.0'));
  assert.throws(() => validateMacFeed(feed('macos-v1.0.0') + '<enclosure url="other.exe"/>', 'macos-v1.0.0'));
});

test('site deployment searches beyond 100 Windows releases and copies the Mac feed unchanged', async () => {
  const directory = await fs.mkdtemp(path.join(os.tmpdir(), 'switcher-feed-'));
  const output = path.join(directory, 'updates', 'appcast.xml');
  const requests = [];
  try {
    const tag = await prepareMacFeed(async url => {
      requests.push(url);
      if (url.endsWith('&page=1')) return { ok: true, json: async () => Array.from({ length: 100 }, () => mac('windows-v99.0.0')) };
      if (url.endsWith('&page=2')) return { ok: true, json: async () => [mac('macos-v1.0.0')] };
      assert.ok(url.endsWith('/macos-v1.0.0/appcast.xml'));
      return { ok: true, text: async () => feed('macos-v1.0.0') };
    }, output);
    assert.equal(tag, 'macos-v1.0.0');
    assert.equal(requests.length, 3);
    assert.equal(await fs.readFile(output, 'utf8'), feed('macos-v1.0.0'));
  } finally { await fs.rm(directory, { recursive: true, force: true }); }
});

test('unified releases win equal-version ties over historical platform releases', () => {
  assert.equal(latestMacRelease([mac('macos-v0.1.11'), mac('v0.1.11')]).tag_name, 'v0.1.11');
  assert.equal(latestMacRelease([mac('v0.1.12'), mac('macos-v0.1.11')]).tag_name, 'v0.1.12');
  validateMacFeed(feed('v0.1.12'), 'v0.1.12');
});
