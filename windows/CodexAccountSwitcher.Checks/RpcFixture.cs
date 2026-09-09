using System.Text.Json;

// Executed only by the shared Swift tests with a temporary CODEX_HOME.
internal static class RpcFixture
{
    public static async Task RunAsync()
    {
        var home = Environment.GetEnvironmentVariable("CODEX_HOME") ?? throw new Exception("Missing fixture home");
        var scenario = await File.ReadAllTextAsync(Path.Combine(home, "fixture-mode"));
        while (await Console.In.ReadLineAsync() is { } line) {
            using var document = JsonDocument.Parse(line); var message = document.RootElement;
            if (!message.TryGetProperty("id", out var id)) continue;
            var method = message.GetProperty("method").GetString();
            if (scenario == "timeout") continue;
            object result = method switch {
                "account/read" => new { account = new { accountId = "fixture", email = "fixture@example.test" } },
                "account/rateLimits/read" => new { rateLimits = new {
                    primary = new { usedPercent = 33, windowDurationMins = 300, resetsAt = 2_000_000_000 },
                    secondary = new { usedPercent = 58, windowDurationMins = 10080, resetsAt = 2_000_000_000 } } },
                "account/login/start" => new { authUrl = "https://example.test/sign-in" },
                _ => new { }
            };
            if (method == "account/login/start" && scenario == "login") {
                await Console.Out.WriteLineAsync(JsonSerializer.Serialize(new { method = "account/login/completed", @params = new { success = true } }));
            }
            await Console.Out.WriteLineAsync(JsonSerializer.Serialize(new { id = id.GetInt32(), result }));
            await Console.Out.FlushAsync();
        }
    }
}
