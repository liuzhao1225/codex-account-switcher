using System.Security.AccessControl;
using System.Text;
using System.Text.Json;
using CodexAccountSwitcher.Core;

if (args.FirstOrDefault() == "app-server") {
    await RpcFixture.RunAsync();
    return 0;
}

if (args.FirstOrDefault() == "desktop-close") {
    var fixture = args.ElementAtOrDefault(1);
    if (string.IsNullOrWhiteSpace(fixture) || !File.Exists(fixture)) {
        Console.Error.WriteLine("Pass the built ChatGPT.exe desktop fixture path to run the isolated close and update check.");
        return 1;
    }
    return await DesktopCloseChecks.RunAsync(fixture);
}

if (args.FirstOrDefault() == "windows-update") {
    return await UpdateChecks.RunAsync();
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
var previousCLI = Environment.GetEnvironmentVariable("CODEX_CLI_PATH");
try {
    await using (var client = new CoreClient(Path.GetFullPath(host), data, active)) {
        await client.InitializeAsync().WaitAsync(TimeSpan.FromSeconds(30));
        await UntilAsync(() => client.State.Strings?.ContainsKey("manage") == true);
        Require(client.State.Accounts.Length == 0, "Isolated startup should have no accounts.");
        Require(client.State.Settings.StatusBarUsageWindow == "fiveHour", "Five-hour usage should be the default tray window.");
        await client.CommandAsync("language", language: "simplifiedChinese");
        await client.CommandAsync("fiveHour", value: true);
        await client.CommandAsync("percentage", value: false);
        await client.CommandAsync("statusBarUsageWindow", language: "weekly");
        await UntilAsync(() => client.State.Settings.ShowsFiveHourUsage && !client.State.Settings.ShowsMenuBarPercentage
            && client.State.Settings.StatusBarUsageWindow == "weekly");
        Require(client.State.Text("manage") == "管理账号", "The native UI must receive shared localization.");
        Require(File.Exists(Path.Combine(data, "settings.json")), "Settings should be saved by Swift.");
        Require(!File.Exists(Path.Combine(active, "auth.json")), "Settings must not create active credentials.");
        var acl = new FileInfo(Path.Combine(data, "settings.json")).GetAccessControl();
        Require(acl.AreAccessRulesProtected, "Shared-core settings must have a private Windows ACL.");
        Require(acl.GetAccessRules(true, true, typeof(System.Security.Principal.SecurityIdentifier)).Count == 1,
            "Shared-core files must grant only the current user access.");
    }
    // The restarted host sees only synthetic profiles and uses this executable as its app-server.
    const string fixtureCreatedAt = "2026-01-01T00:00:00Z";
    var profiles = new[] {
        new { id = Guid.NewGuid(), displayName = "First fixture", accountID = "fixture-first", createdAt = fixtureCreatedAt },
        new { id = Guid.NewGuid(), displayName = "Second fixture", accountID = "fixture-second", createdAt = fixtureCreatedAt }
    };
    foreach (var profile in profiles) {
        var home = Path.Combine(data, "accounts", profile.id.ToString().ToUpperInvariant());
        SecureFiles.CreatePrivateDirectory(home);
        SecureFiles.AtomicWrite(Path.Combine(home, "auth.json"),
            JsonSerializer.SerializeToUtf8Bytes(new { tokens = new { account_id = profile.accountID } }));
        SecureFiles.AtomicWrite(Path.Combine(home, "fixture-mode"), Encoding.UTF8.GetBytes("normal"));
    }
    SecureFiles.AtomicWrite(Path.Combine(data, "accounts.json"), JsonSerializer.SerializeToUtf8Bytes(new { accounts = profiles }));
    var cliFixture = Path.Combine(AppContext.BaseDirectory, "CodexAccountSwitcher.Checks.exe");
    Require(File.Exists(cliFixture), "The isolated CLI fixture is missing.");
    Environment.SetEnvironmentVariable("CODEX_CLI_PATH", cliFixture);
    await using (var client = new CoreClient(Path.GetFullPath(host), data, active)) {
        await client.InitializeAsync().WaitAsync(TimeSpan.FromSeconds(30));
        await UntilAsync(() => client.State.Settings.Language == "simplifiedChinese" && client.State.Accounts.Length == 2);
        Require(client.State.Settings.ShowsFiveHourUsage, "Settings must survive a host restart.");
        Require(client.State.Settings.StatusBarUsageWindow == "weekly", "Tray usage selection must survive a host restart.");
        Require(!client.State.WeeklyUsageAutoStartEnabled, "Weekly auto-start should default to off.");
        await client.CommandAsync("weeklyUsageAutoStart", value: true);
        await UntilAsync(() => client.State.WeeklyUsageAutoStartEnabled);
    }
    await using (var client = new CoreClient(Path.GetFullPath(host), data, active)) {
        await client.InitializeAsync().WaitAsync(TimeSpan.FromSeconds(30));
        await UntilAsync(() => client.State.Accounts.Length == 2 && client.State.WeeklyUsageAutoStartEnabled);
        await client.CommandAsync("weeklyUsageAutoStart", value: false);
        await UntilAsync(() => !client.State.WeeklyUsageAutoStartEnabled);
    }
    Console.WriteLine("PASS: native transport, shared snapshots/localization, global weekly auto-start, private ACL and restart persistence.");
    return 0;
} catch (Exception ex) { Console.Error.WriteLine(ex); return 1; }
finally {
    Environment.SetEnvironmentVariable("CODEX_CLI_PATH", previousCLI);
    SecureFiles.DeleteOwnedDirectory(Path.GetTempPath(), root);
}

static void Require(bool condition, string message) { if (!condition) throw new Exception(message); }
static async Task UntilAsync(Func<bool> condition) {
    for (var i = 0; i < 100; i++) { if (condition()) return; await Task.Delay(50); }
    throw new TimeoutException("The host did not publish the expected state.");
}
