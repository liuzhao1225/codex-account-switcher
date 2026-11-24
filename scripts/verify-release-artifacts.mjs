import fs from 'node:fs/promises';
import path from 'node:path';
import { createHash, createPublicKey, verify } from 'node:crypto';
import { pathToFileURL } from 'node:url';
import { validateMacFeed } from './prepare-macos-feed.mjs';
import { readDefaultPublicKey, validateWindowsFeed, windowsAssetName } from './sign-windows-update.mjs';

const macAssetName = 'Codex-Account-Switcher-macos-arm64.dmg';
const macPublicKeyPath = new URL('./sparkle-public-key.txt', import.meta.url);

export async function verifyReleaseArtifacts(
  directory,
  tag,
  windowsPublicKeySpkiBase64 = null,
  macPublicKeyBase64 = null,
) {
  if (!/^v(0|[1-9]\d*)\.(0|[1-9]\d*)\.(0|[1-9]\d*)$/.test(tag)) throw new Error('Expected a unified release tag.');
  const buffers = {};
  const hashes = {};
  const sizes = {};
  for (const name of [macAssetName, windowsAssetName]) {
    const data = await fs.readFile(path.join(directory, name));
    if (!data.length) throw new Error(`Empty package: ${name}`);
    const checksum = (await fs.readFile(path.join(directory, `${name}.sha256`), 'utf8')).trim();
    const [hash, file] = checksum.split(/\s+\*?/);
    const actual = createHash('sha256').update(data).digest('hex');
    if (file !== name || hash.toLowerCase() !== actual) {
      throw new Error(`Checksum mismatch: ${name}`);
    }
    buffers[name] = data;
    hashes[name] = actual;
    sizes[name] = data.length;
  }
  const xml = await fs.readFile(path.join(directory, 'appcast.xml'), 'utf8');
  const macUpdate = validateMacFeed(xml, tag);
  const version = tag.slice(1);
  if (!xml.includes(`<sparkle:version>${version}</sparkle:version>`) ||
      !xml.includes(`<sparkle:shortVersionString>${version}</sparkle:shortVersionString>`)) {
    throw new Error('The update feed version differs from the release tag.');
  }
  if (macUpdate.size !== sizes[macAssetName]) {
    throw new Error('The macOS update feed size does not match the DMG.');
  }
  const macPublicKey = Buffer.from(
    (macPublicKeyBase64 ?? (await fs.readFile(macPublicKeyPath, 'utf8'))).trim(),
    'base64',
  );
  const publicKey = createPublicKey({
    key: { kty: 'OKP', crv: 'Ed25519', x: macPublicKey.toString('base64url') },
    format: 'jwk',
  });
  if (!verify(null, buffers[macAssetName], publicKey, Buffer.from(macUpdate.signature, 'base64'))) {
    throw new Error('The macOS update feed signature is invalid for the DMG.');
  }
  const winJson = await fs.readFile(path.join(directory, 'windows-update.json'), 'utf8');
  const pubKey = windowsPublicKeySpkiBase64 ?? (await readDefaultPublicKey());
  validateWindowsFeed(winJson, tag, pubKey, {
    size: sizes[windowsAssetName],
    sha256: hashes[windowsAssetName],
  });
}

if (process.argv[1] && import.meta.url === pathToFileURL(process.argv[1]).href) {
  await verifyReleaseArtifacts(process.argv[2], process.argv[3]);
  console.log('Both platform packages, checksums, and both signed update feeds are ready.');
}
