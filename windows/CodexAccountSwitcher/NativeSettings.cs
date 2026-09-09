using System;
using System.Diagnostics;
using System.Linq;
using System.Net.Http;
using System.Text.Json;
using System.Text.RegularExpressions;
using System.Threading.Tasks;
using Microsoft.Win32;

namespace CodexAccountSwitcher;

public sealed class NativeSettings
{
    private const string Key = @"Software\CodexAccountSwitcher";
    private const string Run = @"Software\Microsoft\Windows\CurrentVersion\Run";
    public string Version => typeof(NativeSettings).Assembly.GetName().Version?.ToString(3) ?? "0.1.12";
    public bool LaunchAtLogin {
        get { using var key = Registry.CurrentUser.OpenSubKey(Run); return key?.GetValue("CodexAccountSwitcher") is string; }
        set { using var key = Registry.CurrentUser.CreateSubKey(Run);
            if (value) key.SetValue("CodexAccountSwitcher", "\"" + Environment.ProcessPath + "\" --background");
            else key.DeleteValue("CodexAccountSwitcher", false); }
    }
    public bool AutomaticallyCheckUpdates {
        get { using var key = Registry.CurrentUser.OpenSubKey(Key); return key?.GetValue("AutomaticallyCheckUpdates") is not int number || number != 0; }
        set { using var key = Registry.CurrentUser.CreateSubKey(Key); key.SetValue("AutomaticallyCheckUpdates", value ? 1 : 0); }
    }
    public Uri? UpdatePage { get; private set; }
    public bool IsChecking { get; private set; }
    public string? UpdateError { get; private set; }
    public event Action? Changed;
    public async Task CheckUpdatesAsync()
    {
        if (IsChecking) return;
        IsChecking = true; UpdateError = null; Changed?.Invoke();
        try {
            using var http = new HttpClient { Timeout = TimeSpan.FromSeconds(15) };
            http.DefaultRequestHeaders.UserAgent.ParseAdd("CodexAccountSwitcher/" + Version);
            Version? latest = null;
            for (var page = 1; ; page++) {
                using var document = JsonDocument.Parse(await http.GetStringAsync(
                    "https://api.github.com/repos/liuzhao1225/codex-account-switcher/releases?per_page=100&page=" + page));
                var candidate = LatestWindowsVersion(document.RootElement);
                if (candidate != null && (latest == null || candidate > latest)) latest = candidate;
                if (document.RootElement.GetArrayLength() < 100) break;
            }
            UpdatePage = latest != null && latest > new Version(Version)
                ? new Uri("https://github.com/liuzhao1225/codex-account-switcher/releases/tag/v" + latest.ToString(3)) : null;
        } catch (Exception) { UpdateError = "update_check_failed"; }
        finally { IsChecking = false; Changed?.Invoke(); }
    }
    // Stable unified releases must include a Windows executable.
    public static Version? LatestWindowsVersion(JsonElement releases) => releases.EnumerateArray()
        .Where(release => !release.GetProperty("draft").GetBoolean() &&
            (!release.TryGetProperty("prerelease", out var preview) || !preview.GetBoolean()))
        .Where(release => release.GetProperty("assets").EnumerateArray().Any(asset =>
            asset.GetProperty("name").GetString() == "Codex-Account-Switcher-windows-x64.exe"))
        .Select(release => release.GetProperty("tag_name").GetString())
        .Where(tag => tag != null && Regex.IsMatch(tag, @"\Av(0|[1-9][0-9]*)\.(0|[1-9][0-9]*)\.(0|[1-9][0-9]*)\z"))
        .Select(tag => System.Version.TryParse(tag![1..], out var version) ? version : null)
        .Where(version => version != null).OrderDescending().FirstOrDefault();
    public void OpenUpdate() { if (UpdatePage != null) Process.Start(new ProcessStartInfo(UpdatePage.AbsoluteUri) { UseShellExecute = true })?.Dispose(); }
}
