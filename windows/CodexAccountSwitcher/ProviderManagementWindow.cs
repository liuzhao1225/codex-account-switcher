using System;
using System.Linq;
using System.Threading.Tasks;
using System.Windows;
using System.Windows.Automation;
using System.Windows.Controls;
using System.Windows.Media;
using CodexAccountSwitcher.Core;

namespace CodexAccountSwitcher;

/// Native controls only: discovery, search, ordering and persistence are Swift commands.
public sealed class ProviderManagementWindow : Window
{
    private readonly IAccountClient client;
    private readonly TextBox name = new(), baseURL = new(), query = new(), manualID = new(), effort = new();
    private readonly PasswordBox key = new();
    private readonly ComboBox format = new(), sort = new(), saved = new(), advertisedEffort = new();
    private readonly StackPanel models = new();
    private readonly TextBlock error = new(), hint = new(), defaultModel = new(), effortHint = new();
    private readonly Button fetch, save, addModel, addProvider;
    private string? editorID;
    private string? selectedModelID;
    private bool updating;
    private string? localError;
    private ProviderEditorState? State => client.State.ProviderEditor;
    private bool Busy => client.State.IsMutating || State?.IsBusy == true;
    private string T(string key) => client.State.Text(key);

    public ProviderManagementWindow(IAccountClient client)
    {
        this.client = client;
        Title = T("provider_manager_title"); Width = 730; Height = 820; MinWidth = 640; MinHeight = 620;
        MaxHeight = SystemParameters.WorkArea.Height - 24;
        WindowStartupLocation = WindowStartupLocation.CenterScreen;
        Background = (Brush)FindResource("Surface");
        var root = new DockPanel();
        var header = new DockPanel { Margin = new Thickness(22) };
        addProvider = Action(T("provider_new"), async () => await Run("openProviderEditor"));
        DockPanel.SetDock(addProvider, Dock.Right); header.Children.Add(addProvider);
        saved.Width = 190; saved.DisplayMemberPath = "DisplayName"; saved.Margin = new Thickness(12, 0, 12, 0);
        saved.ToolTip = T("provider_saved"); AutomationProperties.SetName(saved, T("provider_saved"));
        DockPanel.SetDock(saved, Dock.Right); header.Children.Add(saved);
        header.Children.Add(Label(T("provider_manager_title"), 20)); DockPanel.SetDock(header, Dock.Top); root.Children.Add(header);
        var footer = new DockPanel { Margin = new Thickness(22, 14, 22, 18) };
        var actions = new StackPanel { Orientation = Orientation.Horizontal };
        actions.Children.Add(Action(T("cancel"), () => { Close(); return Task.CompletedTask; }));
        save = Action(T("provider_save"), async () => {
            await Run("saveProvider", new(Connection: Connection()));
            if (State?.DidSave == true) Close();
        }); save.Margin = new Thickness(10, 0, 0, 0); actions.Children.Add(save);
        DockPanel.SetDock(actions, Dock.Right); footer.Children.Add(actions);
        var storage = Label(T("provider_storage_notice"), 11); storage.Margin = new Thickness(0, 0, 16, 0); footer.Children.Add(storage);
        DockPanel.SetDock(footer, Dock.Bottom); root.Children.Add(footer);
        var body = new StackPanel { Margin = new Thickness(22, 0, 22, 0) };
        void Field(string title, Control control) {
            var grid = new Grid { Margin = new Thickness(0, 0, 0, 12) };
            grid.ColumnDefinitions.Add(new ColumnDefinition { Width = new GridLength(95) }); grid.ColumnDefinitions.Add(new ColumnDefinition());
            grid.Children.Add(Label(title)); Grid.SetColumn(control, 1); grid.Children.Add(control);
            control.MinHeight = 32; control.VerticalContentAlignment = VerticalAlignment.Center; control.Padding = new Thickness(8, 4, 8, 4);
            AutomationProperties.SetName(control, title); body.Children.Add(grid);
        }
        Field(T("provider_name"), name); Field("Base URL", baseURL); Field("API Key", key);
        format.ItemsSource = new[] { "OpenAI Responses", "Anthropic Messages" }; format.SelectedIndex = 0;
        Field(T("provider_api_format"), format);
        hint.TextWrapping = TextWrapping.Wrap; hint.FontSize = 12; hint.Margin = new Thickness(0, 0, 0, 16); body.Children.Add(hint);
        var modelHeader = new DockPanel { Margin = new Thickness(0, 0, 0, 12) };
        fetch = Action(T("provider_fetch"), async () => await Run("fetchProviderModels", new(Connection: Connection())));
        DockPanel.SetDock(fetch, Dock.Right); modelHeader.Children.Add(fetch); modelHeader.Children.Add(Label(T("provider_models"), 17)); body.Children.Add(modelHeader);
        var searchRow = new DockPanel { Margin = new Thickness(0, 0, 0, 10) };
        sort.ItemsSource = new[] { T("provider_sort_custom"), "A → Z", "Z → A" }; sort.SelectedIndex = 0; sort.Width = 145; sort.Margin = new Thickness(12, 0, 0, 0);
        AutomationProperties.SetName(sort, T("provider_sort")); DockPanel.SetDock(sort, Dock.Right); searchRow.Children.Add(sort);
        query.MinHeight = 32; query.Padding = new Thickness(8, 4, 8, 4); query.ToolTip = T("provider_search"); AutomationProperties.SetName(query, T("provider_search"));
        searchRow.Children.Add(query); body.Children.Add(searchRow);
        body.Children.Add(new Border { BorderBrush = (Brush)FindResource("Line"), BorderThickness = new Thickness(1), CornerRadius = new CornerRadius(6),
            Child = new ScrollViewer { Content = models, MaxHeight = 280, VerticalScrollBarVisibility = ScrollBarVisibility.Auto } });
        var manual = new DockPanel { Margin = new Thickness(0, 10, 0, 16) };
        addModel = Action(T("provider_add_model"), async () => {
            await Run("addProviderModel", new(Connection: Connection(), ModelID: manualID.Text));
            manualID.Clear(); query.Clear();
        }); DockPanel.SetDock(addModel, Dock.Right); manual.Children.Add(addModel);
        manualID.Padding = new Thickness(8, 4, 8, 4); manualID.Margin = new Thickness(0, 0, 10, 0); manualID.ToolTip = T("provider_manual_id");
        AutomationProperties.SetName(manualID, T("provider_manual_id")); manual.Children.Add(manualID); body.Children.Add(manual);
        defaultModel.FontWeight = FontWeights.SemiBold; defaultModel.TextWrapping = TextWrapping.Wrap; defaultModel.Margin = new Thickness(0, 0, 0, 10); body.Children.Add(defaultModel);
        var reasoning = new DockPanel { Margin = new Thickness(0, 0, 0, 8) };
        var reasoningLabel = Label("Thinking / effort"); reasoningLabel.Width = 120; reasoning.Children.Add(reasoningLabel);
        advertisedEffort.Width = 150; advertisedEffort.Margin = new Thickness(10, 0, 0, 0); DockPanel.SetDock(advertisedEffort, Dock.Right); reasoning.Children.Add(advertisedEffort);
        effort.Padding = new Thickness(8, 4, 8, 4); effort.ToolTip = T("provider_effort_default"); AutomationProperties.SetName(effort, "Thinking / effort"); reasoning.Children.Add(effort); body.Children.Add(reasoning);
        effortHint.TextWrapping = TextWrapping.Wrap; effortHint.FontSize = 11; body.Children.Add(effortHint);
        error.TextWrapping = TextWrapping.Wrap; error.Foreground = Brushes.Firebrick; error.Margin = new Thickness(0, 14, 0, 8); body.Children.Add(error);
        root.Children.Add(new ScrollViewer { Content = body, VerticalScrollBarVisibility = ScrollBarVisibility.Auto }); Content = root;
        query.TextChanged += async (_, _) => { if (!updating) await Run("searchProviderModels", new(Query: query.Text)); };
        sort.SelectionChanged += async (_, _) => { if (!updating && sort.SelectedIndex >= 0) await Run("sortProviderModels", new(Sort: new[] { "custom", "nameAscending", "nameDescending" }[sort.SelectedIndex])); };
        effort.TextChanged += async (_, _) => { if (!updating) await Run("setProviderReasoning", new(Effort: effort.Text)); };
        advertisedEffort.SelectionChanged += (_, _) => { if (!updating && advertisedEffort.SelectedItem is string choice) effort.Text = choice == T("provider_effort_default") ? "" : choice; };
        format.SelectionChanged += (_, _) => { if (!updating) UpdateConnectionHint(); };
        saved.SelectionChanged += async (_, _) => { if (!updating && saved.SelectedItem is ManagedProvider provider) await Run("openProviderEditor", new(ProviderID: provider.Id)); };
        client.Changed += Refresh;
        Closing += (_, e) => { if (client.State.IsMutating) e.Cancel = true; };
        Closed += async (_, _) => { client.Changed -= Refresh; key.Clear(); await Run("closeProviderEditor"); };
        Refresh();
    }

