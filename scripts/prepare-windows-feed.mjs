import fs from 'node:fs/promises';
import { pathToFileURL } from 'node:url';
import {
  repository,
  windowsAssetName,
  readDefaultPublicKey,
  validateWindowsFeed,
} from './sign-windows-update.mjs';
import { compareSemverTags, fetchPublishedReleases } from './prepare-feeds.mjs';

export function latestWindowsRelease(releases) {
  return releases
    .filter(release => {
      return (
        !release.draft &&
        !release.prerelease &&
        /^v(0|[1-9]\d*)\.(0|[1-9]\d*)\.(0|[1-9]\d*)$/.test(release.tag_name) &&
        release.assets.some(asset => asset.name === 'windows-update.json') &&
        release.assets.some(asset => asset.name === windowsAssetName)
      );
    })
    .sort((a, b) => compareSemverTags(a.tag_name, b.tag_name))[0];
}

export async function prepareWindowsFeed(
  fetcher = fetch,
  output = 'site/updates/windows/latest.json',
  publicKeySpkiBase64 = null,
  releases = null,
) {
  const pubKey = publicKeySpkiBase64 ?? (await readDefaultPublicKey());
  const publishedReleases = releases ?? (await fetchPublishedReleases(fetcher));
  const release = latestWindowsRelease(publishedReleases);
  if (!release) return null;

  const response = await fetcher(
    `https://github.com/${repository}/releases/download/${release.tag_name}/windows-update.json`,
    { signal: AbortSignal.timeout(30000) },
  );
  if (!response.ok) throw new Error(`Windows feed download failed: ${response.status}`);
  const json = await response.text();
  validateWindowsFeed(json, release.tag_name, pubKey);
  await fs.mkdir(new URL('.', pathToFileURL(output)), { recursive: true });
  await fs.writeFile(output, json, 'utf8');
  return release.tag_name;
}

if (process.argv[1] && import.meta.url === pathToFileURL(process.argv[1]).href) {
  const tag = await prepareWindowsFeed();
  if (tag) console.log(`Windows update feed: ${tag}`);
  else console.log('Windows update feed: no published release with windows-update.json yet.');
}
