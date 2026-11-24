import fs from 'node:fs/promises';
import { pathToFileURL } from 'node:url';
import { repository } from './sign-windows-update.mjs';
import { compareSemverTags, fetchPublishedReleases } from './prepare-feeds.mjs';

const dmg = 'Codex-Account-Switcher-macos-arm64.dmg';

export function latestMacRelease(releases) {
  return releases.filter(release => {
    // Unified v* releases and historical macos-v* releases carry a signed Mac feed.
    return !release.draft && !release.prerelease &&
      /^(macos-)?v(0|[1-9]\d*)\.(0|[1-9]\d*)\.(0|[1-9]\d*)$/.test(release.tag_name) &&
      release.assets.some(asset => asset.name === 'appcast.xml') &&
      release.assets.some(asset => asset.name === dmg);
  }).sort((a, b) => {
    const versionOrder = compareSemverTags(a.tag_name, b.tag_name, /^(macos-)?v/);
    if (versionOrder !== 0) return versionOrder;
    return Number(b.tag_name.startsWith('v')) - Number(a.tag_name.startsWith('v'));
  })[0];
}

export function validateMacFeed(xml, tag) {
  const expected = `https://github.com/${repository}/releases/download/${tag}/${dmg}`;
  const enclosures = [...xml.matchAll(/<enclosure\b[^>]*>/g)].map(match => match[0]);
  if (!/^(macos-)?v(0|[1-9]\d*)\.(0|[1-9]\d*)\.(0|[1-9]\d*)$/.test(tag) || !xml.includes('<rss') || enclosures.length !== 1 ||
      !enclosures[0].includes(`url="${expected}"`) ||
      !/sparkle:edSignature="[^"]+"/.test(enclosures[0])) {
    throw new Error('The macOS feed must contain exactly its signed macOS DMG.');
  }
}

export async function prepareMacFeed(
  fetcher = fetch,
  output = 'site/updates/macos/appcast.xml',
  releases = null,
) {
  const publishedReleases = releases ?? (await fetchPublishedReleases(fetcher));
  const release = latestMacRelease(publishedReleases);
  if (!release) throw new Error('No published macOS release with a signed feed was found.');
  // Construct a platform-specific asset URL; never follow the repository-wide Latest alias.
  const response = await fetcher(`https://github.com/${repository}/releases/download/${release.tag_name}/appcast.xml`, {
    signal: AbortSignal.timeout(30000),
  });
  if (!response.ok) throw new Error(`macOS feed download failed: ${response.status}`);
  const xml = await response.text();
  validateMacFeed(xml, release.tag_name);
  await fs.mkdir(new URL('.', pathToFileURL(output)), { recursive: true });
  await fs.writeFile(output, xml); // Preserve the release's original signature and contents.
  return release.tag_name;
}

if (process.argv[1] && import.meta.url === pathToFileURL(process.argv[1]).href) {
  console.log(`macOS update feed: ${await prepareMacFeed()}`);
}
