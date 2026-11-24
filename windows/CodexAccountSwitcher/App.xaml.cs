using System;
using System.Drawing;
using System.IO;
using System.Linq;
using System.Reflection;
using System.Security.Cryptography;
using System.Text;
using System.Threading;
using System.Threading.Tasks;
using System.Windows;
using System.Windows.Media;
using System.Windows.Threading;
using CodexAccountSwitcher.Core;
using Microsoft.Win32;
using Forms = System.Windows.Forms;

namespace CodexAccountSwitcher;

public partial class App : Application
{
    public static Uri IconUri { get; } = new("pack://application:,,,/Codex-Account-Switcher-windows-x64;component/app.ico");
    private readonly bool startRuntime;
    public App() : this(true) { }
    public App(bool startRuntime) { this.startRuntime = startRuntime; }
    private Mutex? instance;
    private bool ownsMutex;
    private EventWaitHandle? activateWindow;
    private RegisteredWaitHandle? activationListener;
    private Forms.NotifyIcon? tray;
    private Forms.ContextMenuStrip? trayMenu;
    private Icon? icon;
    private string? trayIconVariant;
    private System.Drawing.Size trayIconSize;
    private int? trayIconPercent;
    private CoreClient? client;
    private NativeSettings? native;
    private MainWindow? window;
    private DispatcherTimer? updates;
    private bool exiting;
    private bool updatingRestart;

    protected override async void OnStartup(StartupEventArgs e)
    {
        base.OnStartup(e);
        if (!startRuntime) return;
        if (e.Args.Contains("--self-test")) { await SelfTestAsync(); return; }
        if (e.Args.Contains("--apply-update")) { await ApplyUpdateModeAsync(e.Args); return; }
        try {
            var dataPath = Environment.GetEnvironmentVariable("CODEX_SWITCHER_DATA_HOME")
                ?? Path.Combine(Environment.GetFolderPath(Environment.SpecialFolder.LocalApplicationData), "Codex Account Switcher");
            var updatesRoot = Path.Combine(dataPath, "updates");
            var cleanupStagingDir = ArgValue(e.Args, "--cleanup-update");
            var cleanupWaitPid = int.TryParse(ArgValue(e.Args, "--wait-pid"), out var parsedWaitPid) ? parsedWaitPid : (int?)null;

            var key = Convert.ToHexString(SHA256.HashData(Encoding.UTF8.GetBytes(Path.GetFullPath(dataPath).ToUpperInvariant())));
            instance = new Mutex(true, @"Local\CodexAccountSwitcher-" + key, out ownsMutex);
            if (!ownsMutex && cleanupStagingDir != null) {
                for (var attempt = 0; attempt < 20 && !ownsMutex; attempt++) {
                    await Task.Delay(200);
                    try { ownsMutex = instance.WaitOne(0); }
                    catch (AbandonedMutexException) { ownsMutex = true; }
                }
            }
            activateWindow = new EventWaitHandle(false, EventResetMode.AutoReset, @"Local\CodexAccountSwitcher-Activate-" + key);
            if (!ownsMutex) { activateWindow.Set(); Shutdown(); return; }

            var currentProcessPath = Environment.ProcessPath;
            if (!string.IsNullOrEmpty(currentProcessPath)) {
                _ = Task.Run(() => WindowsUpdater.CleanupAfterUpdate(currentProcessPath, updatesRoot, cleanupStagingDir, cleanupWaitPid));
            }

            ApplyTheme();
            client = new CoreClient(HostRuntime.Resolve(Assembly.GetExecutingAssembly()), dataPath);
            native = new NativeSettings();
            var launchedInBackground = e.Args.Contains("--background");
            var restartHooks = new UpdateRestartHooks(TryBeginUpdateRestart, CancelUpdateRestartReservation, CompleteUpdateRestartAsync);
            window = new MainWindow(client, native, restartHooks, dataPath, updatesRoot, launchedInBackground); MainWindow = window;
            activationListener = ThreadPool.RegisterWaitForSingleObject(activateWindow, (_, _) =>
                Dispatcher.BeginInvoke(new Action(() => { if (!exiting && window != null) { ApplyTheme(); window.OpenWindow(); } })),
                null, Timeout.Infinite, false);
            tray = new Forms.NotifyIcon { Text = "Codex Account Switcher" };
            RefreshTrayIcon();
            tray.Visible = true;
            SystemEvents.UserPreferenceChanged += OnUserPreferenceChanged;
            trayMenu = new Forms.ContextMenuStrip();
            var openItem = new Forms.ToolStripMenuItem("Codex Account Switcher");
            openItem.Click += (_, _) => { ApplyTheme(); window?.OpenWindow(); };
            var quitItem = new Forms.ToolStripMenuItem();
            quitItem.Click += (_, _) => _ = QuitAsync();
            trayMenu.Items.Add(openItem); trayMenu.Items.Add(new Forms.ToolStripSeparator()); trayMenu.Items.Add(quitItem);
            trayMenu.Opening += (_, _) => { quitItem.Text = client.State.Text("quit"); quitItem.Enabled = !(window?.IsBusy ?? false) && !(native?.IsInstalling ?? false); };
            tray.ContextMenuStrip = trayMenu;
            tray.MouseClick += (_, args) => {
                if (args.Button == Forms.MouseButtons.Left) { ApplyTheme(); window?.OpenWindow(); }
            };
            client.Changed += RefreshTray;
            client.LowUsage += ShowLowUsageNotification;
            await client.InitializeAsync();
            SystemEvents.PowerModeChanged += OnPowerModeChanged;
            if (!launchedInBackground) window.OpenWindow();
            updates = new DispatcherTimer { Interval = TimeSpan.FromHours(1) };
            updates.Tick += async (_, _) => { if (native.AutomaticallyCheckUpdates) await native.CheckUpdatesAsync(); };
            updates.Start();
            if (native.AutomaticallyCheckUpdates) _ = native.CheckUpdatesAsync();
        } catch (Exception ex) {
            MessageBox.Show(ex.Message, "Codex Account Switcher", MessageBoxButton.OK, MessageBoxImage.Error);
            await QuitAsync();
        }
    }

