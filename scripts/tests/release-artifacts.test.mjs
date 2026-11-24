import assert from 'node:assert/strict';
import crypto from 'node:crypto';
import test from 'node:test';
import fs from 'node:fs/promises';
import os from 'node:os';
import path from 'node:path';
import { verifyReleaseArtifacts } from '../verify-release-artifacts.mjs';
import { signWindowsUpdate } from '../sign-windows-update.mjs';

test('publishing requires both intact packages and matching signed feeds', async () => {
  const dir = await fs.mkdtemp(path.join(os.tmpdir(), 'switcher-assets-'));
  const mac = 'Codex-Account-Switcher-macos-arm64.dmg';
  const win = 'Codex-Account-Switcher-windows-x64.exe';
  const macKeys = crypto.generateKeyPairSync('ed25519');
  const macPublicKey = Buffer.from(macKeys.publicKey.export({ format: 'jwk' }).x, 'base64url').toString('base64');
  const { privateKey, publicKey } = crypto.generateKeyPairSync('ec', { namedCurve: 'prime256v1' });
  const privPem = privateKey.export({ type: 'pkcs8', format: 'pem' });
  const pubSpki = publicKey.export({ type: 'spki', format: 'der' }).toString('base64');
  try {
    for (const name of [mac, win]) {
      await fs.writeFile(path.join(dir, name), name);
      await fs.writeFile(path.join(dir, name + '.sha256'), crypto.createHash('sha256').update(name).digest('hex') + '  ' + name + '\n');
    }
    const macSignature = crypto.sign(null, Buffer.from(mac), macKeys.privateKey).toString('base64');
    const macSize = Buffer.byteLength(mac);
    const xml = `<rss><sparkle:version>1.2.3</sparkle:version><sparkle:shortVersionString>1.2.3</sparkle:shortVersionString><enclosure url="https://github.com/liuzhao1225/codex-account-switcher/releases/download/v1.2.3/${mac}" length="${macSize}" sparkle:edSignature="${macSignature}" /></rss>`;
    await fs.writeFile(path.join(dir, 'appcast.xml'), xml);
    await signWindowsUpdate(dir, 'v1.2.3', privPem, pubSpki);

    await verifyReleaseArtifacts(dir, 'v1.2.3', pubSpki, macPublicKey);
    await assert.rejects(verifyReleaseArtifacts(dir, 'v1.2.4', pubSpki, macPublicKey));
    await fs.writeFile(path.join(dir, 'appcast.xml'), xml.replace('>1.2.3<', '>1.2.2<'));
    await assert.rejects(verifyReleaseArtifacts(dir, 'v1.2.3', pubSpki, macPublicKey), /version differs/);
    await fs.writeFile(path.join(dir, 'appcast.xml'), xml.replace(`length="${macSize}"`, `length="${macSize + 1}"`));
    await assert.rejects(verifyReleaseArtifacts(dir, 'v1.2.3', pubSpki, macPublicKey), /size does not match/);
    const otherMacSignature = crypto.sign(null, Buffer.from('wrong DMG'), macKeys.privateKey).toString('base64');
    await fs.writeFile(path.join(dir, 'appcast.xml'), xml.replace(macSignature, otherMacSignature));
    await assert.rejects(verifyReleaseArtifacts(dir, 'v1.2.3', pubSpki, macPublicKey), /signature is invalid/);
    await fs.writeFile(path.join(dir, 'appcast.xml'), xml);
    await fs.writeFile(path.join(dir, 'windows-update.json'), (await fs.readFile(path.join(dir, 'windows-update.json'), 'utf8')).replace('v1.2.3', 'v1.2.2'));
    await assert.rejects(verifyReleaseArtifacts(dir, 'v1.2.3', pubSpki, macPublicKey));
    await signWindowsUpdate(dir, 'v1.2.3', privPem, pubSpki);
    await fs.writeFile(path.join(dir, win), 'corrupt');
    await assert.rejects(verifyReleaseArtifacts(dir, 'v1.2.3', pubSpki, macPublicKey), /Checksum mismatch/);
    await fs.unlink(path.join(dir, win));
    await assert.rejects(verifyReleaseArtifacts(dir, 'v1.2.3', pubSpki, macPublicKey), /ENOENT/);
  } finally { await fs.rm(dir, { recursive: true }); }
});
