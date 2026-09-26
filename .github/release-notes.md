- 修复 macOS 在 ChatGPT / Codex 桌面端更新后，添加账号、切换账号或刷新额度时报 `The Codex executable could not be found` 的问题（#13、#14）。
- 自动识别桌面端内置 CLI 的新旧安装位置；系统命令缺失或软链接失效时，无需手动配置软链接。保留显式 `CODEX_CLI_PATH` 和系统 PATH 的优先级。

- Fix `The Codex executable could not be found` during Add Account, account switching, or usage refresh after a ChatGPT / Codex desktop update on macOS (#13, #14).
- Discover both current and legacy bundled CLI locations when the system command is missing or its symlink is broken. Preserve explicit `CODEX_CLI_PATH` and system PATH precedence.

Thanks to @lancer1256 for the bundled CLI discovery contribution in #13.