    private async Task ApplyUpdateModeAsync(string[] args)
    {
        try {
            var stagedExePath = Environment.ProcessPath;
            var target = ArgValue(args, "--target");
            var staging = ArgValue(args, "--staging");
            var pidText = ArgValue(args, "--parent-pid");
            var relaunchInBackground = args.Contains("--background");
            if (string.IsNullOrWhiteSpace(stagedExePath) || string.IsNullOrWhiteSpace(target)
                || string.IsNullOrWhiteSpace(staging) || !int.TryParse(pidText, out var parentPid)) {
                Shutdown(1);
                return;
            }
            await WindowsUpdater.ApplyUpdateAsync(stagedExePath, target, parentPid, staging, relaunchInBackground);
            Shutdown(0);
        } catch (Exception ex) {
            MessageBox.Show(ex.Message, "Codex Account Switcher", MessageBoxButton.OK, MessageBoxImage.Error);
            Shutdown(1);
        }
    }

    private static string? ArgValue(string[] args, string flag)
    {
        for (var i = 0; i < args.Length - 1; i++) {
            if (args[i] == flag) return args[i + 1];
        }
        return null;
    }

    private bool TryBeginUpdateRestart()
    {
        if (exiting || updatingRestart || window?.IsBusy == true) return false;
        updatingRestart = true;
        return true;
    }

    private void CancelUpdateRestartReservation() => updatingRestart = false;

    private async Task CompleteUpdateRestartAsync()
    {
        await ReleaseRuntimeAsync();
        Shutdown(0);
    }

    private async Task ReleaseRuntimeAsync()
    {
        exiting = true;
        updates?.Stop();
        updates = null;
        activationListener?.Unregister(null);
        activationListener = null;
        if (client != null) {
            client.Changed -= RefreshTray;
            client.LowUsage -= ShowLowUsageNotification;
            await client.DisposeAsync();
            client = null;
        }
        window?.CloseForExit();
        window = null;
        ReleaseNativeHandles();
    }

    private void ReleaseNativeHandles()
    {
        SystemEvents.PowerModeChanged -= OnPowerModeChanged;
        SystemEvents.UserPreferenceChanged -= OnUserPreferenceChanged;
        if (tray != null) { tray.Visible = false; tray.Dispose(); tray = null; }
        trayMenu?.Dispose(); trayMenu = null;
        icon?.Dispose(); icon = null;
        activateWindow?.Dispose(); activateWindow = null;
        if (ownsMutex) {
            ownsMutex = false;
            instance?.ReleaseMutex();
        }
        instance?.Dispose();
        instance = null;
    }

    private void ShowLowUsageNotification(string title, string message)
    {
        if (exiting || string.IsNullOrEmpty(message)) return;
        tray?.ShowBalloonTip(0, title, message, Forms.ToolTipIcon.Warning);
    }

