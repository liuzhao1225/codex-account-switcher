import assert from 'node:assert/strict';
import crypto from 'node:crypto';
import fs from 'node:fs/promises';
import os from 'node:os';
import path from 'node:path';
import test from 'node:test';
import { prepareFeeds } from '../prepare-feeds.mjs';
import { signWindowsUpdate, windowsAssetName } from '../sign-windows-update.mjs';

function generateKeyPair() {
  const { privateKey, publicKey } = crypto.generateKeyPairSync('ec', { namedCurve: 'prime256v1' });
  return {
    privateKeyPem: privateKey.export({ type: 'pkcs8', format: 'pem' }),
    publicKeySpkiBase64: publicKey.export({ type: 'spki', format: 'der' }).toString('base64'),
  };
}

const macFeedXml = tag =>
  `<rss><channel><item><enclosure url="https://github.com/liuzhao1225/codex-account-switcher/releases/download/${tag}/Codex-Account-Switcher-macos-arm64.dmg" sparkle:edSignature="fixture" /></item></channel></rss>`;

const unifiedRelease = (tag, assets) => ({
  tag_name: tag,
  draft: false,
  prerelease: false,
  assets,
});

test('prepareFeeds fetches multi-page GitHub releases once for both macOS and Windows feeds', async () => {
  const dir = await fs.mkdtemp(path.join(os.tmpdir(), 'switcher-prepare-feeds-'));
  const { privateKeyPem, publicKeySpkiBase64 } = generateKeyPair();
  try {
    await fs.writeFile(path.join(dir, windowsAssetName), Buffer.from('win-installer-bytes'));
    const signedFeedPath = await signWindowsUpdate(dir, 'v0.3.0', privateKeyPem, publicKeySpkiBase64);
    const windowsJson = await fs.readFile(signedFeedPath, 'utf8');

    const macOutput = path.join(dir, 'site', 'updates', 'macos', 'appcast.xml');
    const windowsOutput = path.join(dir, 'site', 'updates', 'windows', 'latest.json');
    const requestedUrls = [];

    const page1 = Array.from({ length: 100 }, (_, i) =>
      unifiedRelease(`v0.1.${i}`, [{ name: windowsAssetName }]),
    );
    const page2 = [
      unifiedRelease('macos-v0.2.5', [
        { name: 'appcast.xml' },
        { name: 'Codex-Account-Switcher-macos-arm64.dmg' },
      ]),
      unifiedRelease('v0.3.0', [
        { name: 'appcast.xml' },
        { name: 'Codex-Account-Switcher-macos-arm64.dmg' },
        { name: 'windows-update.json' },
        { name: windowsAssetName },
      ]),
    ];

    const result = await prepareFeeds({
      fetcher: async url => {
        requestedUrls.push(url);
        if (url.endsWith('per_page=100&page=1')) return { ok: true, json: async () => page1 };
        if (url.endsWith('per_page=100&page=2')) return { ok: true, json: async () => page2 };
        if (url.endsWith('/v0.3.0/appcast.xml')) return { ok: true, text: async () => macFeedXml('v0.3.0') };
        if (url.endsWith('/v0.3.0/windows-update.json')) return { ok: true, text: async () => windowsJson };
        throw new Error(`Unexpected request: ${url}`);
      },
      macOutput,
      windowsOutput,
      publicKeySpkiBase64,
    });

    assert.deepEqual(result, { mac: 'v0.3.0', windows: 'v0.3.0' });
    assert.deepEqual(requestedUrls, [
      'https://api.github.com/repos/liuzhao1225/codex-account-switcher/releases?per_page=100&page=1',
      'https://api.github.com/repos/liuzhao1225/codex-account-switcher/releases?per_page=100&page=2',
      'https://github.com/liuzhao1225/codex-account-switcher/releases/download/v0.3.0/appcast.xml',
      'https://github.com/liuzhao1225/codex-account-switcher/releases/download/v0.3.0/windows-update.json',
    ]);
    assert.equal(await fs.readFile(macOutput, 'utf8'), macFeedXml('v0.3.0'));
    assert.equal(await fs.readFile(windowsOutput, 'utf8'), windowsJson);
  } finally {
    await fs.rm(dir, { recursive: true, force: true });
  }
});

test('prepareFeeds still writes appcast.xml when no Windows feed manifest exists', async () => {
  const dir = await fs.mkdtemp(path.join(os.tmpdir(), 'switcher-prepare-feeds-nowin-'));
  const { publicKeySpkiBase64 } = generateKeyPair();
  try {
    const macOutput = path.join(dir, 'site', 'updates', 'macos', 'appcast.xml');
    const windowsOutput = path.join(dir, 'site', 'updates', 'windows', 'latest.json');
    const requestedUrls = [];

    const result = await prepareFeeds({
      fetcher: async url => {
        requestedUrls.push(url);
        if (url.endsWith('per_page=100&page=1')) {
          return {
            ok: true,
            json: async () => [
              unifiedRelease('macos-v0.2.0', [
                { name: 'appcast.xml' },
                { name: 'Codex-Account-Switcher-macos-arm64.dmg' },
              ]),
            ],
          };
        }
        if (url.endsWith('/macos-v0.2.0/appcast.xml')) {
          return { ok: true, text: async () => macFeedXml('macos-v0.2.0') };
        }
        throw new Error(`Unexpected request: ${url}`);
      },
      macOutput,
      windowsOutput,
      publicKeySpkiBase64,
    });

    assert.deepEqual(result, { mac: 'macos-v0.2.0', windows: null });
    assert.equal(requestedUrls.length, 2);
    assert.equal(await fs.readFile(macOutput, 'utf8'), macFeedXml('macos-v0.2.0'));
    await assert.rejects(fs.access(windowsOutput));
  } finally {
    await fs.rm(dir, { recursive: true, force: true });
  }
});