    private ProviderConnectionInput Connection() => new(name.Text, baseURL.Text, format.SelectedIndex == 1 ? "anthropic" : "responses", string.IsNullOrEmpty(key.Password) ? null : key.Password);
    private TextBlock Label(string text, double size = 13) => new() { Text = text, FontSize = size, TextWrapping = TextWrapping.Wrap, VerticalAlignment = VerticalAlignment.Center };
    private Button Action(string title, Func<Task> action) {
        var button = new Button { Content = title, Padding = new Thickness(12, 6, 12, 6), MinHeight = 32 };
        AutomationProperties.SetName(button, title); button.Click += async (_, _) => await action(); return button;
    }
    private async Task Run(string command, ProviderEditorCommand? editor = null) {
        try { localError = null; await client.ProviderCommandAsync(command, editor); }
        catch (Exception ex) { localError = ex.Message; error.Text = localError; }
    }
    private void UpdateConnectionHint() {
        hint.Text = T(format.SelectedIndex == 1 ? "provider_anthropic_notice" : "provider_responses_notice");
        save.IsEnabled = !Busy && State?.DefaultModelID != null && format.SelectedIndex == 0;
    }
    private void Refresh() {
        if (State is not { } state) return;
        updating = true;
        try {
            if (editorID != state.Id) {
                editorID = state.Id; name.Text = state.DisplayName; baseURL.Text = state.BaseURL; key.Clear(); query.Clear();
                format.SelectedIndex = state.ApiFormat == "anthropic" ? 1 : 0; selectedModelID = null;
            }
            saved.ItemsSource = client.State.ManagedProviders;
            saved.SelectedItem = client.State.ManagedProviders.FirstOrDefault(provider => provider.Id == state.Id);
            key.ToolTip = T(state.HasStoredKey ? "provider_keep_key" : "provider_key_placeholder");
            sort.SelectedIndex = Array.IndexOf(new[] { "custom", "nameAscending", "nameDescending" }, state.Sort);
            foreach (var control in new Control[] { name, baseURL, key, format, fetch, addModel, addProvider, saved }) control.IsEnabled = !Busy;
            saved.IsEnabled &= client.State.ManagedProviders.Length > 0;
            fetch.Content = T("provider_fetch") + (state.IsBusy ? "…" : "");
            var selected = state.Models.FirstOrDefault(row => row.Id == state.DefaultModelID);
            if (selectedModelID != state.DefaultModelID) { selectedModelID = state.DefaultModelID; effort.Text = selected?.ReasoningEffort ?? ""; }
            defaultModel.Text = T("provider_default_model") + ": " + (state.DefaultModelID ?? "—");
            effort.IsEnabled = !Busy && selected != null;
            var options = selected?.ReasoningOptions ?? [];
            advertisedEffort.ItemsSource = new[] { T("provider_effort_default") }.Concat(options).ToArray();
            advertisedEffort.Visibility = options.Length == 0 ? Visibility.Collapsed : Visibility.Visible;
            effortHint.Text = T(options.Length == 0 ? "provider_effort_manual_hint" : "provider_effort_advertised_hint");
            error.Text = localError ?? state.Error ?? "";
            UpdateConnectionHint(); RenderModels(state);
        } finally { updating = false; }
    }
    private void RenderModels(ProviderEditorState state) {
        models.Children.Clear();
        if (state.VisibleModelIDs.Length == 0) {
            var empty = Label(T(state.Models.Length == 0 ? "provider_fetch_hint" : "provider_no_match"), 12); empty.Margin = new Thickness(18); models.Children.Add(empty); return;
        }
        foreach (var id in state.VisibleModelIDs) {
            var row = state.Models.Single(model => model.Id == id);
            var index = Array.IndexOf(state.VisibleModelIDs, id);
            var grid = new Grid { Margin = new Thickness(10, 8, 10, 8), IsEnabled = !Busy };
            grid.ColumnDefinitions.Add(new ColumnDefinition { Width = GridLength.Auto }); grid.ColumnDefinitions.Add(new ColumnDefinition()); grid.ColumnDefinitions.Add(new ColumnDefinition { Width = GridLength.Auto });
            var enabled = new CheckBox { IsChecked = row.IsEnabled, VerticalAlignment = VerticalAlignment.Center, Margin = new Thickness(0, 0, 12, 0) };
            AutomationProperties.SetName(enabled, T("provider_enable_model") + " " + id);
            enabled.Click += async (_, _) => await Run("enableProviderModel", new(ModelID: id, Value: enabled.IsChecked == true)); grid.Children.Add(enabled);
            var label = new StackPanel { VerticalAlignment = VerticalAlignment.Center };
            var modelID = Label(id); modelID.TextWrapping = TextWrapping.NoWrap; modelID.TextTrimming = TextTrimming.CharacterEllipsis; modelID.ToolTip = id;
            label.Children.Add(modelID); if (row.DisplayName != id) label.Children.Add(Label(row.DisplayName, 11)); Grid.SetColumn(label, 1); grid.Children.Add(label);
            var actions = new StackPanel { Orientation = Orientation.Horizontal };
            var star = Action(state.DefaultModelID == id ? "★" : "☆", async () => await Run("chooseProviderDefaultModel", new(ModelID: id)));
            AutomationProperties.SetName(star, T("provider_set_default") + " " + id); actions.Children.Add(star);
            var up = Action("↑", async () => await Run("moveProviderModel", new(ModelID: id, Offset: -1))); up.IsEnabled = index > 0; actions.Children.Add(up);
            var down = Action("↓", async () => await Run("moveProviderModel", new(ModelID: id, Offset: 1))); down.IsEnabled = index < state.VisibleModelIDs.Length - 1; actions.Children.Add(down);
            Grid.SetColumn(actions, 2); grid.Children.Add(actions); models.Children.Add(grid);
        }
    }
}
