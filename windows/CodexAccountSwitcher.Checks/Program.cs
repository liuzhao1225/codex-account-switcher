using System.Security.AccessControl;
using CodexAccountSwitcher.Core;

if (args.FirstOrDefault() == "app-server") {
    await RpcFixture.RunAsync();
    return 0;
}

var host = args.FirstOrDefault() ?? Environment.GetEnvironmentVariable("CODEX_SWITCHER_HOST_PATH");
if (string.IsNullOrEmpty(host) || !File.Exists(host)) {
    Console.Error.WriteLine("Pass the built SwitcherHost.exe path to run native/shared-core integration checks.");
    return 1;
}
var root = Path.Combine(Path.GetTempPath(), "switcher-host-check-" + Guid.NewGuid());
var data = Path.Combine(root, "data");
var active = Path.Combine(root, "active");
Directory.CreateDirectory(active);
try {
    await using (var client = new CoreClient(Path.GetFullPath(host), data, active)) {
        await client.InitializeAsync("0.1.0").WaitAsync(TimeSpan.FromSeconds(30));
        await UntilAsync(() => client.State.Strings.ContainsKey("manage"));
        Require(client.State.Accounts.Length == 0, "Isolated startup should have no accounts.");
        Require(client.State.Providers != null && client.State.PendingSwitch == null,
            "Provider and confirmation fields must deserialize from the Swift snapshot.");
        await client.ProviderCommandAsync("openProviderEditor");
        await UntilAsync(() => client.State.ProviderEditor != null);
        var availablePort = new System.Net.Sockets.TcpListener(System.Net.IPAddress.Loopback, 0);
        availablePort.Start(); var port = ((System.Net.IPEndPoint)availablePort.LocalEndpoint).Port; availablePort.Stop();
        using (var endpoint = new System.Net.HttpListener()) {
            endpoint.Prefixes.Add($"http://127.0.0.1:{port}/"); endpoint.Start();
            var response = Task.Run(async () => {
                var request = await endpoint.GetContextAsync().WaitAsync(TimeSpan.FromSeconds(10));
                Require(request.Request.RawUrl == "/v1/models", "Model discovery uses the normalized API path.");
                Require(request.Request.Headers["Authorization"] == "Bearer synthetic-discovery-key", "The key reaches only the intended endpoint.");
                request.Response.ContentType = "application/json";
                var bytes = System.Text.Encoding.UTF8.GetBytes("{\"data\":[{\"id\":\"gpt-5-mini\"}]}");
                await request.Response.OutputStream.WriteAsync(bytes); request.Response.Close();
            });
            await client.ProviderCommandAsync("fetchProviderModels", new(Connection: new("Synthetic", $"http://127.0.0.1:{port}/v1", "responses", "synthetic-discovery-key")));
            await response;
            await UntilAsync(() => client.State.ProviderEditor?.Models.Length == 1);
        }
        await client.ProviderCommandAsync("searchProviderModels", new(Query: "g5m"));
        await client.ProviderCommandAsync("chooseProviderDefaultModel", new(ModelID: "gpt-5-mini"));
        await UntilAsync(() => client.State.ProviderEditor?.DefaultModelID == "gpt-5-mini");
        Require(client.State.ProviderEditor!.VisibleModelIDs.SequenceEqual(new[] { "gpt-5-mini" }), "Swift fuzzy search results cross the native transport.");
        Require(!System.Text.Json.JsonSerializer.Serialize(client.State).Contains("synthetic-discovery-key"), "Keys never appear in snapshots.");
        await client.ProviderCommandAsync("closeProviderEditor");
        await UntilAsync(() => client.State.ProviderEditor == null);
        await client.CommandAsync("language", language: "simplifiedChinese");
        await client.CommandAsync("fiveHour", value: true);
        await client.CommandAsync("percentage", value: false);
        await client.CommandAsync("providerSwitching", value: true);
        await UntilAsync(() => client.State.Settings.ShowsFiveHourUsage && !client.State.Settings.ShowsMenuBarPercentage
            && client.State.Settings.EnablesProviderSwitching);
        Require(client.State.Text("manage") == "管理账号", "The native UI must receive shared localization.");
        Require(File.Exists(Path.Combine(data, "settings.json")), "Settings should be saved by Swift.");
        Require(!File.Exists(Path.Combine(active, "auth.json")), "Settings must not create active credentials.");
        var acl = new FileInfo(Path.Combine(data, "settings.json")).GetAccessControl();
        Require(acl.AreAccessRulesProtected, "Shared-core settings must have a private Windows ACL.");
        Require(acl.GetAccessRules(true, true, typeof(System.Security.Principal.SecurityIdentifier)).Count == 1,
            "Shared-core files must grant only the current user access.");
    }
    await using (var second = new CoreClient(Path.GetFullPath(host), data, active)) {
        await second.InitializeAsync("0.1.0").WaitAsync(TimeSpan.FromSeconds(30));
        await UntilAsync(() => second.State.Settings.Language == "simplifiedChinese");
        Require(second.State.Settings.ShowsFiveHourUsage, "Settings must survive a host restart.");
        Require(second.State.Settings.EnablesProviderSwitching, "The provider opt-in must survive a host restart.");
    }
    Console.WriteLine("PASS: native transport, shared snapshots/localization, immediate settings, private ACL and restart persistence.");
    return 0;
} catch (Exception ex) { Console.Error.WriteLine(ex); return 1; }
finally { SecureFiles.DeleteOwnedDirectory(Path.GetTempPath(), root); }

static void Require(bool condition, string message) { if (!condition) throw new Exception(message); }
static async Task UntilAsync(Func<bool> condition) {
    for (var i = 0; i < 100; i++) { if (condition()) return; await Task.Delay(50); }
    throw new TimeoutException("The host did not publish the expected state.");
}
