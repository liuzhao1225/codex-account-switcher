import fs from 'node:fs/promises';
import path from 'node:path';
import { createHash } from 'node:crypto';
import { pathToFileURL } from 'node:url';
import { validateMacFeed } from './prepare-macos-feed.mjs';

export async function verifyReleaseArtifacts(directory, tag) {
  if (!/^v(0|[1-9]\d*)\.(0|[1-9]\d*)\.(0|[1-9]\d*)$/.test(tag)) throw new Error('Expected a unified release tag.');
  for (const name of ['Codex-Account-Switcher-macos-arm64.dmg', 'Codex-Account-Switcher-windows-x64.exe']) {
    const data = await fs.readFile(path.join(directory, name));
    if (!data.length) throw new Error(`Empty package: ${name}`);
    const checksum = (await fs.readFile(path.join(directory, `${name}.sha256`), 'utf8')).trim();
    const [hash, file] = checksum.split(/\s+\*?/);
    if (file !== name || hash.toLowerCase() !== createHash('sha256').update(data).digest('hex')) {
      throw new Error(`Checksum mismatch: ${name}`);
    }
  }
  const xml = await fs.readFile(path.join(directory, 'appcast.xml'), 'utf8');
  validateMacFeed(xml, tag);
  if (!xml.includes(`<sparkle:shortVersionString>${tag.slice(1)}</sparkle:shortVersionString>`)) {
    throw new Error('The update feed version differs from the release tag.');
  }
}

if (process.argv[1] && import.meta.url === pathToFileURL(process.argv[1]).href) {
  await verifyReleaseArtifacts(process.argv[2], process.argv[3]);
  console.log('Both platform packages, checksums and the macOS feed are ready.');
}
