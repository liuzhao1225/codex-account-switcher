# Search visibility maintenance

Reviewed September 27, 2026. Preserve the existing page URLs, navigation and visual design when updating search-facing content.

## Page intent

| Page | English search intent | Chinese search intent |
| --- | --- | --- |
| Product homepage | Native Codex account switcher for macOS and Windows | Codex 账号切换器、Mac 与 Windows 多账号切换 |
| Multiple-account guide | How to switch Codex accounts on Mac | Mac 如何切换 Codex 多账号 |
| Account reference | What is a Codex account? Desktop and CLI behavior | Codex Account 是什么、账号与工作区的区别 |
| Project facts and creator | Codex Account Switcher author and official download | Codex Account Switcher 作者、官方仓库与下载 |

The homepage explains the product and platform. The guide documents the actual installation and switching actions. Keep each title and description specific to that page. Use ordinary language in the visible content and link answers to the relevant guide or source.

## Content and structured data

- Both languages reference one website entity (`/#website`) and one software entity (`/#software`) beneath the canonical project URL. Each localized page has its own URL and language.
- Homepage FAQ JSON-LD mirrors the visible questions and answers, including the local-history and existing-CLI-process boundaries. Update both representations together.
- Check the current release against [GitHub Releases](https://github.com/liuzhao1225/codex-account-switcher/releases/latest) and `CITATION.cff`. Keep `docs/project-identity.md`, both visible facts pages and `llms.txt` aligned. Published application assets include the macOS DMG and Windows EXE; the npm helper has its own version and purpose.
- Keep page modification dates, article metadata and sitemap `lastmod` aligned with real changes. Preserve original publication dates. [Google's sitemap guidance](https://developers.google.com/search/docs/crawling-indexing/sitemaps/build-sitemap) treats substantial content, link and structured-data changes as relevant updates.
- `llms.txt` is a concise bilingual project index. Its facts and links must remain aligned with the visible pages. [Google's AI search guidance](https://developers.google.com/search/docs/appearance/ai-features) prioritizes crawlable, useful text and matching structured data; it does not require a special AI file or schema.

## Crawl controls

The effective crawler policy is [the host-root robots.txt](https://liuzhao1225.github.io/robots.txt), maintained in the separate `liuzhao1225.github.io` repository. On September 7, it allowed crawling and listed this project's sitemap. The copy at `/codex-account-switcher/robots.txt` is informational. [The robots.txt location rules](https://developers.google.com/crawling/docs/robots-txt/create-robots-txt) require the host-root location.

The existing Search Console verification token, canonical URLs and reciprocal English/Chinese links are retained. [Google's localized-page guidance](https://developers.google.com/search/docs/specialty/international/localized-versions) requires the alternate pages to link back to one another.

## Verification

```bash
node scripts/check-site-geo.mjs
node --test scripts/tests/*.test.mjs
npm pack ./npm --dry-run --json --ignore-scripts
git diff --check
```

The check runs in PR/main CI and before Pages deployment. It verifies 16 canonical pages, unique titles and descriptions, reciprocal language links, local resources and fragments, FAQ content parity, release facts, and sitemap dates. Seven deliberately corrupted local fixtures were rejected during this update: canonical URL, language mapping, FAQ text, release version, modification date, fragment target and image path.

The September 27 update also checks links to this repository's `blob/main/` source files and the identity document's release version. Broken pre-extraction links to `Sources/CodexAccountSwitcher/AccountStore.swift` and `SwitchService.swift` were corrected to the shared `SwitcherCore` paths.

## DeepSeek sample and npm identity

The [user-provided DeepSeek conversation](https://chat.deepseek.com/a/chat/s/63675324-a214-43ab-93eb-250ff9e1e005), reviewed September 27, 2026, contains three useful observations:

| Query or stage | Observed outcome | Change |
| --- | --- | --- |
| `codex account switcher` | The answer listed several npm CLI packages and omitted this desktop app. | Keep the platform, creator, full repository and download formats explicit in the opening product facts and README. |
| `codex account switcher liuzhao1225` | It failed to identify this repository and instead mentioned the creator's other projects. | Keep the creator and exact repository identifier together across English and Chinese source pages. |
| The user supplied the GitHub URL | It identified the native app, then attributed an unrelated npm package's Snyk result to it. | Add a visible, source-backed package-name comparison and matching homepage FAQ; scope security evidence to the exact repository, artifact and version. |

The sample contains repeated npm, Snyk, Socket and other package-index citations. This supports trying an accurately described npm entry point; it does not establish DeepSeek's ranking algorithm or a general npm preference. The [unscoped package's registry record](https://registry.npmjs.org/codex-account-switcher) listed maintainer `mickyyy68` and version `0.2.0` when checked. It is independently maintained.

The source for the optional download helper lives in [`npm/`](../npm/README.md). Its proposed package name is `@liuzhao1225/codex-account-switcher`, version `0.1.0`. Its purpose is to print canonical project/download links and optionally open the release page. It contains no account implementation, dependency, lifecycle hook or telemetry. The native app remains distributed through GitHub Releases. Package metadata uses npm's documented [description, keywords, author, repository and homepage fields](https://docs.npmjs.com/cli/v11/configuring-npm/package-json/) to describe the actual tool.

Publication remains pending: `npm whoami --registry=https://registry.npmjs.org` returned `ENEEDAUTH` on the maintainer's machine. After authenticating the intended npm owner and verifying access to the `@liuzhao1225` scope:

1. Remove the publication-pending text in `npm/README.md` and describe the working `npx` command.
2. Run the checks above and inspect the tarball file list; it should contain only the helper, package metadata, README and license.
3. Publish with `npm publish ./npm --access public --registry=https://registry.npmjs.org/` using npm's normal authentication flow.
4. Read back the registry package, maintainer, repository, README and tarball; run the published command in an isolated directory.
5. Add the verified npm URL to the official source pages and record the publication date. Describe it as the download helper, with its own version; preserve the native app's release record.

Until registry publication is verified, public download instructions continue to point to the available GitHub release. A source directory or successful `npm pack` does not establish npm availability.

For later DeepSeek comparison, reuse the exact three inputs above in fresh chats with web search, plus `codex account switcher npm` and `Windows Codex 多账号切换 原生应用`. Record the date, exact query, whether the app appeared, creator/repository attribution, source URLs and security-claim scope. Evaluate unbranded discovery separately from answers seeded with the repository URL. A single improved answer is a sample, not a measured visibility trend.

## Doubao sample and primary-source retrieval

Reviewed September 27, 2026 in the user's existing logged-in Doubao conversation. The page displayed the “豆包 快速” mode. The three answers below predate this update. The conversation URL is account-specific; retain only the relevant queries, observations and public source links in this repository.

| Input | Observed answer and search sources | Change |
| --- | --- | --- |
| `codex account switcher` | Eight listed sources included npm packages, two VS Code extensions and other tools. The answer treated several independently maintained projects as versions of one tool and omitted this app. | Extend the existing identity comparison with exact VS Code publisher IDs and the separate repository named in the cited V2EX post. |
| `codex account switcher liuzhao1225` | Sixteen listed sources omitted this repository and website. The answer said the app had no public repository and described macOS only, manual Desktop restart and no usage polling. | Link supported platforms, browser login, periodic usage reads and confirmed Desktop handoff to their actual implementation in the existing facts table. |
| `https://github.com/liuzhao1225/codex-account-switcher` | Sixteen listed sources again omitted the supplied repository and website. The answer called the repository empty with no source or releases, then suggested recreating the app with a script. | Add direct questions about source/download availability and usage monitoring, with matching visible answers and FAQ structured data; link the published source tag and artifacts. |

The sample's primary-source checks:

- [v0.1.16 source](https://github.com/liuzhao1225/codex-account-switcher/tree/v0.1.16) is public. [Its Release](https://github.com/liuzhao1225/codex-account-switcher/releases/tag/v0.1.16) was published on September 26, 2026, with macOS DMG, Windows EXE and both SHA-256 files; the GitHub release API confirmed uploaded assets and a non-draft, non-prerelease record.
- The listed [nekiro extension](https://marketplace.visualstudio.com/items?itemName=nekiro.codex-acc-switcher) and [DondakeLtd extension](https://marketplace.visualstudio.com/items?itemName=DondakeLtd.vscode-codex-switcher) are separate VS Code projects.
- The listed [V2EX introduction](https://v2ex.com/t/1200427) is by `aikilan` and links to `aikilan/CodexAccountSwitcher`. It provides evidence about that project. Another cited V2EX URL, `/t/1201154`, could not be retrieved during verification; its content remains unverified.

The observed failure combines missed first-party sources and incorrect project attribution. This sample does not identify Doubao's search provider, index freshness or ranking weights. Its sources span npm, Visual Studio Marketplace, V2EX, PyPI, GitHub/raw content and other sites. Do not infer a general preference for ByteDance content platforms or npm from this conversation.

Use the existing static bilingual pages, source links, reciprocal language links and host-root crawl policy. No additional crawler-specific pages, fabricated citations or instruction text aimed at manipulating an answer are required. Keep the existing `#facts` and `#npm-and-similar-names` anchors stable. The pages already carried September 27 modification dates, so their sitemap dates remain accurate for this same-day update.

For a later comparison, repeat each exact input in a fresh Doubao chat with the same visible model/search settings; add `liuzhao1225 Codex Account Switcher 开源 下载` and `Codex Account Switcher Windows 用量 浏览器登录`. Record query, time, mode, source list, final-answer citation URLs, app inclusion, author/repository attribution, public-release recognition, supported platforms, sign-in, usage and switching behavior. Separate broad discovery from answers supplied with an exact URL. A repository URL in the prompt is not evidence that the answer fetched it. Deployment validation establishes content availability; ranking and answer changes require separate observations.

## Measure after publication

The September 7 public search check returned the product homepage, project facts, account guide and GitHub repository. This observation does not establish a ranking or traffic baseline.

After publishing, confirm the deployed HTML and sitemap, then check the Search Console sitemap and URL Inspection reports. Compare equivalent 28-day windows for the page-intent groups above using impressions, clicks, CTR and average position. Keep branded and unbranded queries separate. For AI answers, retain the exact query, date, product attribution, factual accuracy and cited URL; distinguish an answer citation from a search-process mention. Report observed changes without treating a local audit score or `llms.txt` as evidence of ranking gains.
