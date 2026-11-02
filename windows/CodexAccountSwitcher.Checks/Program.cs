using System.Security.AccessControl;
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
        await client.InitializeAsync().WaitAsync(TimeSpan.FromSeconds(30));
        await UntilAsync(() => client.State.Strings.ContainsKey("manage"));
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
    await using (var second = new CoreClient(Path.GetFullPath(host), data, active)) {
        await second.InitializeAsync().WaitAsync(TimeSpan.FromSeconds(30));
        await UntilAsync(() => second.State.Settings.Language == "simplifiedChinese");
        Require(second.State.Settings.ShowsFiveHourUsage, "Settings must survive a host restart.");
        Require(second.State.Settings.StatusBarUsageWindow == "weekly", "Tray usage selection must survive a host restart.");
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
