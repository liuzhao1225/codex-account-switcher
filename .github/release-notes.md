- 修复桌面端刷新登录凭证后，当前账号仍使用旧凭证查询额度的问题。刷新前校验账号身份并同步凭证；同邮箱的个人与组织工作区按账号 ID 区分，旧账号从各自保存的凭证补齐 ID。
- 切换账号前取消并等待额度刷新，切换后重新刷新，避免旧响应覆盖新账号状态。
- Windows 每次关闭、重开 Codex 都重新查找安装路径，并使用应用标识识别 Store 更新后仍运行的旧版本进程。
- 添加账号期间重新打开窗口会回到登录管理页，便于查看状态或取消；重试登录会清除上次错误。

- Refresh the saved active credential before reading usage, after verifying its account identity. Keep same-email personal/workspace accounts distinct and fill missing legacy IDs from each profile's own credential.
- Cancel and drain usage refreshes before switching accounts, then refresh again after the handoff so old responses cannot overwrite current state.
- Rediscover Codex Desktop on every Windows close/open operation and match Store processes by application identity across package updates.
- Reopen a pending sign-in on the account management page, with cancellation available, and clear the previous error when starting sign-in again.

Adapted to the existing shared Swift core and native Windows adapters from @Herbertmt978's credential and Windows handoff changes and @rimom's sign-in navigation fix. Includes targeted credential/concurrency regression tests and an isolated Windows package-path update check. Windows Store account switching still requires real-device acceptance; the isolated checks do not establish a complete Store Desktop handoff.
