# Search visibility maintenance

Reviewed September 7, 2026. Preserve the existing page URLs, navigation and visual design when updating search-facing content.

## Page intent

| Page | English search intent | Chinese search intent |
| --- | --- | --- |
| Product homepage | Codex account switcher for Mac | Codex 账号切换器、Mac 多账号切换 |
| Multiple-account guide | How to switch Codex accounts on Mac | Mac 如何切换 Codex 多账号 |
| Account reference | What is a Codex account? Desktop and CLI behavior | Codex Account 是什么、账号与工作区的区别 |
| Project facts and creator | Codex Account Switcher author and official download | Codex Account Switcher 作者、官方仓库与下载 |

The homepage explains the product and platform. The guide documents the actual installation and switching actions. Keep each title and description specific to that page. Use ordinary language in the visible content and link answers to the relevant guide or source.

## Content and structured data

- Both languages reference one website entity (`/#website`) and one software entity (`/#software`) beneath the canonical project URL. Each localized page has its own URL and language.
- Homepage FAQ JSON-LD mirrors the visible questions and answers, including the local-history and existing-CLI-process boundaries. Update both representations together.
- Check the current release against [GitHub Releases](https://github.com/liuzhao1225/codex-account-switcher/releases/latest) and `CITATION.cff`. The verified v0.1.10 release was published September 5, 2026; its DMG is 3,188,599 bytes.
- Keep page modification dates, article metadata and sitemap `lastmod` aligned with real changes. Preserve original publication dates. [Google's sitemap guidance](https://developers.google.com/search/docs/crawling-indexing/sitemaps/build-sitemap) treats substantial content, link and structured-data changes as relevant updates.
- `llms.txt` is a concise bilingual project index. Its facts and links must remain aligned with the visible pages. [Google's AI search guidance](https://developers.google.com/search/docs/appearance/ai-features) prioritizes crawlable, useful text and matching structured data; it does not require a special AI file or schema.

## Crawl controls

The effective crawler policy is [the host-root robots.txt](https://liuzhao1225.github.io/robots.txt), maintained in the separate `liuzhao1225.github.io` repository. On September 7, it allowed crawling and listed this project's sitemap. The copy at `/codex-account-switcher/robots.txt` is informational. [The robots.txt location rules](https://developers.google.com/crawling/docs/robots-txt/create-robots-txt) require the host-root location.

The existing Search Console verification token, canonical URLs and reciprocal English/Chinese links are retained. [Google's localized-page guidance](https://developers.google.com/search/docs/specialty/international/localized-versions) requires the alternate pages to link back to one another.

## Verification

```bash
node scripts/check-site-geo.mjs
git diff --check
```

The check runs in PR/main CI and before Pages deployment. It verifies 16 canonical pages, unique titles and descriptions, reciprocal language links, local resources and fragments, FAQ content parity, release facts, and sitemap dates. Seven deliberately corrupted local fixtures were rejected during this update: canonical URL, language mapping, FAQ text, release version, modification date, fragment target and image path.

## Measure after publication

The September 7 public search check returned the product homepage, project facts, account guide and GitHub repository. This observation does not establish a ranking or traffic baseline.

After publishing, confirm the deployed HTML and sitemap, then check the Search Console sitemap and URL Inspection reports. Compare equivalent 28-day windows for the page-intent groups above using impressions, clicks, CTR and average position. Keep branded and unbranded queries separate. For AI answers, retain the exact query, date, product attribution, factual accuracy and cited URL; distinguish an answer citation from a search-process mention. Report observed changes without treating a local audit score or `llms.txt` as evidence of ranking gains.
