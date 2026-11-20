## 中文

- **核心架构重构**：精简并统一 macOS 与 Windows 共享核心 `SwitcherCore` 及 `SwitcherHost` IPC（合并状态通知、按需传输多语言字典、移除第三方重置时间预测与冗余 npm 包装层）。
- **双端实时订阅状态**：macOS 与 Windows 统一接入实时订阅状态刷新与本地 `subscription-cache.json` 缓存，支持未激活账号在令牌过期时安全自动续期。
- **配额会话稳定性与隔离**：修复 `codex app-server` 管道关闭时的 CPU 空转问题；配额查询隔离使用本地文件凭据并禁用插件与远端同步（避免后台拉取大量插件缓存），空闲 90 秒自动回收；兼容 macOS `/Applications/ChatGPT.app`（`com.openai.codex`）及内置 `CodexCLI.app` 启动链路。
- **自动 Reset 日志瘦身**：将旧版 `reset-expiry-experiment.jsonl` 自动迁移并压缩为有界 `auto-reset.jsonl`，日常轮询不再写入冗余快照日志。

## English

- **Shared-Core Refactor**: Streamlined and unified the shared `SwitcherCore` and `SwitcherHost` IPC across macOS and Windows (batched snapshot updates, on-demand localization dictionary delivery, and removal of third-party reset forecasts and redundant npm installer layers).
- **Cross-Platform Live Subscriptions**: Unified live subscription refreshes and `subscription-cache.json` caching across macOS and Windows, with safe background token renewal for inactive accounts when tokens expire.
- **Quota Session Stability & Isolation**: Fixed CPU spin on `codex app-server` pipe EOF; forced file-backed credential isolation and disabled plugin/app sync during quota queries (preventing large background plugin downloads), with 90-second idle session expiry and full support for macOS `/Applications/ChatGPT.app` (`com.openai.codex`) and its bundled `CodexCLI.app` binary.
- **Bounded Auto-Reset Log**: Automatically migrates and compacts legacy `reset-expiry-experiment.jsonl` files into a bounded `auto-reset.jsonl`, eliminating routine poll log bloat.
