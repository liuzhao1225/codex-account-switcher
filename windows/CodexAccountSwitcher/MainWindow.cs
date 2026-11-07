using System;
using System.Globalization;
using System.Linq;
using System.Threading.Tasks;
using System.Windows;
using System.Windows.Automation;
using System.Windows.Controls;
using System.Windows.Controls.Primitives;
using System.Windows.Input;
using System.Windows.Media;
using CodexAccountSwitcher.Core;

namespace CodexAccountSwitcher;

public sealed class MainWindow : Window
{
    private const string AccountDragFormat = "CodexAccountSwitcher.AccountID";
    private readonly IAccountClient client;
    private readonly NativeSettings native;
    private string page = "accounts";
    private AccountRow? target;
    private string? localError;
    private bool closingForExit;
    public bool IsBusy => client.State.IsMutating;
    public string CurrentPage => page;
    private AccountSnapshot State => client.State;
    private string T(string key) => State.Text(key);
    private Brush B(string key) => (Brush)FindResource(key);

    public MainWindow(IAccountClient client, NativeSettings? native = null)
    {
        this.client = client; this.native = native ?? new NativeSettings();
        Icon = System.Windows.Media.Imaging.BitmapFrame.Create(App.IconUri);
        Title = "Codex Account Switcher"; Width = 440; SizeToContent = SizeToContent.Height;
        WindowStyle = WindowStyle.SingleBorderWindow; ResizeMode = ResizeMode.CanMinimize;
        Background = B("Surface"); ShowInTaskbar = true;
        WindowStartupLocation = WindowStartupLocation.CenterScreen;
        MaxHeight = SystemParameters.WorkArea.Height - 24;
        client.Changed += Render; this.native.Changed += Render;
        PreviewKeyDown += (_, e) => { if (e.Key == Key.Escape && !IsBusy && page != "accounts") { Navigate(page == "apiKey" ? "manage" : "accounts"); e.Handled = true; } };
        Closing += (_, e) => {
            if (closingForExit) return;
            e.Cancel = true;
            Hide();
        };
        Closed += (_, _) => { client.Changed -= Render; this.native.Changed -= Render; };
        Render();
    }

    public void CloseForExit() { closingForExit = true; Close(); }

    public void OpenWindow()
    {
        if (State.IsAddingAccount) Navigate("manage");
        Show();
        if (WindowState == WindowState.Minimized) WindowState = WindowState.Normal;
        Activate();
        _ = Run("refresh");
    }
    public void Navigate(string destination) { page = destination; target = null; localError = null; Render(); }
    private async Task Run(string command, Guid? id = null, bool? value = null, string? language = null,
        string? displayName = null, string? apiKey = null, Guid? targetAccountID = null)
    {
        try { await client.CommandAsync(command, id, value, language, displayName, apiKey, targetAccountID); }
        catch (Exception ex) { localError = ex.Message; Render(); }
    }
    private TextBlock Text(string text, double size = 13, bool muted = false, bool bold = false) => new() {
        Text = text, FontSize = size, Foreground = B(muted ? "Muted" : "Ink"),
        FontWeight = bold ? FontWeights.SemiBold : FontWeights.Normal,
        VerticalAlignment = VerticalAlignment.Center, TextTrimming = TextTrimming.CharacterEllipsis
    };
    private Button Button(string label, Action action, string? glyph = null, bool left = false)
    {
        var content = new StackPanel { Orientation = Orientation.Horizontal, HorizontalAlignment = left ? HorizontalAlignment.Left : HorizontalAlignment.Center };
        if (glyph != null) content.Children.Add(new TextBlock { Text = glyph, FontFamily = new FontFamily("Segoe MDL2 Assets"), Margin = new Thickness(0, 0, label.Length > 0 ? 7 : 0, 0), VerticalAlignment = VerticalAlignment.Center });
        if (label.Length > 0) content.Children.Add(new TextBlock { Text = label, FontSize = 13, VerticalAlignment = VerticalAlignment.Center });
        var button = new Button { Content = content, IsEnabled = !IsBusy, Padding = new Thickness(12, 6, 12, 6), MinHeight = 32, MinWidth = 32 };
        AutomationProperties.SetName(button, label); button.Click += (_, _) => action(); return button;
    }
    private Border Rule() => new() { Height = 1, Background = B("Line") };
    private Grid Pair(UIElement left, UIElement right)
    {
        var grid = new Grid(); grid.ColumnDefinitions.Add(new ColumnDefinition()); grid.ColumnDefinitions.Add(new ColumnDefinition { Width = GridLength.Auto });
        Grid.SetColumn(right, 1); grid.Children.Add(left); grid.Children.Add(right); return grid;
    }

