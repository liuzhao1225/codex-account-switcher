import fs from 'node:fs/promises';
import path from 'node:path';
import { createHash } from 'node:crypto';
import { pathToFileURL } from 'node:url';
import { validateMacFeed } from './prepare-macos-feed.mjs';
import { readDefaultPublicKey, validateWindowsFeed } from './sign-windows-update.mjs';

export async function verifyReleaseArtifacts(directory, tag, windowsPublicKeySpkiBase64 = null) {
  if (!/^v(0|[1-9]\d*)\.(0|[1-9]\d*)\.(0|[1-9]\d*)$/.test(tag)) throw new Error('Expected a unified release tag.');
  const hashes = {};
  const sizes = {};
  for (const name of ['Codex-Account-Switcher-macos-arm64.dmg', 'Codex-Account-Switcher-windows-x64.exe']) {
    const data = await fs.readFile(path.join(directory, name));
    if (!data.length) throw new Error(`Empty package: ${name}`);
    const checksum = (await fs.readFile(path.join(directory, `${name}.sha256`), 'utf8')).trim();
    const [hash, file] = checksum.split(/\s+\*?/);
    const actual = createHash('sha256').update(data).digest('hex');
    if (file !== name || hash.toLowerCase() !== actual) {
      throw new Error(`Checksum mismatch: ${name}`);
    }
    hashes[name] = actual;
    sizes[name] = data.length;
  }
  const xml = await fs.readFile(path.join(directory, 'appcast.xml'), 'utf8');
  validateMacFeed(xml, tag);
  if (!xml.includes(`<sparkle:shortVersionString>${tag.slice(1)}</sparkle:shortVersionString>`)) {
    throw new Error('The update feed version differs from the release tag.');
  }
  const winJson = await fs.readFile(path.join(directory, 'windows-update.json'), 'utf8');
  const pubKey = windowsPublicKeySpkiBase64 ?? (await readDefaultPublicKey());
  validateWindowsFeed(winJson, tag, pubKey, {
    size: sizes['Codex-Account-Switcher-windows-x64.exe'],
    sha256: hashes['Codex-Account-Switcher-windows-x64.exe'],
  });
}

if (process.argv[1] && import.meta.url === pathToFileURL(process.argv[1]).href) {
  await verifyReleaseArtifacts(process.argv[2], process.argv[3]);
  console.log('Both platform packages, checksums, and both signed update feeds are ready.');
}
