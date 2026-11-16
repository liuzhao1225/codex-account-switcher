## 中文

- 修复 Windows 版 Codex Desktop 关闭窗口后仍留在托盘、导致账号切换超时的问题。确认切换后，结束对应安装的 Desktop 及其子进程，确认退出后再更换账号凭据并重新打开 Desktop。
- 保留独立启动的 CLI 和其他路径下的同名程序，并在切换确认中说明任务中断及未保存状态可能丢失。
- macOS 保持原有正常退出流程。自动使用 reset 的行为保持不变。

## English

- Fix Windows account-switch timeouts when Codex Desktop remains in the tray after its window closes. After confirmation, terminate the matching Desktop installation and its descendants, verify exit, then replace credentials and reopen Desktop.
- Preserve independently launched CLI sessions and unrelated same-name executables. The confirmation explains interrupted tasks and possible unsaved-state loss.
- Keep the macOS normal quit flow and automatic reset behavior unchanged.