    private void Render()
    {
        var body = new StackPanel();
        if (State.Error != null || localError != null) {
            var message = Text(localError ?? State.Error!, 11, muted: true); message.TextWrapping = TextWrapping.Wrap;
            var box = Pair(message, Button("×", () => { localError = null; _ = Run("dismissError"); Render(); }));
            box.Margin = new Thickness(12, 8, 12, 10); body.Children.Add(box); body.Children.Add(Rule());
        }
        if (page == "accounts") {
            var commands = new StackPanel { Orientation = Orientation.Horizontal };
            commands.Children.Add(Button(T("manage"), () => Navigate("manage"), "\uE716"));
            var settings = Button("", () => Navigate("settings"), "\uE713");
            settings.Margin = new Thickness(8, 0, 0, 0); settings.ToolTip = T("settings");
            AutomationProperties.SetName(settings, T("settings"));
            if (native.UpdatePage != null) {
                var glyph = (UIElement)settings.Content; settings.Content = null;
                var indicator = new Grid(); indicator.Children.Add(glyph);
                indicator.Children.Add(new System.Windows.Shapes.Ellipse { Width = 5, Height = 5, Fill = B("Accent"),
                    HorizontalAlignment = HorizontalAlignment.Right, VerticalAlignment = VerticalAlignment.Top, Margin = new Thickness(0, -3, -4, 0) });
                settings.Content = indicator;
            }
            commands.Children.Add(settings);
            var heading = Pair(Text(T("accounts"), 22, bold: true), commands);
            heading.Margin = new Thickness(24, 20, 24, 18); body.Children.Add(heading);
        } else {
            var header = new StackPanel { Orientation = Orientation.Horizontal, Margin = new Thickness(24, 20, 24, 18) };
            header.Children.Add(Button("", () => Navigate(page is "remove" or "apiKey" ? "manage" : "accounts"), "\uE72B"));
            AutomationProperties.SetName(header.Children[0], T("back"));
            var title = target != null && page is "switch" or "remove"
                ? T(page + "_title").Replace("%@", target.Profile.DisplayName)
                : T(page == "settings" ? "settings" : page == "apiKey" ? "add_api_key" : "accounts");
            var heading = Text(title, 20, bold: true); heading.Margin = new Thickness(12, 0, 0, 0); header.Children.Add(heading);
            body.Children.Add(header);
        }
        if (page is "switch" or "remove") Confirmation(body);
        else if (page == "apiKey") APIKeyForm(body);
        else if (page == "settings") Settings(body);
        else Accounts(body, page == "manage");
        Content = new Border { Background = B("Surface"),
            Child = new ScrollViewer { Content = body, VerticalScrollBarVisibility = ScrollBarVisibility.Auto, HorizontalScrollBarVisibility = ScrollBarVisibility.Disabled } };
    }

