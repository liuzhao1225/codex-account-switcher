using System.Text;
using System.Text.Json;

// Used by transport and integration checks with a temporary CODEX_HOME.
internal static class RpcFixture
{
    public static async Task RunAsync()
    {
        using var input = new StreamReader(Console.OpenStandardInput(), Encoding.UTF8);
        var home = Environment.GetEnvironmentVariable("CODEX_HOME") ?? throw new Exception("Missing fixture home");
        var launchesPath = Path.Combine(home, "launches");
        if (File.Exists(launchesPath)) {
            foreach (var previous in await File.ReadAllLinesAsync(launchesPath)) {
                if (!int.TryParse(previous, out var pid)) continue;
                try {
                    using var other = System.Diagnostics.Process.GetProcessById(pid);
                    if (!other.HasExited) await File.WriteAllTextAsync(Path.Combine(home, "overlap"), "yes");
                } catch (ArgumentException) { }
            }
        }
        await File.AppendAllTextAsync(launchesPath, Environment.ProcessId + "\n");
        var scenario = (await File.ReadAllTextAsync(Path.Combine(home, "fixture-mode"))).Trim();
        var threadStarted = false;
        while (await input.ReadLineAsync() is { } line) {
            using var document = JsonDocument.Parse(line); var message = document.RootElement;
            if (!message.TryGetProperty("id", out var id)) continue;
            var method = message.GetProperty("method").GetString();
            await File.AppendAllTextAsync(Path.Combine(home, "requests"), method + "\n");
            if ((scenario == "hold-initialize" && method == "initialize") ||
                (scenario == "hold-quota" && method == "account/rateLimits/read") ||
                (scenario == "hold-identity" && method == "account/read")) {
                while (!File.Exists(Path.Combine(home, "release"))) await Task.Delay(10);
            }
            if (scenario == "timeout" || (scenario == "quota-timeout" && method == "account/rateLimits/read")) continue;
            if (scenario == "exit-once" && method == "account/rateLimits/read" && !File.Exists(Path.Combine(home, "exited"))) {
                await File.WriteAllTextAsync(Path.Combine(home, "exited"), "yes");
                return;
            }
            var reportsFullAllowance = scenario.StartsWith("turn-", StringComparison.Ordinal)
                && (scenario != "turn-nonfull" || !threadStarted);
            object result = method switch {
                "account/read" when scenario == "turn-api-key" => new { account = new { type = "apiKey" } },
                "account/read" => new { account = new { type = "chatgpt", accountId = "fixture", email = "fixture@example.test" } },
                "account/rateLimits/read" when reportsFullAllowance => new { rateLimits = new {
                    ordinaryUsageAllowed = true,
                    primary = new { usedPercent = 0, windowDurationMins = 10080, resetsAt = 2_000_000_000 } } },
                "account/rateLimits/read" => new { rateLimitResetCredits = new { availableCount = 2 }, rateLimits = new {
                    ordinaryUsageAllowed = true,
                    primary = new { usedPercent = 33, windowDurationMins = 300, resetsAt = 2_000_000_000 },
                    secondary = new { usedPercent = 58, windowDurationMins = 10080, resetsAt = 2_000_000_000 } } },
                "account/rateLimitResetCredit/consume" => new { outcome = "reset" },
                "account/login/start" => new { authUrl = "https://example.test/sign-in" },
                _ => new { }
            };
            if (method == "thread/start") {
                var parameters = message.GetProperty("params");
                if (parameters.GetProperty("ephemeral").GetBoolean() && parameters.GetProperty("sandbox").GetString() == "read-only") {
                    threadStarted = true;
                    result = new { thread = new { id = "quota-thread" } };
                }
            } else if (method == "turn/start") {
                var parameters = message.GetProperty("params");
                if (parameters.GetProperty("threadId").GetString() == "quota-thread"
                    && parameters.GetProperty("input")[0].GetProperty("text").GetString() == "只回复 OK"
                    && parameters.GetProperty("serviceTier").GetString() == "default") {
                    result = new { turn = new { id = "quota-turn", status = "inProgress" } };
                    await EmitTurnCompletionAsync("other-thread", "quota-turn", "failed");
                    await EmitTurnCompletionAsync("quota-thread", "other-turn", "failed");
                    if (scenario != "turn-timeout") {
                        await EmitTurnCompletionAsync("quota-thread", "quota-turn", scenario == "turn-failed" ? "failed" : "completed");
                    }
                }
            }
            if (method == "account/login/start" && scenario == "login") {
                await Console.Out.WriteLineAsync(JsonSerializer.Serialize(new { method = "account/login/completed", @params = new { success = true } }));
            }
            await Console.Out.WriteLineAsync(JsonSerializer.Serialize(new { id = id.GetInt32(), result }));
            await Console.Out.FlushAsync();
        }
    }

    private static Task EmitTurnCompletionAsync(string threadId, string turnId, string status) =>
        Console.Out.WriteLineAsync(JsonSerializer.Serialize(new {
            method = "turn/completed",
            @params = new { threadId, turn = new { id = turnId, status } }
        }));
}
