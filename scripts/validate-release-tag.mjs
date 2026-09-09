import fs from 'node:fs';
import path from 'node:path';
import { fileURLToPath } from 'node:url';

export function validateReleaseTag(tag, root = path.resolve(path.dirname(fileURLToPath(import.meta.url)), '..')) {
  const match = tag.match(/^v(0|[1-9]\d*)\.(0|[1-9]\d*)\.(0|[1-9]\d*)$/);
  if (!match) throw new Error(`Expected v<major>.<minor>.<patch>; got ${tag}.`);
  const version = match.slice(1).join('.');
  const read = relative => fs.readFileSync(path.join(root, relative), 'utf8');
  const versions = [
    read('CITATION.cff').match(/^version:\s*(\S+)/m)?.[1],
    read('scripts/package-local-app.sh').match(/APP_VERSION=\$\{RELEASE_VERSION:-([^}]+)\}/)?.[1],
    read('Sources/SwitcherCore/CodexClient.swift').match(/clientVersion: String = "([^"]+)"/)?.[1],
    read('windows/Directory.Build.props').match(/<Version>([^<]+)<\/Version>/)?.[1],
  ];
  if (versions.some(v => v !== version)) throw new Error(`Tag ${tag} disagrees with unified version sources: ${versions.join(', ')}.`);
  return version;
}

if (process.argv[1] && path.resolve(process.argv[1]) === fileURLToPath(import.meta.url)) {
  try { console.log(validateReleaseTag(process.argv[2])); }
  catch (error) { console.error(error.message); process.exitCode = 1; }
}
