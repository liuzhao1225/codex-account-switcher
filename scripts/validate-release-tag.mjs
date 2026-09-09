import fs from 'node:fs';
import path from 'node:path';
import { fileURLToPath } from 'node:url';

export function validateReleaseTag(platform, tag, root = path.resolve(path.dirname(fileURLToPath(import.meta.url)), '..')) {
  if (!['macos', 'windows'].includes(platform)) throw new Error('Unknown release platform.');
  const match = tag.match(new RegExp(`^${platform}-v(0|[1-9]\\d*)\\.(0|[1-9]\\d*)\\.(0|[1-9]\\d*)$`));
  if (!match) throw new Error(`Expected ${platform}-v<major>.<minor>.<patch>; got ${tag}.`);
  const version = match.slice(1).join('.');
  const read = relative => fs.readFileSync(path.join(root, relative), 'utf8');
  const versions = platform === 'windows'
    ? [read('windows/Directory.Build.props').match(/<Version>([^<]+)<\/Version>/)?.[1]]
    : [read('CITATION.cff').match(/^version:\s*(\S+)/m)?.[1],
      read('scripts/package-local-app.sh').match(/APP_VERSION=\$\{RELEASE_VERSION:-([^}]+)\}/)?.[1],
      read('Sources/SwitcherCore/CodexClient.swift').match(/clientVersion: String = "([^"]+)"/)?.[1]];
  if (versions.some(v => v !== version)) throw new Error(`Tag ${tag} disagrees with ${platform} version source(s): ${versions.join(', ')}.`);
  return version;
}

if (process.argv[1] && path.resolve(process.argv[1]) === fileURLToPath(import.meta.url)) {
  try { console.log(validateReleaseTag(process.argv[2], process.argv[3])); }
  catch (error) { console.error(error.message); process.exitCode = 1; }
}
