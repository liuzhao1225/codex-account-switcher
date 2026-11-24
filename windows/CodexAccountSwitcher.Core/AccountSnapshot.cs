using System.Globalization;
using System.Text.Json;

namespace CodexAccountSwitcher.Core;

// Wire DTOs only. Account policy and storage live in Sources/SwitcherCore.
public sealed record Profile(Guid Id, string DisplayName, string? Email);
public sealed record Usage(int RemainingPercent, DateTimeOffset ResetsAt,
    int? FiveHourRemainingPercent, DateTimeOffset? FiveHourResetsAt, int? ResetCreditsRemaining = null);
public sealed record SubscriptionSnapshot(DateTimeOffset ActiveUntil, DateTimeOffset LastChecked);
public sealed record LiveSubscription(DateTimeOffset? ActiveUntil, string PlanType, bool IsActive,
    bool? WillRenew, bool? IsDelinquent, DateTimeOffset FetchedAt);
public sealed record SubscriptionPresentation(
    string Primary,
    DateTimeOffset? ActiveUntil = null,
    string? PlanType = null,
    bool? IsActive = null,
    DateTimeOffset? FetchedAt = null,
    DateTimeOffset? StaleAfter = null,
    bool RequiresUpdateImmediately = false,
    bool IsWaitingForRefresh = false,
    string? RefreshError = null,
    string AutoRenew = "unknown",
    string PaymentDelinquent = "unknown",
    DateTimeOffset? HistoricalActiveUntil = null,
    DateTimeOffset? HistoricalLastChecked = null)
{
    public bool NeedsUpdate(DateTimeOffset now) =>
        RequiresUpdateImmediately || (StaleAfter is { } deadline && now >= deadline);

    public string FormatPrimary(DateTimeOffset now, Func<string, string> text)
    {
        var label = Primary switch
        {
            "free" => text("subscription_live_free"),
            "inactive" => text("subscription_live_inactive"),
            "activeUntil" when ActiveUntil is { } until =>
                FormatTemplate(text("subscription_live_until"), until.ToLocalTime().ToString("yyyy-MM-dd", CultureInfo.InvariantCulture)),
            "active" => text("subscription_live_active"),
            _ => text("subscription_live_pending"),
        };
        return NeedsUpdate(now) ? label + " · " + text("subscription_live_needs_update") : label;
    }

    public string FormatDetail(DateTimeOffset now, Func<string, string> text, CultureInfo culture)
    {
        string Day(DateTimeOffset date) => date.ToLocalTime().ToString("yyyy-MM-dd", CultureInfo.InvariantCulture);
        string Timestamp(DateTimeOffset date) => date.ToLocalTime().ToString("yyyy MMM d HH:mm", culture);

        var lines = new List<string> { text("subscription_live_source") };
        if (FetchedAt is { } fetched)
        {
            var stale = NeedsUpdate(now);
            lines.Add(FormatTemplate(text(stale ? "subscription_live_last_success" : "subscription_live_updated"), Timestamp(fetched)));
            if (!string.IsNullOrEmpty(PlanType))
                lines.Add(FormatTemplate(text("subscription_live_plan"), PlanType));
            if (IsActive is { } active)
                lines.Add(text(active ? "subscription_live_status_active" : "subscription_live_status_inactive"));
            if (ActiveUntil is { } until)
                lines.Add(FormatTemplate(text("subscription_live_until"), Day(until)));
            lines.Add(text(AutoRenew switch
            {
                "yes" => "subscription_live_renew_on",
                "no" => "subscription_live_renew_off",
                _ => "subscription_live_renew_unknown",
            }));
            lines.Add(text(PaymentDelinquent switch
            {
                "yes" => "subscription_live_delinquent_yes",
                "no" => "subscription_live_delinquent_no",
                _ => "subscription_live_delinquent_unknown",
            }));
            if (IsWaitingForRefresh)
                lines.Add(text("subscription_refresh_pending"));
            else if (stale)
                lines.Add(text("subscription_live_stale_hint"));
        }
        else
        {
            lines.Add(text("subscription_live_never_succeeded"));
            lines.Add(text("subscription_live_renew_unknown"));
            lines.Add(text("subscription_live_delinquent_unknown"));
        }
        if (!string.IsNullOrEmpty(RefreshError))
            lines.Add(FormatTemplate(text("subscription_live_refresh_failed"), RefreshError));
        if (HistoricalActiveUntil is { } histUntil && HistoricalLastChecked is { } histChecked)
            lines.Add(FormatTemplate(text("subscription_live_history"), Day(histUntil), Timestamp(histChecked)));
        return string.Join("\n", lines);
    }

    private static string FormatTemplate(string template, params string[] values)
    {
        var result = template;
        foreach (var value in values)
        {
            var index = result.IndexOf("%@", StringComparison.Ordinal);
            if (index < 0) break;
            result = string.Concat(result.AsSpan(0, index), value, result.AsSpan(index + 2));
        }
        return result;
    }
}

public sealed record AccountRow(
    Profile Profile,
    string Initials,
    Usage? Usage,
    string? UsageError,
    string UsageStatus = "loaded",
    SubscriptionSnapshot? Subscription = null,
    string SubscriptionStatus = "idle",
    LiveSubscription? LiveSubscription = null,
    string? SubscriptionError = null,
    string? Title = null,
    SubscriptionPresentation? SubscriptionView = null)
{
    public string DisplayTitle => !string.IsNullOrEmpty(Title)
        ? Title
        : string.IsNullOrEmpty(Profile.Email) ? Profile.DisplayName : Profile.Email;
}

public sealed record Preferences(string Language = "system", bool ShowsMenuBarPercentage = true, bool ShowsFiveHourUsage = false,
    string StatusBarUsageWindow = "fiveHour", bool AutoResetEnabled = false);
public sealed record AccountSnapshot(
    AccountRow[] Accounts,
    Guid? ActiveAccountID,
    Preferences Settings,
    bool IsMutating,
    bool IsAddingAccount,
    bool ActiveIdentityConfirmed,
    string? Error,
    Dictionary<string, string>? Strings,
    int? ActiveRemainingPercent = null)
{
    public static AccountSnapshot Empty { get; } = new([], null, new(), false, false, true, null, []);
    public string Text(string key) => Strings != null && Strings.TryGetValue(key, out var value) ? value : key;
    public static JsonSerializerOptions JsonOptions { get; } = new() { PropertyNameCaseInsensitive = true };
}

public interface IAccountClient
{
    AccountSnapshot State { get; }
    event Action? Changed;
    Task CommandAsync(string command, Guid? accountID = null, bool? value = null, string? language = null,
        Guid? targetAccountID = null);
}
