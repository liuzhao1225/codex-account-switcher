import { pathToFileURL } from 'node:url';
import { repository } from './sign-windows-update.mjs';

export function compareSemverTags(aTag, bTag, prefixPattern = /^v/) {
  const av = aTag.replace(prefixPattern, '').split('.').map(BigInt);
  const bv = bTag.replace(prefixPattern, '').split('.').map(BigInt);
  for (let i = 0; i < 3; i++) if (av[i] !== bv[i]) return av[i] > bv[i] ? -1 : 1;
  return 0;
}

export async function fetchPublishedReleases(fetcher = fetch) {
  const releases = [];
  for (let page = 1; ; page++) {
    const response = await fetcher(
      `https://api.github.com/repos/${repository}/releases?per_page=100&page=${page}`,
      {
        headers: {
          Accept: 'application/vnd.github+json',
          'User-Agent': 'CodexAccountSwitcher-UpdateFeeds',
          ...(process.env.GH_TOKEN ? { Authorization: `Bearer ${process.env.GH_TOKEN}` } : {}),
        },
        signal: AbortSignal.timeout(30000),
      },
    );
    if (!response.ok) throw new Error(`Release lookup failed: ${response.status}`);
    const batch = await response.json();
    releases.push(...batch);
    if (batch.length < 100) break;
  }
  return releases;
}

export async function prepareFeeds({
  fetcher = fetch,
  macOutput = 'site/updates/macos/appcast.xml',
  windowsOutput = 'site/updates/windows/latest.json',
  publicKeySpkiBase64 = null,
} = {}) {
  const releases = await fetchPublishedReleases(fetcher);
  const [{ prepareMacFeed }, { prepareWindowsFeed }] = await Promise.all([
    import('./prepare-macos-feed.mjs'),
    import('./prepare-windows-feed.mjs'),
  ]);
  const mac = await prepareMacFeed(fetcher, macOutput, releases);
  const windows = await prepareWindowsFeed(fetcher, windowsOutput, publicKeySpkiBase64, releases);
  return { mac, windows };
}

if (process.argv[1] && import.meta.url === pathToFileURL(process.argv[1]).href) {
  prepareFeeds()
    .then(({ mac, windows }) => {
      console.log(`macOS update feed: ${mac}`);
      if (windows) console.log(`Windows update feed: ${windows}`);
      else console.log('Windows update feed: no published release with windows-update.json yet.');
    })
    .catch(error => {
      console.error(error);
      process.exitCode = 1;
    });
}