    private void Accounts(StackPanel body, bool manage)
    {
        if (!manage && !State.ActiveIdentityConfirmed) {
            var warning = new StackPanel { Margin = new Thickness(12, 8, 12, 4) };
            warning.Children.Add(Text(T("active_unconfirmed"), 11, muted: true));
            warning.Children.Add(Button(T("manage"), () => Navigate("manage"), left: true)); body.Children.Add(warning);
        }
        var list = new StackPanel();
        if (manage && State.Accounts.Length > 1) {
            var hint = Text(T("reorder_accounts"), 11, muted: true);
            hint.Margin = new Thickness(14, 10, 14, 2);
            list.Children.Add(hint);
        }
        foreach (var row in State.Accounts) {
            var avatar = new Border { Width = 36, Height = 36, CornerRadius = new CornerRadius(18), Background = B("Avatar"),
                Child = Text(row.Initials, 12, bold: true) };
            ((TextBlock)avatar.Child).HorizontalAlignment = HorizontalAlignment.Center;
            var details = new StackPanel { VerticalAlignment = VerticalAlignment.Center };
            var active = row.Profile.Id == State.ActiveAccountID;
            var title = string.IsNullOrEmpty(row.Profile.Email) ? row.Profile.DisplayName : row.Profile.Email;
            var name = Text(title, 14, bold: true);
            name.ToolTip = title;
            if (manage) {
                details.Children.Add(name);
            } else {
                details.Children.Add(name);
                if (row.Usage is { } usage) {
                    if (State.Settings.ShowsFiveHourUsage && usage.FiveHourRemainingPercent is { } five && usage.FiveHourResetsAt is { } time)
                        details.Children.Add(UsageLine(T("five_hour"), five, Reset(time, false)));
                    details.Children.Add(UsageLine(T(State.Settings.ShowsFiveHourUsage ? "weekly" : "usage"), usage.RemainingPercent,
                        null));
                    details.ToolTip = Reset(usage.ResetsAt) + (row.UsageError is null ? "" : "\n" + row.UsageError);
                } else { var missing = Text(row.UsageStatus == "idle" ? T("usage") + " —" : T("usage_unavailable"), 10.5, muted: true); missing.ToolTip = row.UsageError; details.Children.Add(missing); }
            }
            var grid = new Grid { MinHeight = manage ? 40 : 54 };
            grid.ColumnDefinitions.Add(new ColumnDefinition { Width = new GridLength(48) }); grid.ColumnDefinitions.Add(new ColumnDefinition());
            grid.Children.Add(avatar); Grid.SetColumn(details, 1); grid.Children.Add(details);
            grid.ColumnDefinitions.Add(new ColumnDefinition { Width = GridLength.Auto });
            if (manage) {
                var handle = Text("☰", 17, muted: true);
                handle.Width = 26;
                handle.Cursor = Cursors.SizeAll;
                handle.ToolTip = T("drag_to_reorder");
                AutomationProperties.SetName(handle, T("drag_to_reorder"));
                handle.MouseMove += (_, e) => {
                    if (!IsBusy && !State.IsAddingAccount && e.LeftButton == MouseButtonState.Pressed)
                        DragDrop.DoDragDrop(handle, new DataObject(AccountDragFormat, row.Profile.Id.ToString()), DragDropEffects.Move);
                };
                grid.ColumnDefinitions.Insert(0, new ColumnDefinition { Width = new GridLength(26) });
                Grid.SetColumn(avatar, 1);
                Grid.SetColumn(details, 2);
                UIElement action = active ? Text(T("active"), 11, muted: true) : Button("", () => { target = row; page = "remove"; Render(); }, "\uE74D");
                AutomationProperties.SetName(action, active ? T("active") : T("remove")); Grid.SetColumn(action, 3); grid.Children.Add(action);
                Grid.SetColumn(handle, 0); grid.Children.Add(handle);
                var item = new Border { Padding = new Thickness(14, 9, 14, 9), Child = grid, AllowDrop = true };
                item.DragOver += (_, e) => {
                    e.Effects = !IsBusy && !State.IsAddingAccount && e.Data.GetDataPresent(AccountDragFormat)
                        && Guid.TryParse(e.Data.GetData(AccountDragFormat) as string, out var source)
                        && source != row.Profile.Id && State.Accounts.Any(account => account.Profile.Id == source)
                        ? DragDropEffects.Move : DragDropEffects.None;
                    e.Handled = true;
                };
                item.Drop += (_, e) => {
                    if (!IsBusy && !State.IsAddingAccount && e.Data.GetDataPresent(AccountDragFormat)
                        && Guid.TryParse(e.Data.GetData(AccountDragFormat) as string, out var source)
                        && source != row.Profile.Id && State.Accounts.Any(account => account.Profile.Id == source))
                        _ = Run("move", source, targetAccountID: row.Profile.Id);
                    e.Handled = true;
                };
                list.Children.Add(item);
            } else {
                var state = Text(active ? T("active") : "›", active ? 11 : 20, muted: !active, bold: active);
                state.Margin = new Thickness(12, 0, 0, 0); Grid.SetColumn(state, 2); grid.Children.Add(state);
                var button = new Button { Content = grid, Style = (Style)FindResource("AccountRow"), Background = active ? B("Selected") : Brushes.Transparent, IsEnabled = !IsBusy };
                AutomationProperties.SetName(button, title);
                button.Click += (_, _) => { if (!active) { target = row; page = "switch"; Render(); } };
                list.Children.Add(button);
            }
        }
        if (State.Accounts.Length == 0) { var empty = Text(T("no_accounts"), 12, muted: true); empty.Margin = new Thickness(12, 24, 12, 24); list.Children.Add(empty); }
        body.Children.Add(new Border { Margin = new Thickness(24, 0, 24, 20), BorderBrush = B("Line"), BorderThickness = new Thickness(1),
            Background = B("ListSurface"), CornerRadius = new CornerRadius(10), Child = list });
        if (manage) {
            var actions = new StackPanel { Margin = new Thickness(24, 0, 24, 24) };
            var add = Button(T(State.IsAddingAccount ? "cancel_add_account" : "add_account"), () => _ = Run(State.IsAddingAccount ? "cancelAdd" : "add"), State.IsAddingAccount ? "\uE711" : "\uE710");
            var addRow = new StackPanel { Orientation = Orientation.Horizontal };
            addRow.Children.Add(add);
            var addKey = Button(T("add_api_key"), () => Navigate("apiKey"));
            addKey.Margin = new Thickness(8, 0, 0, 0);
            addRow.Children.Add(addKey);
            actions.Children.Add(addRow);
            var hint = Text(T(State.IsAddingAccount ? "sign_in_pending_hint" : "sign_in_hint"), 11, muted: true);
            hint.TextWrapping = TextWrapping.Wrap;
            hint.Margin = new Thickness(0, 8, 0, 14);
            actions.Children.Add(hint);
            var register = Button(T("register_current_account"), () => _ = Run("register"));
            register.IsEnabled &= !State.IsAddingAccount; register.HorizontalAlignment = HorizontalAlignment.Left;
            actions.Children.Add(register); body.Children.Add(actions);
        }
    }

