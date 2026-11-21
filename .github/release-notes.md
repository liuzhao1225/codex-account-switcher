## 中文

- **Windows 应用内自动更新**：Windows 版新增与 macOS 对齐的自动更新体验。点击「更新…」后直接后台流式下载安装包并展示进度（支持取消），通过内置公钥校验 ECDSA P-256 签名与 SHA-256 摘要，随后自动关闭并原子替换原程序且重启应用（若所在目录只读则回退至打开下载页）。
- **签名托管更新源**：GitHub Pages 同步发布经非对称签名的 `updates/windows/latest.json`，避免 GitHub API 匿名限流并保证更新完整性。

## English

- **Signed In-App Auto-Updates on Windows**: Windows now updates inside the app just like macOS. Clicking Update streams the release binary with live progress and cancellation support, verifies its ECDSA P-256 signature and SHA-256 digest using the embedded public key, and atomically replaces and relaunches the running executable (falling back to the release download page if the install folder is read-only).
- **Signed Update Feed**: GitHub Pages now serves the signed `updates/windows/latest.json` feed alongside macOS `appcast.xml`, avoiding anonymous GitHub API rate limits and ensuring update integrity.
