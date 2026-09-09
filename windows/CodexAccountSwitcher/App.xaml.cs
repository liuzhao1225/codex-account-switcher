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
    private CoreClient? client;
    private MainWindow? window;
    private DispatcherTimer? updates;
    private bool exiting;

    protected override async void OnStartup(StartupEventArgs e)
    {
        base.OnStartup(e);
        if (!startRuntime) return;
        if (e.Args.Contains("--self-test")) { await SelfTestAsync(); return; }
        try {
            var dataPath = Environment.GetEnvironmentVariable("CODEX_SWITCHER_DATA_HOME")
                ?? Path.Combine(Environment.GetFolderPath(Environment.SpecialFolder.LocalApplicationData), "Codex Account Switcher");
            var key = Convert.ToHexString(SHA256.HashData(Encoding.UTF8.GetBytes(Path.GetFullPath(dataPath).ToUpperInvariant())));
            instance = new Mutex(true, @"Local\CodexAccountSwitcher-" + key, out ownsMutex);
            activateWindow = new EventWaitHandle(false, EventResetMode.AutoReset, @"Local\CodexAccountSwitcher-Activate-" + key);
            if (!ownsMutex) { activateWindow.Set(); Shutdown(); return; }
            ApplyTheme();
            client = new CoreClient(HostRuntime.Resolve(Assembly.GetExecutingAssembly()), dataPath);
            var native = new NativeSettings();
            window = new MainWindow(client, native); MainWindow = window;
            activationListener = ThreadPool.RegisterWaitForSingleObject(activateWindow, (_, _) =>
                Dispatcher.BeginInvoke(new Action(() => { if (!exiting) { ApplyTheme(); window.OpenWindow(); } })),
                null, Timeout.Infinite, false);
            tray = new Forms.NotifyIcon { Text = "Codex Account Switcher" };
            RefreshTrayIcon();
            tray.Visible = true;
            SystemEvents.UserPreferenceChanged += OnUserPreferenceChanged;
            trayMenu = new Forms.ContextMenuStrip();
            var openItem = new Forms.ToolStripMenuItem("Codex Account Switcher");
            openItem.Click += (_, _) => { ApplyTheme(); window.OpenWindow(); };
            var quitItem = new Forms.ToolStripMenuItem();
            quitItem.Click += (_, _) => _ = QuitAsync();
            trayMenu.Items.Add(openItem); trayMenu.Items.Add(new Forms.ToolStripSeparator()); trayMenu.Items.Add(quitItem);
            trayMenu.Opening += (_, _) => { quitItem.Text = client.State.Text("quit"); quitItem.Enabled = !window.IsBusy; };
            tray.ContextMenuStrip = trayMenu;
            tray.MouseClick += (_, args) => {
                if (args.Button == Forms.MouseButtons.Left) { ApplyTheme(); window.OpenWindow(); }
            };
            client.Changed += RefreshTray;
            await client.InitializeAsync(native.Version);
            if (!e.Args.Contains("--background")) window.OpenWindow();
            updates = new DispatcherTimer { Interval = TimeSpan.FromHours(1) };
            updates.Tick += async (_, _) => { if (native.AutomaticallyCheckUpdates) await native.CheckUpdatesAsync(); };
            updates.Start();
            if (native.AutomaticallyCheckUpdates) _ = native.CheckUpdatesAsync();
        } catch (Exception ex) {
            MessageBox.Show(ex.Message, "Codex Account Switcher", MessageBoxButton.OK, MessageBoxImage.Error);
            await QuitAsync();
        }
    }

    private void RefreshTray()
    {
        if (client == null || tray == null) return;
        RefreshTrayIcon();
        var active = client.State.Accounts.FirstOrDefault(row => row.Profile.Id == client.State.ActiveAccountID);
        var percent = client.State.Settings.ShowsMenuBarPercentage ? active?.Usage?.RemainingPercent : null;
        var label = active == null ? "Codex Account Switcher" : active.Profile.DisplayName + (percent != null ? " · " + percent + "%" : "");
        tray.Text = label.Length > 63 ? label[..63] : label;
    }
    private void RefreshTrayIcon()
    {
        if (tray == null) return;
        using var key = Registry.CurrentUser.OpenSubKey(@"Software\Microsoft\Windows\CurrentVersion\Themes\Personalize");
        // Taskbar appearance can differ from the application's light/dark theme.
        var variant = key?.GetValue("SystemUsesLightTheme") is int light && light != 0 ? "light" : "dark";
        var size = Forms.SystemInformation.SmallIconSize;
        if (trayIconVariant == variant && trayIconSize == size) return;
        var uri = new Uri($"pack://application:,,,/Codex-Account-Switcher-windows-x64;component/tray-{variant}.ico");
        using var resource = GetResourceStream(uri).Stream;
        using var original = new Icon(resource, size);
        var replacement = (Icon)original.Clone();
        tray.Icon = replacement;
        icon?.Dispose(); icon = replacement;
        trayIconVariant = variant; trayIconSize = size;
    }
    private void OnUserPreferenceChanged(object sender, UserPreferenceChangedEventArgs e)
    {
        if (Dispatcher.HasShutdownStarted) return;
        Dispatcher.BeginInvoke(new Action(() => { if (!exiting) RefreshTrayIcon(); }));
    }
    private static bool IsDark() {
        using var key = Registry.CurrentUser.OpenSubKey(@"Software\Microsoft\Windows\CurrentVersion\Themes\Personalize");
        return key?.GetValue("AppsUseLightTheme") is int value && value == 0;
    }
    private void ApplyTheme() {
        var dark = IsDark();
        foreach (var pair in new[] { ("ListSurface", dark ? "#2D2D2D" : "#FFFFFF"), ("Surface", dark ? "#282828" : "#F5F5F5"), ("Ink", dark ? "#F5F5F5" : "#1A1A1A"),
            ("Muted", dark ? "#BEBEBE" : "#666666"), ("Line", dark ? "#444444" : "#DDDDDD"),
            ("Accent", dark ? "#60CDFF" : "#0067C0"), ("Selected", dark ? "#293F50" : "#E2EEFA"), ("Hover", dark ? "#15FFFFFF" : "#0C000000") })
            Resources[pair.Item1] = new SolidColorBrush((System.Windows.Media.Color)System.Windows.Media.ColorConverter.ConvertFromString(pair.Item2));
    }
    private async Task QuitAsync() {
        if (exiting || window?.IsBusy == true) return;
        exiting = true; updates?.Stop();
        activationListener?.Unregister(null);
        if (client != null) { client.Changed -= RefreshTray; await client.DisposeAsync(); }
        window?.CloseForExit();
        Shutdown();
    }
    private async Task SelfTestAsync() {
        var root = Path.Combine(Path.GetTempPath(), "switcher-package-check-" + Guid.NewGuid());
        var result = "PASS"; var exitCode = 0;
        try {
            Directory.CreateDirectory(Path.Combine(root, "active"));
            var host = HostRuntime.Resolve(Assembly.GetExecutingAssembly());
            await using var core = new CoreClient(host, Path.Combine(root, "data"), Path.Combine(root, "active"));
            await core.InitializeAsync(new NativeSettings().Version).WaitAsync(TimeSpan.FromSeconds(30));
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
        SystemEvents.UserPreferenceChanged -= OnUserPreferenceChanged;
        if (tray != null) { tray.Visible = false; tray.Dispose(); }
        trayMenu?.Dispose();
        icon?.Dispose();
        activateWindow?.Dispose();
        if (ownsMutex) instance?.ReleaseMutex(); instance?.Dispose();
        base.OnExit(e);
    }
}
