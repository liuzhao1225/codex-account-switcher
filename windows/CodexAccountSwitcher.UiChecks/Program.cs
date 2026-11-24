using System;
using System.Collections.Generic;
using System.Diagnostics;
using System.IO;
using System.Linq;
using System.Net;
using System.Net.Http;
using System.Net.Http.Headers;
using System.Security.Cryptography;
using System.Text;
using System.Text.Json;
using System.Threading;
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
            const string testPubKey = "MFkwEwYHKoZIzj0CAQYIKoZIzj0DAQcDQgAEkeWTKfZIKx3GnWkh5xBlkyWt10Uhd7iJ0vnjlxDR8Ola1nSSc+wDED/iA8UNoy9bDrU7lHQCfN5dZo5MFByp7A==";
            const string signedFeed = """
                {
                  "version": "0.2.1",
                  "tag": "v0.2.1",
                  "url": "https://github.com/liuzhao1225/codex-account-switcher/releases/download/v0.2.1/Codex-Account-Switcher-windows-x64.exe",
                  "size": 123456,
                  "sha256": "aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa",
                  "releaseNotesUrl": "https://github.com/liuzhao1225/codex-account-switcher/releases/tag/v0.2.1",
                  "signature": "ejLJeqnLSWnne4afPqt0SqG+CuCuSf+JHyuSA8AmO+WVkOiwAEijmvx4XyjNK3HuOQfBq03c+0iuJwHO2BQr1g=="
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
            var simulatedNow = new DateTimeOffset(2026, 9, 15, 9, 30, 0, TimeSpan.FromHours(8));
            var window = new MainWindow(client, clock: () => simulatedNow);
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
            var liveSubBlock = All<TextBlock>(window).SingleOrDefault(text => text.Text == "有效至 2099-10-17");
            Assert(liveSubBlock != null && liveSubBlock.ToolTip is string liveTip
                && liveTip.Contains("自动续费：已开启") && liveTip.Contains("欠费状态：否")
                && liveTip.Contains("历史登录快照（非实时）"),
                "Home shows live subscription primary line and full details in tooltip.");
            var failedSubBlock = All<TextBlock>(window).SingleOrDefault(text => text.Text == "订阅日期：待同步 · 待更新");
            Assert(failedSubBlock != null && failedSubBlock.ToolTip is string failedTip
                && failedTip.Contains("刷新失败：Network timeout") && failedTip.Contains("历史登录快照（非实时）"),
                "First-sync failure with historical snapshot keeps main line as pending needs-update and puts error + history in tooltip.");
            simulatedNow = simulatedNow.AddMinutes(10);
            window.RefreshIfVisible();
            window.UpdateLayout();
            Assert(All<TextBlock>(window).Any(text => text.Text == "有效至 2099-10-17 · 待更新"),
                "Crossing the core staleAfter deadline updates the subscription line without a new network snapshot.");
            simulatedNow = simulatedNow.AddMinutes(-10);
            window.RefreshIfVisible();
            window.UpdateLayout();
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
            var noteAction = All<Button>(window).First(button => System.Windows.Automation.AutomationProperties.GetName(button) == "编辑账号备注");
            noteAction.RaiseEvent(new RoutedEventArgs(Button.ClickEvent));
            window.UpdateLayout();
            Assert(window.CurrentPage == "note", "Clicking edit note must open the note editor page.");
            All<TextBox>(window).Single().Text = "草稿";
            window.RefreshIfVisible();
            Assert(window.CurrentPage == "note" && All<TextBox>(window).Single().Text == "草稿",
                "Background refreshes must not wipe unsaved note input.");
            All<TextBox>(window).Single().Text = "工作";
            All<Button>(window).Single(button => System.Windows.Automation.AutomationProperties.GetName(button) == "保存备注")
                .RaiseEvent(new RoutedEventArgs(Button.ClickEvent));
            window.UpdateLayout();
            Assert(window.CurrentPage == "manage", "Saving a note must return to Manage.");
            Assert(All<TextBlock>(window).Any(text => text.Text == "工作"), "Saving a note must update the Manage list.");
            Assert(All<TextBlock>(window).Any(text => text.Text == "personal@example.test"), "A note must retain the identifiable email.");
            window.Navigate("settings"); Render(window, Path.Combine(output, "settings-zh.png"));
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
            var reminder = All<ComboBox>(window).Single(box => System.Windows.Automation.AutomationProperties.GetName(box) == "低额度提醒");
            Assert(reminder.SelectedItem as string == "关闭", "Low usage reminders must start off.");
            reminder.SelectedItem = "10%";
            Assert(client.Commands.Last() == "lowUsageThreshold:10", "Selecting a threshold must reach the shared host.");
            Assert(All<TextBlock>(window).Any(text => text.Text == client.State.Text("auto_reset_hint")),
                "Settings must disclose real reset consumption and runtime requirements.");
            Assert(!All<TextBlock>(window).Any(text => text.Text is "保存" or "Save"), "Settings must not have a Save flow.");
            client.State = client.State with { Settings = client.State.Settings with { ShowsFiveHourUsage = true, AutoResetEnabled = true } };
            window.Navigate("settings"); Render(window, Path.Combine(output, "settings-auto-reset-enabled-zh.png"));
            Assert(All<CheckBox>(window).Single(toggle => System.Windows.Automation.AutomationProperties.GetName(toggle) == client.State.Text("auto_reset")).IsChecked == true,
                "The auto-reset toggle must reflect the persisted setting.");
            window.Navigate("accounts"); Render(window, Path.Combine(output, "accounts-five-hour-zh.png"));
            Assert(All<TextBlock>(window).Count(text => text.Text == "5 小时") == 2, "Five-hour view must be per account.");
            Assert(All<TextBlock>(window).Any(text => text.Text == "工作") && All<TextBlock>(window).Any(text => text.Text == "personal@example.test"),
                "Home must render the saved note and identifiable email.");
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
            var customData = Path.Combine(Path.GetTempPath(), "switcher-ui-path-check-" + Guid.NewGuid().ToString("N"));
            var customWindow = new MainWindow(client, dataPath: customData);
            Assert(customWindow.DataPath == customData, "MainWindow must preserve the resolved custom dataPath.");
            customWindow.CloseForExit();
            Task.Run(VerifyNativeSettingsUpdateFlowsAsync).GetAwaiter().GetResult();
            Console.WriteLine("PASS: native taskbar window, focus persistence, compact home, full-row confirmation, management, immediate settings and optional five-hour usage.");
            Console.WriteLine(output);
            return 0;
        } catch (Exception ex) { Console.Error.WriteLine(ex); return 1; }
    }

    private static async Task VerifyNativeSettingsUpdateFlowsAsync()
    {
        var root = Path.Combine(Path.GetTempPath(), "switcher-ui-update-checks-" + Guid.NewGuid().ToString("N"));
        try
        {
            var updatesRoot = Path.Combine(root, "updates");

            var payload = new byte[64_000];
            Random.Shared.NextBytes(payload);
            var sha256 = Convert.ToHexString(SHA256.HashData(payload)).ToLowerInvariant();
            const string version = "9.9.9";
            const string tag = "v9.9.9";
            var url = $"https://github.com/{WindowsUpdater.Repository}/releases/download/{tag}/{WindowsUpdater.AssetName}";

            using var key = ECDsa.Create(ECCurve.NamedCurves.nistP256);
            var pubSpki = Convert.ToBase64String(key.ExportSubjectPublicKeyInfo());
            var sig = Convert.ToBase64String(key.SignData(
                WindowsUpdater.CanonicalPayload(version, tag, url, payload.Length, sha256),
                HashAlgorithmName.SHA256,
                DSASignatureFormat.IeeeP1363FixedFieldConcatenation));

            var manifestJson = JsonSerializer.Serialize(new
            {
                version,
                tag,
                url,
                size = payload.Length,
                sha256,
                releaseNotesUrl = $"https://github.com/{WindowsUpdater.Repository}/releases/tag/{tag}",
                signature = sig,
            });

            // 1. Read-only install directory opens release page fallback.
            Uri? openedFallback = null;
            var readOnlySettings = new NativeSettings(
                _ => new HttpClient(new StubUpdateHandler(manifestJson, () => new ByteArrayContent(payload))),
                _ => false,
                _ => null,
                uri => openedFallback = uri,
                () => @"C:\Program Files\Codex\Codex.exe",
                pubSpki);
            await readOnlySettings.CheckUpdatesAsync();
            Assert(readOnlySettings.AvailableUpdate != null, "Signed update manifest must populate AvailableUpdate.");
            await readOnlySettings.InstallUpdateAsync(
                new UpdateRestartHooks(() => true, () => { }, () => Task.CompletedTask),
                relaunchInBackground: false,
                updatesRoot);
            Assert(readOnlySettings.UpdateError == "update_readonly_fallback", "Read-only directory must set fallback error.");
            Assert(openedFallback == readOnlySettings.AvailableUpdate!.ReleaseNotesUri, "Read-only fallback must open release notes.");

            // 2. Signature / checksum mismatch cleans staging directory and reports update_verify_failed.
            var corrupted = (byte[])payload.Clone();
            corrupted[0] ^= 0xFF;
            var tamperSettings = new NativeSettings(
                _ => new HttpClient(new StubUpdateHandler(manifestJson, () => new ByteArrayContent(corrupted))),
                _ => true,
                _ => null,
                _ => { },
                () => @"C:\Writable\Codex.exe",
                pubSpki);
            await tamperSettings.CheckUpdatesAsync();
            await tamperSettings.InstallUpdateAsync(
                new UpdateRestartHooks(() => true, () => { }, () => Task.CompletedTask),
                relaunchInBackground: false,
                updatesRoot);
            Assert(tamperSettings.UpdateError == "update_verify_failed" && !tamperSettings.IsInstalling,
                "Tampered payload must surface update_verify_failed.");
            Assert(!Directory.EnumerateDirectories(updatesRoot).Any(), "Tampered update must remove staging directory.");

            // 3. Cancellation clears error and cleans staging directory.
            NativeSettings? cancelTarget = null;
            cancelTarget = new NativeSettings(
                _ => new HttpClient(new StubUpdateHandler(manifestJson, () =>
                {
                    var content = new StreamContent(new CancelTriggeringStream(payload, () => cancelTarget!.CancelUpdate()));
                    content.Headers.ContentLength = payload.Length;
                    return content;
                })),
                _ => true,
                _ => null,
                _ => { },
                () => @"C:\Writable\Codex.exe",
                pubSpki);
            await cancelTarget.CheckUpdatesAsync();
            await cancelTarget.InstallUpdateAsync(
                new UpdateRestartHooks(() => true, () => { }, () => Task.CompletedTask),
                relaunchInBackground: false,
                updatesRoot);
            Assert(cancelTarget.UpdateError == null && !cancelTarget.IsInstalling && cancelTarget.DownloadPercent == null,
                "Cancelled update must clear state cleanly without error.");
            Assert(!Directory.EnumerateDirectories(updatesRoot).Any(), "Cancelled update must remove staging directory.");

            // 4. Refused restart cleans staging directory without calling Complete.
            var completed = false;
            var refusedSettings = new NativeSettings(
                _ => new HttpClient(new StubUpdateHandler(manifestJson, () => new ByteArrayContent(payload))),
                _ => true,
                _ => null,
                _ => { },
                () => @"C:\Writable\Codex.exe",
                pubSpki);
            await refusedSettings.CheckUpdatesAsync();
            await refusedSettings.InstallUpdateAsync(
                new UpdateRestartHooks(() => false, () => { }, () => { completed = true; return Task.CompletedTask; }),
                relaunchInBackground: false,
                updatesRoot);
            Assert(!completed && !refusedSettings.IsInstalling && !Directory.EnumerateDirectories(updatesRoot).Any(),
                "Refused restart must clean staging directory.");

            // 5. Helper launch failure cancels restart reservation, deletes staging, and surfaces original error.
            var cancelledReservation = false;
            var helperFailSettings = new NativeSettings(
                _ => new HttpClient(new StubUpdateHandler(manifestJson, () => new ByteArrayContent(payload))),
                _ => true,
                _ => throw new IOException("helper start blocked"),
                _ => { },
                () => @"C:\Writable\Codex.exe",
                pubSpki);
            await helperFailSettings.CheckUpdatesAsync();
            await helperFailSettings.InstallUpdateAsync(
                new UpdateRestartHooks(() => true, () => cancelledReservation = true, () => { completed = true; return Task.CompletedTask; }),
                relaunchInBackground: false,
                updatesRoot);
            Assert(cancelledReservation && !completed && !helperFailSettings.IsInstalling,
                "Helper launch failure must release restart reservation and restore non-installing state.");
            Assert(helperFailSettings.UpdateError == "helper start blocked",
                "Helper launch failure must preserve the launch error message.");
            Assert(!Directory.EnumerateDirectories(updatesRoot).Any(),
                "Helper launch failure must clean staging directory.");

            // 6. Successful helper handoff transfers staging directory ownership and triggers Complete.
            var handoffCompleted = false;
            string[]? helperArgs = null;
            var handoffSettings = new NativeSettings(
                _ => new HttpClient(new StubUpdateHandler(manifestJson, () => new ByteArrayContent(payload))),
                _ => true,
                psi => { helperArgs = [.. psi.ArgumentList]; return new Process(); },
                _ => { },
                () => @"C:\Writable\Codex.exe",
                pubSpki);
            await handoffSettings.CheckUpdatesAsync();
            await handoffSettings.InstallUpdateAsync(
                new UpdateRestartHooks(() => true, () => Assert(false, "Successful handoff must not cancel."), () => { handoffCompleted = true; return Task.CompletedTask; }),
                relaunchInBackground: true,
                updatesRoot);
            Assert(handoffCompleted && helperArgs != null && helperArgs.Contains("--apply-update") && helperArgs.Contains("--background"),
                "Successful handoff must launch helper and invoke Complete.");
            Assert(Directory.EnumerateDirectories(updatesRoot).Count() == 1,
                "Successful handoff must leave staging directory for the launched helper.");
        }
        finally
        {
            if (Directory.Exists(root)) SecureFiles.DeleteOwnedDirectory(Path.GetTempPath(), root);
        }
    }

    private sealed class StubUpdateHandler(string manifestJson, Func<HttpContent> downloadContent) : HttpMessageHandler
    {
        protected override Task<HttpResponseMessage> SendAsync(HttpRequestMessage request, CancellationToken cancellationToken)
        {
            if (request.RequestUri?.AbsoluteUri == WindowsUpdater.FeedUrl)
            {
                return Task.FromResult(new HttpResponseMessage(HttpStatusCode.OK)
                {
                    Content = new StringContent(manifestJson, Encoding.UTF8, "application/json"),
                });
            }
            var content = downloadContent();
            content.Headers.ContentType = new MediaTypeHeaderValue("application/octet-stream");
            return Task.FromResult(new HttpResponseMessage(HttpStatusCode.OK) { Content = content });
        }
    }

    private sealed class CancelTriggeringStream(byte[] payload, Action triggerCancel) : Stream
    {
        private bool sentFirstChunk;
        public override bool CanRead => true;
        public override bool CanSeek => false;
        public override bool CanWrite => false;
        public override long Length => payload.Length;
        public override long Position { get => sentFirstChunk ? 1024 : 0; set => throw new NotSupportedException(); }
        public override void Flush() { }
        public override int Read(byte[] buffer, int offset, int count) => throw new NotSupportedException();
        public override long Seek(long offset, SeekOrigin origin) => throw new NotSupportedException();
        public override void SetLength(long value) => throw new NotSupportedException();
        public override void Write(byte[] buffer, int offset, int count) => throw new NotSupportedException();

        public override Task<int> ReadAsync(byte[] buffer, int offset, int count, CancellationToken cancellationToken) =>
            ReadAsync(buffer.AsMemory(offset, count), cancellationToken).AsTask();

        public override async ValueTask<int> ReadAsync(Memory<byte> buffer, CancellationToken cancellationToken = default)
        {
            if (!sentFirstChunk)
            {
                sentFirstChunk = true;
                var chunk = Math.Min(1024, buffer.Length);
                payload.AsMemory(0, chunk).CopyTo(buffer);
                return chunk;
            }
            triggerCancel();
            await Task.Delay(5000, cancellationToken);
            return 0;
        }
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
            var until = new DateTimeOffset(2099, 10, 17, 12, 0, 0, TimeSpan.Zero);
            var personalSub = new SubscriptionPresentation(
                "activeUntil", ActiveUntil: until, PlanType: "plus", IsActive: true,
                FetchedAt: time, StaleAfter: time.AddSeconds(600),
                RequiresUpdateImmediately: false, IsWaitingForRefresh: false, RefreshError: null,
                AutoRenew: "yes", PaymentDelinquent: "no",
                HistoricalActiveUntil: until, HistoricalLastChecked: time);
            var studioSub = new SubscriptionPresentation(
                "pending", RequiresUpdateImmediately: true, RefreshError: "Network timeout",
                HistoricalActiveUntil: until, HistoricalLastChecked: time);
            State = new([
                new(new(id, "Personal", "personal@example.test"), "P", new(83, time, 91, time.AddHours(-2), 2), null,
                    "loaded", new(until, time), SubscriptionView: personalSub),
                new(new(Guid.Parse("22222222-2222-2222-2222-222222222222"), "Studio", "studio@example.test"), "S", new(56, time.AddHours(1), 68, time.AddHours(-1)), null,
                    SubscriptionView: studioSub)
            ], id, new("simplifiedChinese"), false, false, true, null, new() {
                ["usage"] = "用量", ["resets"] = "重置于", ["reset_credits"] = "重置次数", ["unknown"] = "未知", ["left"] = "% 剩余", ["manage"] = "管理账号", ["settings"] = "设置", ["quit"] = "退出应用",
                ["subscription_live_pending"] = "订阅日期：待同步", ["subscription_live_until"] = "有效至 %@",
                ["subscription_live_active"] = "订阅已生效", ["subscription_live_inactive"] = "无有效订阅",
                ["subscription_live_free"] = "免费方案", ["subscription_live_needs_update"] = "待更新",
                ["subscription_live_source"] = "数据来源：ChatGPT 订阅服务", ["subscription_live_updated"] = "更新于 %@",
                ["subscription_live_plan"] = "方案：%@", ["subscription_live_status_active"] = "订阅状态：已生效",
                ["subscription_live_status_inactive"] = "订阅状态：未生效", ["subscription_live_renew_on"] = "自动续费：已开启",
                ["subscription_live_renew_off"] = "自动续费：未开启", ["subscription_live_renew_unknown"] = "自动续费：未知",
                ["subscription_live_delinquent_yes"] = "欠费状态：是", ["subscription_live_delinquent_no"] = "欠费状态：否",
                ["subscription_live_delinquent_unknown"] = "欠费状态：未知", ["subscription_live_last_success"] = "上次成功更新时间：%@",
                ["subscription_live_never_succeeded"] = "更新时间：尚未成功同步", ["subscription_live_stale_hint"] = "待更新。当前显示的是上次成功同步的结果。",
                ["subscription_live_refresh_failed"] = "刷新失败：%@", ["subscription_live_history"] = "历史登录快照（非实时）：有效至 %@；最近核验于 %@。",
                ["subscription_refresh_pending"] = "正在等待更新订阅信息。",
                ["accounts"] = "账号", ["drag_to_reorder"] = "拖动调整顺序", ["back"] = "返回", ["active"] = "当前", ["remove"] = "移除", ["add_account"] = "添加账号",
                ["sign_in_hint"] = "将打开浏览器进行 Codex 登录。", ["register_current_account"] = "登记当前登录账号",
                ["edit_account_note"] = "编辑账号备注", ["account_note"] = "账号备注",
                ["save_account_note"] = "保存备注", ["account_note_hint"] = "留空可移除备注。",
                ["settings_general"] = "通用", ["settings_updates"] = "软件更新", ["launch_at_login"] = "登录时自动启动",
                ["low_usage_reminder"] = "低额度提醒", ["low_usage_off"] = "关闭",
                ["settings_automation"] = "自动化", ["auto_reset"] = "到期前自动使用 reset",
                ["auto_reset_hint"] = "到期前 10 分钟自动使用所有已保存账号的 reset；应用须运行且电脑保持唤醒。", ["open_reset_log"] = "打开日志文件夹",
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
        public Task SetLowUsageThresholdAsync(int? threshold)
        {
            Commands.Add("lowUsageThreshold:" + threshold);
            return Task.CompletedTask;
        }
        public Task SetAccountNoteAsync(Guid accountID, string note)
        {
            var normalized = string.IsNullOrWhiteSpace(note) ? null : note.Trim();
            State = State with {
                Accounts = State.Accounts.Select(row => row.Profile.Id == accountID
                    ? row with { Profile = row.Profile with { Note = normalized }, Title = null } : row).ToArray(),
            };
            return Task.CompletedTask;
        }
        public Task CommandAsync(string command, Guid? accountID = null, bool? value = null, string? language = null,
            Guid? targetAccountID = null) {
            Commands.Add(command + ":" + (language ?? value?.ToString())); return Task.CompletedTask;
        }
    }
}
