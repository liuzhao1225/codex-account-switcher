import crypto from 'node:crypto';
import fs from 'node:fs/promises';
import path from 'node:path';
import { fileURLToPath, pathToFileURL } from 'node:url';

export const repository = '4379711/codex-account-switcher';
export const windowsAssetName = 'Codex-Account-Switcher-windows-x64.exe';
export const defaultPublicKeyPath = path.resolve(
  path.dirname(fileURLToPath(import.meta.url)),
  'windows-update-public-key.txt',
);

export function canonicalPayload({ version, tag, url, size, sha256 }) {
  return Buffer.from(
    [
      'codex-account-switcher-windows-update-v1',
      version,
      tag,
      url,
      String(size),
      sha256.toLowerCase(),
    ].join('\n'),
    'utf8',
  );
}

export async function readDefaultPublicKey(publicKeyPath = defaultPublicKeyPath) {
  return (await fs.readFile(publicKeyPath, 'utf8')).trim();
}

export function verifyManifestSignature(manifest, publicKeySpkiBase64) {
  const pubKey = crypto.createPublicKey({
    key: Buffer.from(publicKeySpkiBase64.trim(), 'base64'),
    format: 'der',
    type: 'spki',
  });
  const sig = Buffer.from(manifest.signature, 'base64');
  if (sig.length !== 64) return false;
  return crypto.verify(
    'sha256',
    canonicalPayload(manifest),
    { key: pubKey, dsaEncoding: 'ieee-p1363' },
    sig,
  );
}

export function validateWindowsFeed(jsonText, tag, publicKeySpkiBase64, expected = null) {
  if (!/^v(0|[1-9]\d*)\.(0|[1-9]\d*)\.(0|[1-9]\d*)$/.test(tag)) {
    throw new Error(`Expected unified tag v<major>.<minor>.<patch>; got ${tag}.`);
  }
  const version = tag.slice(1);
  const manifest = JSON.parse(jsonText);
  const expectedUrl = `https://github.com/${repository}/releases/download/${tag}/${windowsAssetName}`;
  const expectedNotes = `https://github.com/${repository}/releases/tag/${tag}`;
  if (manifest.version !== version || manifest.tag !== tag) {
    throw new Error('The Windows update feed version differs from the release tag.');
  }
  if (manifest.url !== expectedUrl || manifest.releaseNotesUrl !== expectedNotes) {
    throw new Error('The Windows update feed URLs do not match the official release.');
  }
  if (!Number.isSafeInteger(manifest.size) || manifest.size <= 0) {
    throw new Error('The Windows update feed size is invalid.');
  }
  if (typeof manifest.sha256 !== 'string' || !/^[0-9a-f]{64}$/.test(manifest.sha256)) {
    throw new Error('The Windows update feed sha256 is invalid.');
  }
  if (typeof manifest.signature !== 'string' || !manifest.signature) {
    throw new Error('The Windows update feed is missing its signature.');
  }
  if (expected) {
    if (manifest.size !== expected.size) throw new Error('The Windows update feed size does not match the EXE.');
    if (manifest.sha256 !== expected.sha256.toLowerCase()) {
      throw new Error('The Windows update feed checksum does not match the EXE.');
    }
  }
  if (!verifyManifestSignature(manifest, publicKeySpkiBase64)) {
    throw new Error('The Windows update feed signature is invalid.');
  }
  return manifest;
}

export async function signWindowsUpdate(
  directory,
  tag,
  privateKeyPem = process.env.WINDOWS_UPDATE_PRIVATE_KEY,
  publicKeySpkiBase64 = null,
) {
  if (!/^v(0|[1-9]\d*)\.(0|[1-9]\d*)\.(0|[1-9]\d*)$/.test(tag)) {
    throw new Error(`Expected unified tag v<major>.<minor>.<patch>; got ${tag}.`);
  }
  if (!privateKeyPem || !privateKeyPem.trim()) {
    throw new Error('WINDOWS_UPDATE_PRIVATE_KEY is required to sign the Windows update feed.');
  }
  const pubKey = publicKeySpkiBase64 ?? (await readDefaultPublicKey());
  const exePath = path.join(directory, windowsAssetName);
  const exeBytes = await fs.readFile(exePath);
  if (!exeBytes.length) throw new Error(`Empty package: ${windowsAssetName}`);

  const version = tag.slice(1);
  const sha256 = crypto.createHash('sha256').update(exeBytes).digest('hex');
  const manifest = {
    version,
    tag,
    url: `https://github.com/${repository}/releases/download/${tag}/${windowsAssetName}`,
    size: exeBytes.length,
    sha256,
    releaseNotesUrl: `https://github.com/${repository}/releases/tag/${tag}`,
    signature: '',
  };
  const signature = crypto.sign('sha256', canonicalPayload(manifest), {
    key: privateKeyPem,
    dsaEncoding: 'ieee-p1363',
  });
  manifest.signature = signature.toString('base64');

  const json = JSON.stringify(manifest, null, 2) + '\n';
  validateWindowsFeed(json, tag, pubKey, { size: exeBytes.length, sha256 });
  const outputPath = path.join(directory, 'windows-update.json');
  await fs.writeFile(outputPath, json, 'utf8');
  return outputPath;
}

if (process.argv[1] && import.meta.url === pathToFileURL(process.argv[1]).href) {
  const out = await signWindowsUpdate(process.argv[2], process.argv[3]);
  console.log(`Signed Windows update feed: ${out}`);
}