    private void APIKeyForm(StackPanel body)
    {
        var form = new StackPanel { Margin = new Thickness(24, 0, 24, 24) };
        var name = new TextBox { Margin = new Thickness(0, 6, 0, 14), MaxLength = 100,
            MinHeight = 34, Padding = new Thickness(8, 5, 8, 5), Background = B("ListSurface"),
            BorderBrush = B("Line"), BorderThickness = new Thickness(1) };
        AutomationProperties.SetName(name, T("api_key_name"));
        form.Children.Add(Text(T("api_key_name")));
        form.Children.Add(name);
        var key = new PasswordBox { Margin = new Thickness(0, 6, 0, 14),
            MinHeight = 34, Padding = new Thickness(8, 5, 8, 5), Background = B("ListSurface"),
            BorderBrush = B("Line"), BorderThickness = new Thickness(1) };
        AutomationProperties.SetName(key, T("api_key_secret"));
        form.Children.Add(Text(T("api_key_secret")));
        form.Children.Add(key);
        var hint = Text(T("api_key_hint"), 11, muted: true);
        hint.TextWrapping = TextWrapping.Wrap;
        hint.Margin = new Thickness(0, 0, 0, 14);
        form.Children.Add(hint);
        var validation = Text("", 11, muted: true);
        validation.Foreground = B("Error");
        validation.Margin = new Thickness(0, 0, 0, 8);
        form.Children.Add(validation);
        var save = Button(T("save_api_key"), () => {
            var label = name.Text.Trim();
            var secret = key.Password.Trim();
            if (label.Length == 0 || secret.Length == 0 || secret.Any(char.IsWhiteSpace)) {
                validation.Text = T("api_key_invalid"); return;
            }
            key.Clear();
            Navigate("manage");
            _ = Run("addAPIKey", displayName: label, apiKey: secret);
        });
        var buttons = new StackPanel { Orientation = Orientation.Horizontal, HorizontalAlignment = HorizontalAlignment.Right };
        buttons.Children.Add(Button(T("cancel"), () => Navigate("manage")));
        save.Margin = new Thickness(8, 0, 0, 0);
        save.IsDefault = true;
        buttons.Children.Add(save);
        form.Children.Add(buttons);
        body.Children.Add(form);
    }

