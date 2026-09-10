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
            Assert(All<TextBlock>(window).Any(text => text.Text == client.State.PendingSwitch!.Message
                && text.Text.Contains(client.State.Text("native_api_storage_notice"))),
                "API retention and model notices must come from the shared prepared action.");
            Render(window, Path.Combine(output, "api-return-zh.png"));
            var confirm = All<Button>(window).Single(button => AutomationProperties.GetName(button) == "切换账号");
            confirm.RaiseEvent(new RoutedEventArgs(Button.ClickEvent));
            Assert(client.Commands.Last() == "confirmSwitch:", "Only confirmation executes a prepared switch.");
            window.Navigate("manage");
            Assert(All<Button>(window).Count(button => AutomationProperties.GetName(button) == "移除") == 2,
                "API authentication must not mark an old ChatGPT account as protected.");
            client.ProviderCommandAsync("openProviderEditor").GetAwaiter().GetResult();
            var providerWindow = new ProviderManagementWindow(client);
            Render(providerWindow, Path.Combine(output, "provider-add-zh.png"));
            All<PasswordBox>(providerWindow).Single().Password = "synthetic-only";
            All<Button>(providerWindow).Single(button => AutomationProperties.GetName(button) == client.State.Text("provider_fetch"))
                .RaiseEvent(new RoutedEventArgs(Button.ClickEvent));
            Render(providerWindow, Path.Combine(output, "provider-models-zh.png"));
            var search = All<TextBox>(providerWindow).Single(box => AutomationProperties.GetName(box) == client.State.Text("provider_search"));
            search.Text = "g5m";
            Assert(client.LastProviderQuery == "g5m", "Fuzzy queries are sent to the shared core unchanged.");
            Assert(All<CheckBox>(providerWindow).Count() == 1, "Render exactly the model IDs filtered by the shared core.");
            var makeDefault = All<Button>(providerWindow).Single(button => AutomationProperties.GetName(button) == client.State.Text("provider_set_default") + " gpt-5-mini");
            makeDefault.RaiseEvent(new RoutedEventArgs(Button.ClickEvent));
            All<TextBox>(providerWindow).Single(box => AutomationProperties.GetName(box) == "Thinking / effort").Text = "high";
            Assert(client.State.ProviderEditor?.Models.Single(row => row.Id == "gpt-5-mini").ReasoningEffort == "high", "Thinking changes go through the core.");
            Render(providerWindow, Path.Combine(output, "provider-fuzzy-default-zh.png"));
            All<Button>(providerWindow).Single(button => AutomationProperties.GetName(button) == client.State.Text("provider_save"))
                .RaiseEvent(new RoutedEventArgs(Button.ClickEvent));
            Assert(!providerWindow.IsVisible && client.LastProviderCommand == "closeProviderEditor", "Save closes the independent provider window and clears its editor.");
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
        // Snapshot notifications replace the view. Materialize its templates
        // before the synchronous harness queries the next control.
        if (parent is Window window) window.UpdateLayout();
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
        public string? LastProviderCommand { get; private set; }
        public string? LastProviderQuery { get; private set; }
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
                ["provider_setup_notice"] = "在服务商窗口中添加连接、选择和排序模型。此开关控制账号列表是否显示服务商，关闭后不改变当前服务商。", ["credential_in_use"] = "登录凭据使用中",
                ["switch_provider_body"] = "Codex Desktop 将使用此提供商重新启动。请先完成或停止正在运行的 Desktop 任务，并处理退出提示；无法正常退出时会停止切换。现有 CLI 会话保持运行。切换器不会选择模型或管理模型列表。请在 Desktop 中选择兼容模型；如果列表中没有，请先在 Codex 中配置。现有对话不会迁移。",
                ["native_api_storage_notice"] = "OpenAI API 登录将单独保存在本机，便于以后切回。已保存的 ChatGPT 账号与其分开保存。模型设置会保留，必要时请选择兼容模型。",
                ["return_account_model_notice"] = "模型设置将保留。如果自定义提供商使用了不同的模型 ID，请先在 Desktop 中选择 ChatGPT 支持的模型再发送消息。自定义模型目录也可能需要在 Codex 中更改。",
                ["provider_manager_title"] = "服务商",
                ["provider_new"] = "添加服务商",
                ["provider_saved"] = "已保存的服务商",
                ["provider_name"] = "名称",
                ["provider_name_placeholder"] = "例如：我的 API 服务",
                ["provider_key_placeholder"] = "输入 API Key",
                ["provider_keep_key"] = "留空保留已保存的密钥",
                ["provider_api_format"] = "接口格式",
                ["provider_responses_notice"] = "使用支持 Responses API 的服务。获取模型后勾选要启用的模型，点击星标设置默认模型。",
                ["provider_anthropic_notice"] = "Codex 暂不能直接使用 Anthropic Messages。请使用兼容 Responses 的网关来保存可用服务商；这里支持获取 Anthropic 模型列表。",
                ["provider_models"] = "模型",
                ["provider_fetch"] = "获取模型",
                ["provider_search"] = "模糊搜索模型 ID 或名称",
                ["provider_sort"] = "排序",
                ["provider_sort_custom"] = "自定义顺序",
                ["provider_manual_id"] = "或手动输入模型 ID",
                ["provider_add_model"] = "添加模型",
                ["provider_default_model"] = "默认模型",
                ["provider_set_default"] = "设为默认模型",
                ["provider_enable_model"] = "启用此模型",
                ["provider_move_up"] = "上移",
                ["provider_move_down"] = "下移",
                ["provider_effort_default"] = "跟随模型默认值（留空）",
                ["provider_effort_options"] = "服务商提供的选项",
                ["provider_effort_manual_hint"] = "模型列表没有提供 effort 选项。留空使用模型默认值，也可填写服务商文档支持的 effort 值。",
                ["provider_effort_advertised_hint"] = "选择服务商提供的选项，或留空使用模型默认值。",
                ["provider_fetch_hint"] = "获取模型或手动添加 ID。勾选列表和排序用于本切换器。",
                ["provider_no_match"] = "没有匹配的模型。",
                ["provider_storage_notice"] = "API Key 保存到本机受文件权限保护的 Codex 配置。保存后添加服务商，准备好后再切换。",
                ["provider_save"] = "保存服务商",
                ["provider_invalid_url"] = "请输入 HTTPS API Base URL，不包含用户名、密码、查询参数或片段；本地地址可用 HTTP。",
                ["provider_invalid_key"] = "请输入 API Key，或保留有效的已保存密钥。",
                ["provider_empty_name"] = "请输入服务商名称。",
                ["provider_no_models"] = "服务返回的模型列表为空，可以手动输入模型 ID。",
                ["provider_select_default"] = "请启用一个模型并将其设为默认模型。",
                ["provider_edit_active"] = "请先切换到其他账号或服务商，再编辑当前服务商。",
                ["provider_invalid_response"] = "服务返回的模型或配置数据格式无效。",
                ["provider_redirect_refused"] = "模型接口发生重定向。请填写最终 API Base URL，以确保密钥只发送到指定服务器。",
                ["provider_pagination_failed"] = "模型分页未正常推进，列表未导入。",
                ["provider_fetch_cancelled"] = "已取消获取模型。",
                ["provider_switched_reopen_message"] = "所选提供商已经生效，但 Codex Desktop 未能重新打开。请手动打开 Codex 继续使用。"
            }, [], "openai", "chatgpt", null, [], null);
        }
        public async Task CommandAsync(string command, Guid? accountID = null, bool? value = null, string? language = null, string? providerID = null) {
            Commands.Add(command + ":" + value);
            LastProviderID = providerID;
            if (command == "cancelSwitch" && PendingCancellation != null) await PendingCancellation.Task;
            if (command == "prepareAccountSwitch") {
                var row = State.Accounts.Single(row => row.Profile.Id == accountID);
                State = State with { PendingSwitch = row.IsActive ? null : new(accountID, null, "切换到 " + row.Profile.DisplayName + "？",
                    State.Text("switch_body") + (State.AuthenticationKind == "apiKey"
                        ? "\n\n" + State.Text("return_account_model_notice") + "\n\n" + State.Text("native_api_storage_notice") : ""), "切换账号") };
            } else if (command == "prepareProviderSwitch") {
                State = State with { PendingSwitch = new(null, providerID, "切换提供商？", State.Text("switch_provider_body"), "切换提供商") };
            } else if (command is "cancelSwitch" or "confirmSwitch") State = State with { PendingSwitch = null };
            Changed?.Invoke();
        }
        public Task ProviderCommandAsync(string command, ProviderEditorCommand? editor = null) {
            LastProviderCommand = command;
            if (command == "openProviderEditor") {
                State = State with { ProviderEditor = new("switcher_synthetic", "示例服务商", "https://api.example.test/v1", "responses", false,
                    [], null, "", "custom", [], false, null, false) };
            } else if (command == "closeProviderEditor") State = State with { ProviderEditor = null };
            else if (State.ProviderEditor is { } current) {
                if (command == "fetchProviderModels") current = current with {
                    Models = [new("vendor-large", "Vendor Large", false, [], null), new("gpt-5-mini", "GPT 5 Mini", false, ["low", "high"], null)],
                    VisibleModelIDs = ["vendor-large", "gpt-5-mini"] };
                if (command == "searchProviderModels") {
                    LastProviderQuery = editor?.Query;
                    current = current with { Query = editor?.Query ?? "", VisibleModelIDs = editor?.Query == "g5m" ? ["gpt-5-mini"] : current.Models.Select(row => row.Id).ToArray() };
                }
                if (command == "chooseProviderDefaultModel") current = current with {
                    DefaultModelID = editor?.ModelID, Models = current.Models.Select(row => row.Id == editor?.ModelID ? row with { IsEnabled = true } : row).ToArray() };
                if (command == "setProviderReasoning") current = current with {
                    Models = current.Models.Select(row => row.Id == current.DefaultModelID ? row with { ReasoningEffort = editor?.Effort } : row).ToArray() };
                if (command == "saveProvider") current = current with { DidSave = true };
                State = State with { ProviderEditor = current };
            }
            Changed?.Invoke();
            return Task.CompletedTask;
        }
    }
}
