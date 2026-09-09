using System.Text.Json;

namespace CodexAccountSwitcher.Core;

// Wire DTOs only. Account policy and storage live in Sources/SwitcherCore.
public sealed record Profile(Guid Id, string DisplayName, string? Email);
public sealed record Usage(int RemainingPercent, DateTimeOffset ResetsAt,
    int? FiveHourRemainingPercent, DateTimeOffset? FiveHourResetsAt);
public sealed record AccountRow(Profile Profile, string Initials, Usage? Usage, string? UsageError, string UsageStatus = "loaded");
public sealed record Preferences(string Language = "system", bool ShowsMenuBarPercentage = true, bool ShowsFiveHourUsage = false);
public sealed record AccountSnapshot(AccountRow[] Accounts, Guid? ActiveAccountID, Preferences Settings,
    bool IsMutating, bool IsAddingAccount, bool ActiveIdentityConfirmed, string? Error, Dictionary<string, string> Strings)
{
    public static AccountSnapshot Empty { get; } = new([], null, new(), false, false, true, null, []);
    public string Text(string key) => Strings.GetValueOrDefault(key, key);
    public static JsonSerializerOptions JsonOptions { get; } = new() { PropertyNameCaseInsensitive = true };
}

public interface IAccountClient
{
    AccountSnapshot State { get; }
    event Action? Changed;
    Task CommandAsync(string command, Guid? accountID = null, bool? value = null, string? language = null);
}
