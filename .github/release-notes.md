## 中文

- 新增“到期前自动使用 reset”：开启后覆盖所有已保存账号，包括当前未激活账号，从到期前 10 分钟开始自动使用指定 reset。
- 接口返回“无需重置”时在到期前 5、1 分钟继续检查；成功、已使用或调用失败后停止该枚，重启后也不会重复消费。成功后刷新额度并核对 reset 状态。
- 保留真实请求、接口结果、原始错误和使用后额度的本地日志，原有试验记录保持不变。
- 新开关默认关闭，旧“仅日志”开关不会自动启用真实消费。应用须运行且电脑保持唤醒。开发和发布测试仅使用模拟接口。

## English

- Add opt-in automatic reset consumption for every saved account, including inactive accounts, starting 10 minutes before each credit expires.
- Check again at 5 and 1 minute only when the service reports nothing to reset. Stop after consumption, unavailable credit or call failure, including across restarts; refresh usage and verify consumption.
- Retain real attempt parameters, service outcomes, original errors and usage readback locally. Preserve historical dry-run records unchanged.
- The new setting defaults off; the old log-only setting does not enable consumption. Keep the app running and computer awake. Development and release tests use fake interfaces only.
