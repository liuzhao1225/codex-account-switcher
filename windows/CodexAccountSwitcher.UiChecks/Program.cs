using System;
using System.Collections.Generic;
using System.IO;
using System.Linq;
using System.Threading.Tasks;
using System.Windows;
using System.Windows.Automation;
using System.Windows.Controls;
using System.Windows.Media;
using System.Windows.Media.Imaging;
using System.Windows.Threading;
using CodexAccountSwitcher;
using CodexAccountSwitcher.Core;

internal static class Program
{
    [STAThread]
    private static int Main(string[] args)
    {
        var output = Path.GetFullPath(args.FirstOrDefault() ?? Path.Combine("windows", "artifacts", "ui"));
        try {
            using var releases = System.Text.Json.JsonDocument.Parse("""
                [
                  {"tag_name":"macos-v99.0.0","draft":false,"assets":[{"name":"Codex-Account-Switcher-windows-x64.exe"}]},
                  {"tag_name":"windows-v99.0.0","draft":false,"assets":[{"name":"Codex-Account-Switcher-windows-x64.exe"}]},
                  {"tag_name":"v9.0.0","draft":true,"assets":[{"name":"Codex-Account-Switcher-windows-x64.exe"}]},
                  {"tag_name":"v8.0.0","draft":false,"prerelease":true,"assets":[{"name":"Codex-Account-Switcher-windows-x64.exe"}]},
                  {"tag_name":"v7.0.0","draft":false,"assets":[]},
                  {"tag_name":"v06.0.0","draft":false,"assets":[{"name":"Codex-Account-Switcher-windows-x64.exe"}]},
                  {"tag_name":"v0.1.9","draft":false,"assets":[{"name":"Codex-Account-Switcher-windows-x64.exe"}]},
                  {"tag_name":"v0.1.12","draft":false,"assets":[{"name":"Codex-Account-Switcher-windows-x64.exe"}]}
                ]
                """);
            Assert(NativeSettings.LatestWindowsVersion(releases.RootElement) == new Version(0, 1, 12),
                "Updates must select stable unified releases with a Windows EXE, ordered by version.");
            using var macOnly = System.Text.Json.JsonDocument.Parse("""
                [{"tag_name":"v99.0.0","draft":false,"assets":[{"name":"Codex-Account-Switcher-macos-arm64.dmg"}]}]
                """);
            Assert(NativeSettings.LatestWindowsVersion(macOnly.RootElement) == null, "A release without a Windows EXE must never prompt a Windows update.");
            Directory.CreateDirectory(output);
            var app = new App(false); app.InitializeComponent();
            var client = new FixtureClient();
            var window = new MainWindow(client);
            Assert(window.Icon != null, "The taskbar and title bar must use the packaged application logo.");
            using (var stream = Application.GetResourceStream(App.IconUri).Stream)
            using (var trayIcon = new System.Drawing.Icon(stream, 16, 16))
            using (var pixels = trayIcon.ToBitmap())
                Assert(pixels.Width == 16 && pixels.Height == 16, "The original logo must contain a usable native tray size.");
            foreach (var variant in new[] { "light", "dark" }) {
                foreach (var size in new[] { 16, 20, 24, 32, 40, 48, 64 }) {
                    var uri = new Uri($"pack://application:,,,/Codex-Account-Switcher-windows-x64;component/tray-{variant}.ico");
                    using var stream = Application.GetResourceStream(uri).Stream;
                    using var trayIcon = new System.Drawing.Icon(stream, size, size);
                    using var pixels = trayIcon.ToBitmap();
                    Assert(pixels.Width == size && pixels.Height == size, $"Tray {variant} must include {size}px (loaded {pixels.Width} x {pixels.Height}).");
                    Assert(pixels.GetPixel(0, 0).A == 0 && pixels.GetPixel(size - 1, size - 1).A == 0,
                        "Tray logos must have transparent corners, with no application tile.");
                    var top = size; var bottom = -1;
                    for (var y = 0; y < size; y++) for (var x = 0; x < size; x++) {
                        var pixel = pixels.GetPixel(x, y);
                        if (pixel.A < 128) continue;
                        top = Math.Min(top, y); bottom = Math.Max(bottom, y);
                        Assert(pixel.R == (variant == "light" ? 0 : 255), "Tray foreground must match the taskbar theme.");
                    }
                    Assert(bottom - top + 1 >= size * 0.95, "The visible logo must fill the tray canvas without the old app-icon inset.");
                }
            }
            Render(window, Path.Combine(output, "accounts-zh.png"));
            Assert(Math.Abs(window.ActualWidth - 420) < 2 && window.ActualHeight < 360,
                $"Home must be a compact 420 DIP window (actual {window.ActualWidth} × {window.ActualHeight}).");
            Assert(window.ShowInTaskbar && !window.Topmost && window.WindowStyle == WindowStyle.SingleBorderWindow,
                "Windows must use a normal titled window visible in the taskbar.");
            var other = new Window { Width = 100, Height = 100, ShowInTaskbar = false };
            other.Show(); other.Activate(); other.Close();
            Assert(window.IsVisible, "Losing focus must not dismiss the account window.");
            var active = All<Button>(window).Single(button => System.Windows.Automation.AutomationProperties.GetName(button) == "Personal");
            active.RaiseEvent(new RoutedEventArgs(Button.ClickEvent));
            Assert(window.IsVisible && client.Commands.Single() == "prepareAccountSwitch:",
                "Even the highlighted row must refresh through the shared core before deciding it is active.");
            client.Commands.Clear();
            Assert(!All<TextBlock>(window).Any(text => text.Text.Contains("@")), "Home must not display email addresses.");
            Assert(!All<TextBlock>(window).Any(text => text.Text == "当前"), "Home uses selection color, not active labels.");
            var target = All<Button>(window).Single(button => button.Content is Grid && System.Windows.Automation.AutomationProperties.GetName(button) == "Studio");
            target.RaiseEvent(new RoutedEventArgs(Button.ClickEvent));
            Assert(window.CurrentPage == "switch", "Selecting a row must open an in-place confirmation.");
            Assert(client.Commands.Single() == "prepareAccountSwitch:", "Selection must only prepare, never execute the switch.");
            Render(window, Path.Combine(output, "switch-zh.png"));
            client.PendingCancellation = new TaskCompletionSource();
            window.Navigate("manage");
            Assert(window.CurrentPage == "switch", "Navigation waits for the shared core to cancel its pending confirmation.");
            client.PendingCancellation.SetResult();
            Render(window, Path.Combine(output, "manage-zh.png"));
            Assert(window.CurrentPage == "manage", "Asynchronous cancellation must preserve the requested destination.");
            client.PendingCancellation = null;
            Assert(All<TextBlock>(window).Count(text => text.Text.Contains("@example.test")) == 2, "Manage must show account email addresses.");
            Assert(All<TextBlock>(window).Count(text => text.Text == "当前") == 1, "Manage identifies the active account.");
            Assert(!All<TextBox>(window).Any(), "Account management must not add a rename workflow.");
            window.Navigate("settings"); Render(window, Path.Combine(output, "settings-zh.png"));
            Assert(All<CheckBox>(window).Count() == 5, "Settings includes the opt-in provider switch.");
            client.Commands.Clear();
            var fiveHour = All<CheckBox>(window).Single(toggle => System.Windows.Automation.AutomationProperties.GetName(toggle) == "显示 5 小时用量");
            fiveHour.IsChecked = true; fiveHour.RaiseEvent(new RoutedEventArgs(CheckBox.ClickEvent));
            Assert(client.Commands.Single() == "fiveHour:True", "Settings must save immediately.");
            Assert(!All<TextBlock>(window).Any(text => text.Text is "保存" or "Save"), "Settings must not have a Save flow.");
            client.State = client.State with { Settings = client.State.Settings with { ShowsFiveHourUsage = true } };
            window.Navigate("accounts"); Render(window, Path.Combine(output, "accounts-five-hour-zh.png"));
            Assert(All<TextBlock>(window).Count(text => text.Text == "5 小时") == 2, "Five-hour view must be per account.");
            client.State = client.State with {
                Settings = client.State.Settings with { EnablesProviderSwitching = true },
                AuthenticationKind = "apiKey", ActiveAccountID = null,
                Accounts = client.State.Accounts.Select(row => row with { IsActive = false, IsCredentialOwner = false, CanRemove = true }).ToArray(),
                Providers = [new(new("openai", "OpenAI API"), true, "API key 登录"),
                    new(new("azure", "Azure OpenAI"), false, "已配置的提供商")]
            };
            window.Navigate("accounts"); Render(window, Path.Combine(output, "providers-zh.png"));
            var azure = All<Button>(window).Single(button => AutomationProperties.GetName(button) == "Azure OpenAI");
            azure.RaiseEvent(new RoutedEventArgs(Button.ClickEvent));
            Assert(client.LastProviderID == "azure" && window.CurrentPage == "switch", "Provider rows prepare through the host with a provider ID.");
            Assert(All<TextBlock>(window).Any(text => text.Text == client.State.PendingSwitch!.Message), "Display the core's provider confirmation verbatim.");
            Render(window, Path.Combine(output, "provider-switch-zh.png"));
            window.Navigate("accounts");
            var saved = All<Button>(window).Single(button => AutomationProperties.GetName(button) == "Personal");
            saved.RaiseEvent(new RoutedEventArgs(Button.ClickEvent));
            Assert(All<TextBlock>(window).Any(text => text.Text == "API 登录将单独保存在本机。模型设置将保留。"),
                "API retention and model notices must come from the shared prepared action.");
            Render(window, Path.Combine(output, "api-return-zh.png"));
            var confirm = All<Button>(window).Single(button => AutomationProperties.GetName(button) == "切换账号");
            confirm.RaiseEvent(new RoutedEventArgs(Button.ClickEvent));
            Assert(client.Commands.Last() == "confirmSwitch:", "Only confirmation executes a prepared switch.");
            window.Navigate("manage");
            Assert(All<Button>(window).Count(button => AutomationProperties.GetName(button) == "移除") == 2,
                "API authentication must not mark an old ChatGPT account as protected.");
            var closed = false; window.Closed += (_, _) => closed = true;
            var beforeClose = client.Commands.Count;
            window.Close();
            Assert(!window.IsVisible && !closed, "Title-bar close must hide the window without disposing the running app.");
            Assert(client.Commands.Count == beforeClose, "Hiding must not send account commands.");
            window.OpenWindow();
            Assert(window.IsVisible && !closed, "The tray must be able to reopen the same window.");
            client.State = client.State with { IsMutating = true };
            window.Close();
            Assert(!window.IsVisible && !closed, "An active operation can continue while the window is hidden.");
            client.State = client.State with { IsMutating = false };
            window.CloseForExit();
            Assert(closed, "Explicit application exit must release the window.");
            Console.WriteLine("PASS: native taskbar window, focus persistence, compact home, full-row confirmation, management, immediate settings and optional five-hour usage.");
            Console.WriteLine(output);
            return 0;
        } catch (Exception ex) { Console.Error.WriteLine(ex); return 1; }
    }
    private static void Assert(bool condition, string message) { if (!condition) throw new Exception(message); }
    private static IEnumerable<T> All<T>(DependencyObject parent) where T : DependencyObject {
        for (var i = 0; i < VisualTreeHelper.GetChildrenCount(parent); i++) {
            var child = VisualTreeHelper.GetChild(parent, i); if (child is T match) yield return match;
            foreach (var descendant in All<T>(child)) yield return descendant;
        }
    }
    private static void Render(Window window, string path) {
        window.Show(); window.UpdateLayout();
        var frame = new DispatcherFrame(); window.Dispatcher.BeginInvoke(DispatcherPriority.ApplicationIdle, new Action(() => frame.Continue = false)); Dispatcher.PushFrame(frame);
        window.UpdateLayout();
        var bitmap = new RenderTargetBitmap((int)Math.Ceiling(window.ActualWidth * 2), (int)Math.Ceiling(window.ActualHeight * 2), 192, 192, PixelFormats.Pbgra32);
        var visual = new DrawingVisual(); using (var drawing = visual.RenderOpen()) drawing.DrawRectangle(new VisualBrush(window), null, new Rect(0, 0, window.ActualWidth, window.ActualHeight));
        bitmap.Render(visual); var encoder = new PngBitmapEncoder(); encoder.Frames.Add(BitmapFrame.Create(bitmap));
        using var stream = File.Create(path); encoder.Save(stream);
    }
    private sealed class FixtureClient : IAccountClient {
        public event Action? Changed;
        public List<string> Commands { get; } = [];
        public string? LastProviderID { get; private set; }
        public TaskCompletionSource? PendingCancellation { get; set; }
        public AccountSnapshot State { get; set; }
        public FixtureClient() {
            var id = Guid.Parse("11111111-1111-1111-1111-111111111111");
            var time = new DateTimeOffset(2026, 9, 15, 9, 25, 0, TimeSpan.FromHours(8));
            State = new([
                new(new(id, "Personal", "personal@example.test"), "P", new(83, time, 91, time.AddHours(-2)), null, "loaded", true, true, false),
                new(new(Guid.Parse("22222222-2222-2222-2222-222222222222"), "Studio", "studio@example.test"), "S", new(56, time.AddHours(1), 68, time.AddHours(-1)), null, "loaded", false, false, true)
            ], id, new("simplifiedChinese"), false, false, true, null, new() {
                ["usage"] = "用量", ["resets"] = "重置于", ["left"] = "% 剩余", ["manage"] = "管理账号", ["settings"] = "设置", ["quit"] = "退出应用",
                ["accounts"] = "账号", ["back"] = "返回", ["active"] = "当前", ["remove"] = "移除", ["add_account"] = "添加账号",
                ["sign_in_hint"] = "将打开浏览器进行 Codex 登录。", ["register_current_account"] = "登记当前登录账号",
                ["settings_general"] = "通用", ["settings_updates"] = "软件更新", ["launch_at_login"] = "登录时自动启动",
                ["show_menu_bar_percentage"] = "在菜单栏显示百分比", ["show_five_hour_usage"] = "显示 5 小时用量", ["language"] = "语言",
                ["system_default"] = "跟随系统", ["english"] = "English", ["simplified_chinese"] = "简体中文", ["five_hour"] = "5 小时", ["weekly"] = "7 天",
                ["automatically_check_updates"] = "自动检查更新", ["update_check_hint"] = "每小时检查一次，有新版本时显示蓝点。",
                ["current_version"] = "当前版本 %@", ["check_for_updates"] = "检查更新", ["cancel"] = "取消", ["switch"] = "切换账号",
                ["switch_title"] = "切换到 %@？", ["switch_body"] = "Codex Desktop 将关闭并重新打开。请先完成或停止正在运行的 Desktop 任务。如果 Desktop 显示退出提示，请处理该提示；无法正常退出时会停止切换。现有 CLI 会话保持运行，新 CLI 会话将使用所选账号。",
                ["advanced"] = "高级", ["enable_provider_switching"] = "启用提供商切换", ["providers"] = "已配置的提供商",
                ["provider_setup_notice"] = "适用于已在 Codex 中配置的提供商。模型兼容性需要单独验证。", ["credential_in_use"] = "登录凭据使用中"
            }, [], "openai", "chatgpt", null);
        }
        public async Task CommandAsync(string command, Guid? accountID = null, bool? value = null, string? language = null, string? providerID = null) {
            Commands.Add(command + ":" + value);
            LastProviderID = providerID;
            if (command == "cancelSwitch" && PendingCancellation != null) await PendingCancellation.Task;
            if (command == "prepareAccountSwitch") {
                var row = State.Accounts.Single(row => row.Profile.Id == accountID);
                State = State with { PendingSwitch = row.IsActive ? null : new(accountID, null, "切换到 " + row.Profile.DisplayName + "？",
                    State.AuthenticationKind == "apiKey" ? "API 登录将单独保存在本机。模型设置将保留。" : State.Text("switch_body"), "切换账号") };
            } else if (command == "prepareProviderSwitch") {
                State = State with { PendingSwitch = new(null, providerID, "切换提供商？", "核心提供的重启与模型兼容提示。", "切换提供商") };
            } else if (command is "cancelSwitch" or "confirmSwitch") State = State with { PendingSwitch = null };
            Changed?.Invoke();
        }
    }
}
