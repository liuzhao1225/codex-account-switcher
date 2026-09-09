## Codex Account Switcher for Windows — Preview

The Windows application is an additional native client in the same project as the macOS app.

- Download **Codex-Account-Switcher-windows-x64.exe** and run it directly. No separate .NET installation is needed.
- Requires Windows 10/11 x64, Codex Desktop and a Codex CLI supporting the account app-server methods.
- Register the account already signed in to Codex, then add other accounts through browser sign-in.
- Choose an account and confirm to close Desktop normally, switch and verify credentials, and reopen Desktop.
- Remove inactive accounts, view automatically refreshed weekly usage, optionally show 5-hour usage, and choose English or Simplified Chinese.
- Closing the window keeps the application in the system tray. Use the tray's Quit command to exit.

The Windows interface uses Microsoft Fluent controls and an original transparent tray logo that follows the taskbar theme. Both platforms use the same Swift account logic.

This preview checks for Windows updates and opens their download page; it does not replace the running EXE automatically. The EXE is **not Authenticode-signed**. Windows may show a publisher or SmartScreen warning. Check the supplied SHA-256 and the official repository before deciding whether to run it. Credentials are stored locally with a current-user-only Windows ACL. Keyring-only or `auto` credential storage is not supported.

Finish active Desktop tasks before switching. Existing CLI sessions are left running. Saved accounts remain under `%LOCALAPPDATA%\Codex Account Switcher`; the default active login is `%USERPROFILE%\.codex\auth.json` (or the process's `CODEX_HOME`). Desktop and Switcher must use the same Codex home.

See [Windows development and limitations](https://github.com/liuzhao1225/codex-account-switcher/blob/main/windows/README.md) in the repository. This is an independent project, not an official OpenAI application.