    private void RefreshTray()
    {
        if (client == null || tray == null) return;
        var percent = ActiveTrayPercent();
        RefreshTrayIcon(percent);
        var active = client.State.Accounts.FirstOrDefault(row => row.Profile.Id == client.State.ActiveAccountID);
        var label = active == null ? "Codex Account Switcher" : active.Profile.DisplayName + (percent != null ? " · " + percent + "%" : "");
        tray.Text = label.Length > 63 ? label[..63] : label;
    }
    private int? ActiveTrayPercent() =>
        client?.State.Settings.ShowsMenuBarPercentage == true ? client.State.ActiveRemainingPercent : null;
    private void RefreshTrayIcon() => RefreshTrayIcon(ActiveTrayPercent());
    private void RefreshTrayIcon(int? percent)
    {
        if (tray == null) return;
        using var key = Registry.CurrentUser.OpenSubKey(@"Software\Microsoft\Windows\CurrentVersion\Themes\Personalize");
        // Taskbar appearance can differ from the application's light/dark theme.
        var variant = key?.GetValue("SystemUsesLightTheme") is int light && light != 0 ? "light" : "dark";
        var size = Forms.SystemInformation.SmallIconSize;
        if (trayIconVariant == variant && trayIconSize == size && trayIconPercent == percent) return;
        Icon replacement;
        if (percent is { } value) {
            replacement = TrayUsageIcon.Create(value, variant == "light", size);
        } else {
            var uri = new Uri($"pack://application:,,,/Codex-Account-Switcher-windows-x64;component/tray-{variant}.ico");
            using var resource = GetResourceStream(uri).Stream;
            using var original = new Icon(resource, size);
            replacement = (Icon)original.Clone();
        }
        tray.Icon = replacement;
        icon?.Dispose(); icon = replacement;
        trayIconVariant = variant; trayIconSize = size; trayIconPercent = percent;
    }
    private void OnUserPreferenceChanged(object sender, UserPreferenceChangedEventArgs e)
    {
        if (Dispatcher.HasShutdownStarted) return;
        Dispatcher.BeginInvoke(new Action(() => { if (!exiting) RefreshTrayIcon(); }));
    }
    private void OnPowerModeChanged(object sender, PowerModeChangedEventArgs e)
    {
        if (e.Mode != PowerModes.Resume || Dispatcher.HasShutdownStarted) return;
        Dispatcher.BeginInvoke(new Action(() => { if (!exiting) window?.RefreshUsage(); }));
    }
    private static bool IsDark() {
        using var key = Registry.CurrentUser.OpenSubKey(@"Software\Microsoft\Windows\CurrentVersion\Themes\Personalize");
        return key?.GetValue("AppsUseLightTheme") is int value && value == 0;
    }
    private void ApplyTheme() {
        var dark = IsDark();
        foreach (var pair in new[] { ("ListSurface", dark ? "#2D2D2D" : "#FFFFFF"), ("Surface", dark ? "#282828" : "#F5F5F5"), ("Ink", dark ? "#F5F5F5" : "#1A1A1A"),
            ("Muted", dark ? "#BEBEBE" : "#666666"), ("Line", dark ? "#444444" : "#DDDDDD"),
            ("Accent", dark ? "#60CDFF" : "#0067C0"), ("Selected", dark ? "#293F50" : "#E2EEFA"), ("Hover", dark ? "#15FFFFFF" : "#0C000000"),
            ("Warning", dark ? "#FFB74D" : "#B25900") })
        {
            var color = (System.Windows.Media.Color)System.Windows.Media.ColorConverter.ConvertFromString(pair.Item2);
            if (Resources[pair.Item1] is SolidColorBrush brush && !brush.IsFrozen) brush.Color = color;
            else Resources[pair.Item1] = new SolidColorBrush(color);
        }
    }
    private async Task QuitAsync() {
        if (exiting || updatingRestart || window?.IsBusy == true || native?.IsInstalling == true) return;
        await ReleaseRuntimeAsync();
        Shutdown();
    }
    private async Task SelfTestAsync() {
        var root = Path.Combine(Path.GetTempPath(), "switcher-package-check-" + Guid.NewGuid());
        var result = "PASS"; var exitCode = 0;
        try {
            Directory.CreateDirectory(Path.Combine(root, "active"));
            var host = HostRuntime.Resolve(Assembly.GetExecutingAssembly());
            await using var core = new CoreClient(host, Path.Combine(root, "data"), Path.Combine(root, "active"));
            await core.InitializeAsync().WaitAsync(TimeSpan.FromSeconds(30));
            await core.CommandAsync("fiveHour", value: true).WaitAsync(TimeSpan.FromSeconds(10));
            if (!File.Exists(Path.Combine(root, "data", "settings.json"))) throw new IOException("Shared settings were not persisted.");
            if (File.Exists(Path.Combine(root, "active", "auth.json"))) throw new IOException("Empty startup created an unexpected credential.");
            result += ": bundled .NET, extracted Swift runtime, shared host and isolated settings.";
        } catch (Exception ex) { result = "FAIL: " + ex; exitCode = 1; }
        finally { if (Directory.Exists(root)) SecureFiles.DeleteOwnedDirectory(Path.GetTempPath(), root); }
        if (Environment.GetEnvironmentVariable("CODEX_SWITCHER_SELF_TEST_RESULT") is { } output) File.WriteAllText(output, result);
        Shutdown(exitCode);
    }
    protected override void OnExit(ExitEventArgs e) {
        ReleaseNativeHandles();
        base.OnExit(e);
    }
}