    private string Reset(DateTimeOffset date, bool includeDate = true) => T("resets") + " " + date.ToLocalTime().ToString(includeDate ? "MMM d HH:mm" : "HH:mm", CultureInfo.CurrentCulture);
    private Grid UsageLine(string title, int percent, string? reset)
    {
        var grid = new Grid { Margin = new Thickness(0, 5, 0, 0) };
        grid.ColumnDefinitions.Add(new ColumnDefinition { Width = GridLength.Auto }); grid.ColumnDefinitions.Add(new ColumnDefinition()); grid.ColumnDefinitions.Add(new ColumnDefinition { Width = GridLength.Auto });
        grid.Children.Add(Text(title, 10.5, muted: true));
        var track = new Grid { Height = 4, Margin = new Thickness(7, 0, 7, 0), VerticalAlignment = VerticalAlignment.Center };
        track.Children.Add(new Border { Background = B("Line"), CornerRadius = new CornerRadius(1) });
        var fill = new Border { Background = B("Accent"), CornerRadius = new CornerRadius(1), HorizontalAlignment = HorizontalAlignment.Left };
        track.SizeChanged += (_, _) => fill.Width = track.ActualWidth * percent / 100.0; track.Children.Add(fill);
        AutomationProperties.SetName(track, title + " " + percent + "%"); Grid.SetColumn(track, 1); grid.Children.Add(track);
        var remaining = Text(reset == null ? percent + T("left") : percent + "%  " + reset, reset == null ? 10.5 : 9.5, muted: true);
        Grid.SetColumn(remaining, 2); grid.Children.Add(remaining); return grid;
    }
    private void Confirmation(StackPanel body)
    {
        if (target == null) return;
        var content = new StackPanel { Margin = new Thickness(20, 0, 20, 20) };
        var copy = T(page == "switch" ? "switch_body_windows" : "remove_body").Replace("这台 Mac", "这台电脑").Replace("this Mac", "this PC");
        var text = Text(copy, 13, muted: true); text.TextWrapping = TextWrapping.Wrap; text.Margin = new Thickness(0, 0, 0, 14); content.Children.Add(text);
        var buttons = new StackPanel { Orientation = Orientation.Horizontal, HorizontalAlignment = HorizontalAlignment.Right };
        buttons.Children.Add(Button(T("cancel"), () => Navigate(page == "remove" ? "manage" : "accounts")));
        var command = page; var id = target.Profile.Id;
        var confirm = Button(T(command), () => { Navigate(command == "remove" ? "manage" : "accounts"); _ = Run(command, id); });
        confirm.Margin = new Thickness(8, 0, 0, 0); confirm.BorderBrush = B("Accent"); confirm.IsDefault = true; buttons.Children.Add(confirm); content.Children.Add(buttons); body.Children.Add(content);
    }
    private void Settings(StackPanel body)
    {
        var settings = new StackPanel { Margin = new Thickness(20, 0, 20, 20) };
        settings.Children.Add(Text(T("settings_general"), 14, bold: true));
        void Toggle(string title, bool current, Action<bool> action) {
            var toggle = new CheckBox { IsChecked = current, Content = title, FontSize = 13, VerticalAlignment = VerticalAlignment.Center, Margin = new Thickness(0, 9, 0, 9) };
            AutomationProperties.SetName(toggle, title); toggle.Click += (_, _) => { try { action(toggle.IsChecked == true); } catch (Exception ex) { localError = ex.Message; Render(); } };
            settings.Children.Add(toggle);
        }
        Toggle(T("launch_at_login"), native.LaunchAtLogin, value => native.LaunchAtLogin = value);
        Toggle(T("show_menu_bar_percentage").Replace("菜单栏", "托盘").Replace("Menu Bar", "System Tray"), State.Settings.ShowsMenuBarPercentage, value => _ = Run("percentage", value: value));
        var usageWindows = new[] { "fiveHour", "weekly" };
        var usageWindow = new ComboBox { Width = 160, VerticalAlignment = VerticalAlignment.Center,
            ItemsSource = new[] { T("five_hour"), T("weekly") },
            SelectedIndex = State.Settings.StatusBarUsageWindow == "fiveHour" ? 0 : 1 };
        usageWindow.SelectionChanged += (_, _) => { if (usageWindow.SelectedIndex >= 0) _ = Run("statusBarUsageWindow", language: usageWindows[usageWindow.SelectedIndex]); };
        var usageWindowRow = Pair(Text(T("status_bar_usage_window")), usageWindow);
        usageWindowRow.Height = 48; settings.Children.Add(usageWindowRow);
        Toggle(T("show_five_hour_usage"), State.Settings.ShowsFiveHourUsage, value => _ = Run("fiveHour", value: value));
        var languages = new[] { "system", "english", "simplifiedChinese" };
        var language = new ComboBox { Width = 160, VerticalAlignment = VerticalAlignment.Center, ItemsSource = new[] { T("system_default"), T("english"), T("simplified_chinese") }, SelectedIndex = Array.IndexOf(languages, State.Settings.Language) };
        language.SelectionChanged += (_, _) => { if (language.SelectedIndex >= 0) _ = Run("language", language: languages[language.SelectedIndex]); };
        var languageRow = Pair(Text(T("language")), language); languageRow.Height = 48; settings.Children.Add(languageRow);
        var experimentHeading = Text(T("settings_automation"), 14, bold: true); experimentHeading.Margin = new Thickness(0, 20, 0, 0); settings.Children.Add(experimentHeading);
        Toggle(T("auto_reset"), State.Settings.AutoResetEnabled, value => _ = Run("autoReset", value: value));
        var experimentHint = Text(T("auto_reset_hint"), 10.5, muted: true); experimentHint.TextWrapping = TextWrapping.Wrap; settings.Children.Add(experimentHint);
        settings.Children.Add(Button(T("open_reset_log"), () => {
            try {
                var directory = System.IO.Path.Combine(Environment.GetFolderPath(Environment.SpecialFolder.LocalApplicationData), "Codex Account Switcher");
                System.Diagnostics.Process.Start(new System.Diagnostics.ProcessStartInfo(directory) { UseShellExecute = true });
            } catch (Exception ex) { localError = ex.Message; Render(); }
        }));
        var heading = Text(T("settings_updates"), 14, bold: true); heading.Margin = new Thickness(0, 20, 0, 0); settings.Children.Add(heading);
        Toggle(T("automatically_check_updates"), native.AutomaticallyCheckUpdates, value => native.AutomaticallyCheckUpdates = value);
        var hint = Text(T(native.UpdateError ?? "update_check_hint"), 10.5, muted: true); hint.Margin = new Thickness(0, 0, 0, 12); hint.TextWrapping = TextWrapping.Wrap; settings.Children.Add(hint); settings.Children.Add(Rule());
        var check = Button(T(native.UpdatePage == null ? "check_for_updates" : "update_action"), async () => { if (native.UpdatePage != null) native.OpenUpdate(); else await native.CheckUpdatesAsync(); }); check.IsEnabled = !native.IsChecking;
        var version = Pair(Text(T("current_version").Replace("%@", native.Version), 12), check); version.Margin = new Thickness(0, 12, 0, 0); settings.Children.Add(version); body.Children.Add(settings);
    }
}
