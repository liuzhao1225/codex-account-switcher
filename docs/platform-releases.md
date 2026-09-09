# Platform versions and releases

Both platforms belong to Codex Account Switcher. They share the Swift business core and have native platform interfaces, independent version numbers and release workflows.

| | macOS | Windows |
| --- | --- | --- |
| Code | `Sources/`, `Tests/` | `windows/` |
| Version source | Existing `CITATION.cff`, packaging default, Codex client version (validated together) | `windows/Directory.Build.props` |
| New release tag | `macos-v<major>.<minor>.<patch>` | `windows-v<major>.<minor>.<patch>` |
| Release title | `macOS · v<version>` | `Windows · v<version> Preview` during preview |
| Artifact | `Codex-Account-Switcher-macos-arm64.dmg` | `Codex-Account-Switcher-windows-x64.exe` |
| Release workflow | `.github/workflows/release.yml` | `.github/workflows/windows.yml` |

Do not rename, delete or recreate historical `v*` tags. The new Mac tag prefix is a future publishing convention; it does not change the version string displayed in the app. Windows uses `0.1.11` for its first preview release. macOS uses `0.1.11` for its shared-core compatibility release, tagged `macos-v0.1.11` after separate Mac testing. Their version sources and tags remain independent.

## Publishing procedure

1. Update the platform's version source(s), release notes and relevant documentation.
2. Run that platform's checks and packaging, and `node --test scripts/tests/*.test.mjs`.
3. Merge the prepared changes to `main`.
4. Create an annotated platform tag from the intended `origin/main` commit, and push that tag when ready to publish.

For example, after the source version has actually been changed to the corresponding value:

```sh
git tag -a macos-v0.1.11 -m "macOS 0.1.11" origin/main
git push origin macos-v0.1.11

# Independent release, only after Windows version and validation are ready:
git tag -a windows-v0.1.11 -m "Windows 0.1.11 Preview" origin/main
git push origin windows-v0.1.11
```

Never run both just to publish one platform. Tag push filtering is independent from branch-path filtering: a `windows-v*` tag starts the Windows pipeline even if that commit also changes Mac files. Ordinary branch pushes run tests but cannot enter either tag-only publishing job. Existing releases are not overwritten on rerun. Failed release jobs may be rerun against the same immutable tag.

Both pipelines require the tagged commit to equal current `origin/main` when validated. If `main` advances before a delayed run starts, release validation fails explicitly. Resolve this by preparing a new version/tag from current main; do not move a published tag.

Windows-only PRs/branch pushes run the Windows workflow. Changes to `SwitcherCore`, its tests, or the package manifest run both platforms' CI, including the same shared Swift tests. Release tags still trigger only their own platform's release pipeline. Existing macOS signing, notarization and Sparkle publishing stay in the macOS pipeline.

## Downloads and legacy Mac updates

GitHub has **one repository-wide Latest release**, not one Latest per platform. A platform-specific download must use an explicit release tag, or a release-list filter. Do not send Windows users to the repository-wide `latest/download` route.

During Windows preview:

- Mac releases retain `--latest`, preserving existing website links and the Sparkle feed used by installed Mac versions.
- Windows releases use `--prerelease --latest=false` and their own EXE asset. This is a preview/compatibility choice, not a difference in product ownership or tag naming.
- The Windows entry links to [Windows releases](https://github.com/liuzhao1225/codex-account-switcher/releases?q=windows-v). Before the first release, this list is intentionally empty; the source README supplies build instructions.
- Direct Windows download URLs have the form `https://github.com/liuzhao1225/codex-account-switcher/releases/download/windows-v0.1.11/Codex-Account-Switcher-windows-x64.exe` **only after that release exists**.

New Mac builds use `https://liuzhao1225.github.io/codex-account-switcher/updates/macos/appcast.xml`. The Pages build fetches releases with pagination, selects the highest published stable `macos-v*` version (also accepting historical Mac-only `v*` tags), requires a Mac DMG and appcast, and copies its signed feed unchanged. It rejects other-platform or unsigned enclosures. A successful Mac release workflow triggers a Pages deployment to refresh this feed; every ordinary site deployment regenerates it as well. Feed lookup or validation failure blocks deployment, preserving the previous published site. The new endpoint becomes available after the updated Pages workflow is deployed.

Existing Mac installations still request `/releases/latest/download/appcast.xml`. Keep Mac releases marked Latest so those clients can upgrade to a build using the dedicated Mac channel. Do not let Windows take over that compatibility endpoint. Both platform update selectors are independent of repository Latest; keeping Latest on Mac is solely for installed legacy clients and existing download links.

The Windows preview checks only `windows-v*` releases with a Windows EXE, including preview releases and excluding drafts, using pagination and its own installed version. It checks hourly when enabled and opens the release download page for updates. It does not replace its running EXE automatically and has no Authenticode signing. Do not describe the EXE as signed or as an installer. Adding a signed `Setup.exe` later is an independent packaging decision.
