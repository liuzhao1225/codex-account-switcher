using System.Text.Json;

namespace CodexAccountSwitcher.Core;

// Wire DTOs only. Account policy and storage live in Sources/SwitcherCore.
public sealed record Profile(Guid Id, string DisplayName, string? Email);
public sealed record Usage(int RemainingPercent, DateTimeOffset ResetsAt,
    int? FiveHourRemainingPercent, DateTimeOffset? FiveHourResetsAt);
public sealed record AccountRow(Profile Profile, string Initials, Usage? Usage, string? UsageError,
    string UsageStatus, bool IsActive, bool IsCredentialOwner, bool CanRemove);
public sealed record ProviderProfile(string Id, string DisplayName);
public sealed record ProviderRow(ProviderProfile Profile, bool IsActive, string Subtitle);
public sealed record SwitchConfirmation(Guid? AccountID, string? ProviderID, string Title, string Message, string ConfirmTitle);
public sealed record ProviderModel(string Id, string DisplayName, bool IsEnabled, string[] ReasoningOptions, string? ReasoningEffort);
public sealed record ManagedProvider(string Id, string DisplayName, string BaseURL, string ApiFormat, ProviderModel[] Models, string DefaultModelID, string Sort = "custom");
public sealed record ProviderEditorState(string Id, string DisplayName, string BaseURL, string ApiFormat, bool HasStoredKey,
    ProviderModel[] Models, string? DefaultModelID, string Query, string Sort, string[] VisibleModelIDs, bool IsBusy, string? Error, bool DidSave);
public sealed record ProviderConnectionInput(string DisplayName, string BaseURL, string ApiFormat, string? ApiKey);
public sealed record ProviderEditorCommand(string? ProviderID = null, ProviderConnectionInput? Connection = null,
    string? ModelID = null, string? Query = null, string? Sort = null, int? Offset = null, bool? Value = null, string? Effort = null);
public sealed record Preferences(string Language = "system", bool ShowsMenuBarPercentage = true,
    bool ShowsFiveHourUsage = false, bool EnablesProviderSwitching = false);
public sealed record AccountSnapshot(AccountRow[] Accounts, Guid? ActiveAccountID, Preferences Settings,
    bool IsMutating, bool IsAddingAccount, bool ActiveIdentityConfirmed, string? Error, Dictionary<string, string> Strings,
    ProviderRow[] Providers, string ActiveProviderID, string AuthenticationKind, SwitchConfirmation? PendingSwitch,
    ManagedProvider[] ManagedProviders, ProviderEditorState? ProviderEditor)
{
    public static AccountSnapshot Empty { get; } = new([], null, new(), false, false, false, null, [], [], "openai", "unknown", null, [], null);
    public string Text(string key) => Strings.GetValueOrDefault(key, key);
    public static JsonSerializerOptions JsonOptions { get; } = new() { PropertyNameCaseInsensitive = true };
}

public interface IAccountClient
{
    AccountSnapshot State { get; }
    event Action? Changed;
    Task CommandAsync(string command, Guid? accountID = null, bool? value = null, string? language = null, string? providerID = null);
    Task ProviderCommandAsync(string command, ProviderEditorCommand? editor = null);
}
