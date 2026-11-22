using System;
using System.Collections.Generic;
using System.IO;
using System.Linq;
using System.Threading.Tasks;
using System.Windows;
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
            const string testPubKey = "MFkwEwYHKoZIzj0CAQYIKoZIzj0DAQcDQgAEo68/mjZ8Qwu1darSKOA/idYSAyrHm2TiXTE8zWGUa6shjD1kKPAx+MeTmUj69dBDfxTAoyCVcsUczLWvfuJdtg==";
            const string signedFeed = """
                {
                  "version": "0.2.1",
                  "tag": "v0.2.1",
                  "url": "https://github.com/4379711/codex-account-switcher/releases/download/v0.2.1/Codex-Account-Switcher-windows-x64.exe",
                  "size": 123456,
                  "sha256": "aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa",
                  "releaseNotesUrl": "https://github.com/4379711/codex-account-switcher/releases/tag/v0.2.1",
                  "signature": "gk9jo6f140VoyZ9NgUbh2dVOFfxR1lIWELRU9WrBH6c+ER5B44Tq6hyvv+rljjUbdwyT9CV/W0KIPZFYl0xO2w=="
                }
                """;
            var parsed = WindowsUpdater.ParseAndVerifyManifest(signedFeed, new Version(0, 2, 0), testPubKey);
            Assert(parsed != null && parsed.Version == new Version(0, 2, 1),
                "Updates must accept valid signed unified releases newer than the current version.");
            Assert(WindowsUpdater.ParseAndVerifyManifest(signedFeed, new Version(0, 2, 1), testPubKey) == null,
                "Updates must ignore the same or older versions.");
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
            var active = All<Button>(window).Single(button => System.Windows.Automation.AutomationProperties.GetName(button) == "personal@example.test");
            active.RaiseEvent(new RoutedEventArgs(Button.ClickEvent));
            Assert(window.IsVisible && client.Commands.Count == 0, "Clicking the active account keeps the window open.");
            Assert(All<TextBlock>(window).Count(text => text.Text.Contains("@example.test")) == 2, "Home must use full emails as account titles.");
            Assert(All<TextBlock>(window).Where(text => text.Text.Contains("@example.test")).All(text =>
                text.TextWrapping == TextWrapping.NoWrap && text.TextTrimming == TextTrimming.CharacterEllipsis && Equals(text.ToolTip, text.Text)),
                "Account emails must stay on one line and expose the full address in a tooltip.");
            Assert(!All<TextBlock>(window).Any(text => text.Text == "当前"), "Home uses selection color, not active labels.");
            Assert(All<TextBlock>(window).Any(text => text.Text == "重置次数: 2"), "Home shows the reported reset count beneath usage.");
            Assert(All<TextBlock>(window).Any(text => text.Text == "重置次数: 未知"), "Missing reset count must not be shown as zero.");
            Assert(All<TextBlock>(window).Any(text => text.Text == "有效期：2099-10-17" && text.ToolTip is string),
                "Home shows the subscription date without a parenthetical label and exposes its check time on hover.");
            Assert(All<TextBlock>(window).Any(text => text.Text == "有效期：未知"), "Missing subscription date stays unknown.");
            var target = All<Button>(window).Single(button => button.Content is Grid && System.Windows.Automation.AutomationProperties.GetName(button) == "studio@example.test");
            target.RaiseEvent(new RoutedEventArgs(Button.ClickEvent));
            Assert(window.CurrentPage == "switch", "Selecting a row must open an in-place confirmation.");
            Assert(client.Commands.Count == 0, "Selection must not switch before confirmation.");
            Render(window, Path.Combine(output, "switch-zh.png"));
            Assert(All<TextBlock>(window).Any(text => text.Text.Contains("强制结束") && text.Text.Contains("未保存的状态可能丢失")),
                "Windows confirmation must explain forced termination before switching.");
            window.Navigate("manage"); Render(window, Path.Combine(output, "manage-zh.png"));
            Assert(All<TextBlock>(window).Count(text => text.Text.Contains("@example.test")) == 2, "Manage must show account email addresses.");
            Assert(!All<TextBlock>(window).Any(text => text.Text is "Personal" or "Studio"), "Manage must not duplicate the email with a display-name row.");
            var addHint = All<TextBlock>(window).Single(text => text.Text == client.State.Text("sign_in_hint"));
            var addButton = All<Button>(window).Single(button => System.Windows.Automation.AutomationProperties.GetName(button) == client.State.Text("add_account"));
            var hintPosition = addHint.TranslatePoint(new Point(), window);
            var addPosition = addButton.TranslatePoint(new Point(), window);
            Assert(hintPosition.X >= addPosition.X + addButton.ActualWidth &&
                hintPosition.Y >= addPosition.Y && hintPosition.Y + addHint.ActualHeight <= addPosition.Y + addButton.ActualHeight + 1,
                "The sign-in hint must sit to the right of Add Account within the same row.");
            Assert(All<TextBlock>(window).Count(text => text.Text == "当前") == 1, "Manage identifies the active account.");
            var dragLabel = client.State.Text("drag_to_reorder");
            var handles = All<TextBlock>(window).Where(text => System.Windows.Automation.AutomationProperties.GetName(text) == dragLabel).ToArray();
            Assert(handles.Length == 2 && handles.All(handle => handle.ToolTip as string == dragLabel),
                "Each saved account must have a named drag handle.");
            Assert(All<Border>(window).Count(row => row.ReadLocalValue(UIElement.AllowDropProperty) is true) == 2,
                "Each account row must accept a drop, including the active account.");
            var weeklySwitchName = client.State.Text("weekly_auto_start");
            bool IsWeeklyAutoStart(CheckBox toggle) =>
                System.Windows.Automation.AutomationProperties.GetName(toggle) == weeklySwitchName;
            Assert(!All<CheckBox>(window).Any(IsWeeklyAutoStart) &&
                !All<TextBlock>(window).Any(text => text.Text == client.State.Text("weekly_auto_start_hint")),
                "Manage accounts must not show weekly auto-start controls or help.");
            window.Navigate("settings"); Render(window, Path.Combine(output, "settings-zh.png"));
            var weeklyAutoStart = All<CheckBox>(window).Single(IsWeeklyAutoStart);
            Assert(weeklyAutoStart.IsChecked == false && client.Commands.Count == 0,
                "Settings must display a single global weekly auto-start switch, off by default, without sending commands.");
            Assert(!All<TextBlock>(window).Any(text => text.Text.Contains("@example.test")),
                "Global weekly auto-start must not display per-account controls.");
            var weeklyHint = All<TextBlock>(window).Single(text => text.Text == client.State.Text("weekly_auto_start_hint"));
            var resetHint = All<TextBlock>(window).Single(text => text.Text == client.State.Text("auto_reset_hint"));
            var resetLog = All<Button>(window).Single(button =>
                System.Windows.Automation.AutomationProperties.GetName(button) == client.State.Text("open_reset_log"));
            var updatesHeading = All<TextBlock>(window).Single(text => text.Text == client.State.Text("settings_updates"));
            double Top(FrameworkElement element) => element.TranslatePoint(new Point(), window).Y;
            Assert(Top(resetHint) < Top(weeklyAutoStart) && Top(weeklyAutoStart) < Top(weeklyHint) &&
                Top(weeklyHint) < Top(resetLog) &&
                Top(resetLog) < Top(updatesHeading),
                "Settings must put the log button after both automation controls and before the updates section.");
            weeklyAutoStart.IsChecked = true;
            weeklyAutoStart.RaiseEvent(new RoutedEventArgs(CheckBox.ClickEvent));
            const string enableWeeklyAutoStart = "weeklyUsageAutoStart:True";
            Assert(client.Commands.SequenceEqual(new[] { enableWeeklyAutoStart }),
                "Enabling weekly auto-start must send one global command without an account ID.");

            client.State = client.State with { WeeklyUsageAutoStartEnabled = true };
            window.Navigate("settings");
            window.UpdateLayout();
            weeklyAutoStart = All<CheckBox>(window).Single(IsWeeklyAutoStart);
            Assert(weeklyAutoStart.IsChecked == true && client.Commands.SequenceEqual(new[] { enableWeeklyAutoStart }),
                "Rebuilding Settings must show the persisted global setting without sending commands.");
            weeklyAutoStart.IsChecked = false;
            weeklyAutoStart.RaiseEvent(new RoutedEventArgs(CheckBox.ClickEvent));
            Assert(client.Commands.SequenceEqual(new[] { enableWeeklyAutoStart, "weeklyUsageAutoStart:False" }),
                "Disabling weekly auto-start must also send one command without an account ID.");
            client.State = client.State with { WeeklyUsageAutoStartEnabled = false };
            client.Commands.Clear();
            var languagePicker = All<ComboBox>(window).Single(box => box.Items.Contains("Italiano"));
            var fiveHour = All<CheckBox>(window).Single(toggle => System.Windows.Automation.AutomationProperties.GetName(toggle) == "显示 5 小时用量");
            fiveHour.IsChecked = true; fiveHour.RaiseEvent(new RoutedEventArgs(CheckBox.ClickEvent));
            Assert(client.Commands.Single() == "fiveHour:True", "Settings must save immediately.");
            var experiment = All<CheckBox>(window).Single(toggle => System.Windows.Automation.AutomationProperties.GetName(toggle) == client.State.Text("auto_reset"));
            Assert(experiment.IsChecked == false, "Auto-reset must default to off.");
            experiment.IsChecked = true; experiment.RaiseEvent(new RoutedEventArgs(CheckBox.ClickEvent));
            Assert(client.Commands.SequenceEqual(new[] { "fiveHour:True", "autoReset:True" }),
                "The auto-reset toggle must send the setting to the shared host.");
            languagePicker.SelectedItem = "Italiano";
            Assert(client.Commands.Last() == "language:italian", "Selecting Italian must reach the shared host.");
            Assert(All<TextBlock>(window).Any(text => text.Text == client.State.Text("auto_reset_hint")),
                "Settings must disclose real reset consumption and runtime requirements.");
            Assert(!All<TextBlock>(window).Any(text => text.Text is "保存" or "Save"), "Settings must not have a Save flow.");
            client.State = client.State with { Settings = client.State.Settings with { ShowsFiveHourUsage = true, AutoResetEnabled = true } };
            window.Navigate("settings"); Render(window, Path.Combine(output, "settings-auto-reset-enabled-zh.png"));
            Assert(All<CheckBox>(window).Single(toggle => System.Windows.Automation.AutomationProperties.GetName(toggle) == client.State.Text("auto_reset")).IsChecked == true,
                "The auto-reset toggle must reflect the persisted setting.");
            window.Navigate("accounts"); Render(window, Path.Combine(output, "accounts-five-hour-zh.png"));
            Assert(All<TextBlock>(window).Count(text => text.Text == "5 小时") == 2, "Five-hour view must be per account.");
            var closed = false; window.Closed += (_, _) => closed = true;
            var beforeClose = client.Commands.Count;
            window.Close();
            Assert(!window.IsVisible && !closed, "Title-bar close must hide the window without disposing the running app.");
            Assert(client.Commands.Count == beforeClose, "Hiding must not send account commands.");
            window.OpenWindow();
            Assert(window.IsVisible && !closed, "The tray must be able to reopen the same window.");
            client.State = client.State with { IsAddingAccount = true };
            window.Navigate("accounts");
            window.Hide();
            window.OpenWindow();
            Assert(window.CurrentPage == "manage", "Reopening a pending login must restore its cancellation page.");
            Render(window, Path.Combine(output, "pending-sign-in-reopened-zh.png"));
            Assert(All<Button>(window).Any(button => System.Windows.Automation.AutomationProperties.GetName(button) == client.State.Text("cancel_add_account") && button.IsEnabled),
                "The pending login must remain cancellable after reopening.");
            client.State = client.State with { IsAddingAccount = false };
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
        public event Action? Changed { add {} remove {} }
        public List<string> Commands { get; } = [];
        public AccountSnapshot State { get; set; }
        public FixtureClient() {
            var id = Guid.Parse("11111111-1111-1111-1111-111111111111");
            var time = new DateTimeOffset(2026, 9, 15, 9, 25, 0, TimeSpan.FromHours(8));
            State = new([
                new(new(id, "Personal", "personal@example.test"), "P", new(83, time, 91, time.AddHours(-2), 2), null,
                    "loaded", new(new DateTimeOffset(2099, 10, 17, 12, 0, 0, TimeSpan.Zero), time)),
                new(new(Guid.Parse("22222222-2222-2222-2222-222222222222"), "Studio", "studio@example.test"), "S", new(56, time.AddHours(1), 68, time.AddHours(-1)), null)
            ], id, new("simplifiedChinese"), false, false, true, null, new() {
                ["usage"] = "用量", ["resets"] = "重置于", ["reset_credits"] = "重置次数", ["unknown"] = "未知", ["left"] = "% 剩余", ["manage"] = "管理账号", ["settings"] = "设置", ["quit"] = "退出应用",
                ["subscription_until"] = "有效期：%@", ["subscription_snapshot"] = "登录快照", ["subscription_old_snapshot"] = "旧登录快照",
                ["subscription_unknown"] = "有效期：未知", ["subscription_detail"] = "最近核验于 %@。",
                ["accounts"] = "账号", ["drag_to_reorder"] = "拖动调整顺序", ["back"] = "返回", ["active"] = "当前", ["remove"] = "移除", ["add_account"] = "添加账号",
                ["sign_in_hint"] = "将打开浏览器进行 Codex 登录。", ["register_current_account"] = "登记当前登录账号",
                ["settings_general"] = "通用", ["settings_updates"] = "软件更新", ["launch_at_login"] = "登录时自动启动",
                ["settings_automation"] = "自动化", ["auto_reset"] = "自动使用重置卡",
                ["auto_reset_hint"] = "重置卡到期前 10 分钟开始尝试使用，适用于所有已保存账号。请保持应用运行、电脑唤醒。", ["open_reset_log"] = "打开日志文件夹",
                ["weekly_auto_start"] = "自动开启下个 7 天周期",
                ["weekly_auto_start_hint"] = "适用于所有已保存账号。周额度自然恢复到 100% 后，用对应账号自动发送一次「只回复 OK」。请保持应用运行。",
                ["show_menu_bar_percentage"] = "在菜单栏显示百分比", ["show_tray_percentage"] = "在系统托盘显示百分比", ["show_five_hour_usage"] = "显示 5 小时用量", ["language"] = "语言",
                ["remove_body_windows"] = "此操作只会移除这台电脑上保存的本地账号档案。",
                ["system_default"] = "跟随系统", ["english"] = "English", ["simplified_chinese"] = "简体中文", ["italian"] = "Italiano", ["five_hour"] = "5 小时", ["weekly"] = "7 天",
                ["automatically_check_updates"] = "自动检查更新", ["update_check_hint"] = "每小时检查一次，有新版本时显示蓝点。",
                ["update_available"] = "发现新版本 %@", ["update_action"] = "更新…", ["update_installing"] = "正在安装…",
                ["update_downloading"] = "正在下载更新… %@%", ["update_download_failed"] = "更新下载失败。",
                ["update_verify_failed"] = "更新签名校验失败，已丢弃安装包。", ["update_readonly_fallback"] = "当前目录不可写，已改为打开下载页面。",
                ["current_version"] = "当前版本 %@", ["check_for_updates"] = "检查更新", ["cancel"] = "取消", ["switch"] = "切换账号",
                ["switch_title"] = "切换到 %@？", ["switch_body_windows"] = "将强制结束 Codex Desktop 及其子进程，然后重新打开 Desktop。正在运行的任务会被中断，未保存的状态可能丢失。请先完成或停止 Desktop 任务再切换。独立启动的 CLI 会话保持运行，新 CLI 会话将使用所选账号。"
            });
        }
        public Task CommandAsync(string command, Guid? accountID = null, bool? value = null, string? language = null,
            Guid? targetAccountID = null) {
            var argument = language ?? value?.ToString();
            Commands.Add(accountID is { } id ? $"{command}:{id}:{argument}" : $"{command}:{argument}");
            return Task.CompletedTask;
        }
    }
}
