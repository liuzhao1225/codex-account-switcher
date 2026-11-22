import assert from 'node:assert/strict';
import crypto from 'node:crypto';
import fs from 'node:fs/promises';
import os from 'node:os';
import path from 'node:path';
import test from 'node:test';
import { signWindowsUpdate, validateWindowsFeed, windowsAssetName } from '../sign-windows-update.mjs';
import { latestWindowsRelease, prepareWindowsFeed } from '../prepare-windows-feed.mjs';

function generateKeyPair() {
  const { privateKey, publicKey } = crypto.generateKeyPairSync('ec', { namedCurve: 'prime256v1' });
  return {
    privateKeyPem: privateKey.export({ type: 'pkcs8', format: 'pem' }),
    publicKeySpkiBase64: publicKey.export({ type: 'spki', format: 'der' }).toString('base64'),
  };
}

test('signWindowsUpdate creates a verifiable P-256 feed and rejects tampering', async () => {
  const dir = await fs.mkdtemp(path.join(os.tmpdir(), 'switcher-win-sign-'));
  const { privateKeyPem, publicKeySpkiBase64 } = generateKeyPair();
  const payload = Buffer.from('synthetic-windows-exe-bytes');
  const sha256 = crypto.createHash('sha256').update(payload).digest('hex');
  try {
    await fs.writeFile(path.join(dir, windowsAssetName), payload);
    const out = await signWindowsUpdate(dir, 'v0.2.1', privateKeyPem, publicKeySpkiBase64);
    const json = await fs.readFile(out, 'utf8');
    const manifest = validateWindowsFeed(json, 'v0.2.1', publicKeySpkiBase64, { size: payload.length, sha256 });
    assert.equal(manifest.version, '0.2.1');
    assert.equal(manifest.url, `https://github.com/4379711/codex-account-switcher/releases/download/v0.2.1/${windowsAssetName}`);
    assert.equal(manifest.releaseNotesUrl, 'https://github.com/4379711/codex-account-switcher/releases/tag/v0.2.1');
    assert.equal(manifest.size, payload.length);
    assert.equal(manifest.sha256, sha256);

    assert.throws(() => validateWindowsFeed(json.replace('0.2.1', '0.2.2'), 'v0.2.1', publicKeySpkiBase64));
    assert.throws(() => validateWindowsFeed(json.replaceAll('4379711/', 'liuzhao1225/'), 'v0.2.1', publicKeySpkiBase64), /URLs/);
    const tampered = JSON.parse(json);
    tampered.size += 1;
    assert.throws(() => validateWindowsFeed(JSON.stringify(tampered), 'v0.2.1', publicKeySpkiBase64), /signature is invalid/);
    const otherKey = generateKeyPair().publicKeySpkiBase64;
    assert.throws(() => validateWindowsFeed(json, 'v0.2.1', otherKey), /signature is invalid/);
  } finally {
    await fs.rm(dir, { recursive: true, force: true });
  }
});

test('prepareWindowsFeed selects latest stable unified release with signed feed and handles none gracefully', async () => {
  const dir = await fs.mkdtemp(path.join(os.tmpdir(), 'switcher-win-feed-'));
  const { privateKeyPem, publicKeySpkiBase64 } = generateKeyPair();
  const exe = Buffer.from('win-exe');
  try {
    await fs.writeFile(path.join(dir, windowsAssetName), exe);
    const feedPath = await signWindowsUpdate(dir, 'v0.2.1', privateKeyPem, publicKeySpkiBase64);
    const feedJson = await fs.readFile(feedPath, 'utf8');

    const rel = (tag, extra = {}) => ({
      tag_name: tag,
      draft: false,
      prerelease: false,
      assets: [{ name: 'windows-update.json' }, { name: windowsAssetName }],
      ...extra,
    });
    assert.equal(
      latestWindowsRelease([
        rel('windows-v9.0.0'),
        rel('v9.0.0', { draft: true }),
        rel('v8.0.0', { prerelease: true }),
        rel('v0.2.0', { assets: [{ name: windowsAssetName }] }),
        rel('v0.2.1'),
      ]).tag_name,
      'v0.2.1',
    );

    const output = path.join(dir, 'site', 'updates', 'windows', 'latest.json');
    const none = await prepareWindowsFeed(
      async () => ({ ok: true, json: async () => [rel('v0.2.0', { assets: [{ name: windowsAssetName }] })] }),
      output,
      publicKeySpkiBase64,
    );
    assert.equal(none, null);

    const picked = await prepareWindowsFeed(
      async url => {
        if (url === 'https://api.github.com/repos/4379711/codex-account-switcher/releases?per_page=100&page=1') {
          return { ok: true, json: async () => [rel('v0.2.1')] };
        }
        assert.equal(url, 'https://github.com/4379711/codex-account-switcher/releases/download/v0.2.1/windows-update.json');
        return { ok: true, text: async () => feedJson };
      },
      output,
      publicKeySpkiBase64,
    );
    assert.equal(picked, 'v0.2.1');
    assert.equal(await fs.readFile(output, 'utf8'), feedJson);
  } finally {
    await fs.rm(dir, { recursive: true, force: true });
  }
});
