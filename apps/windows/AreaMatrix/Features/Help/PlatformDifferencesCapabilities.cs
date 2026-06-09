namespace AreaMatrix.Features.Help;

public enum PlatformDifferencesPlatformId
{
    Macos,
    Ios,
    Windows,
    Linux,
    Unknown
}

public enum PlatformDifferencesCapabilityStatus
{
    Available,
    Limited,
    NotAvailable,
    Unknown
}

public sealed record PlatformDifferencesCapabilitySupport(
    PlatformDifferencesCapabilityStatus Status,
    bool UiEnabled,
    bool RequiresPermission,
    string? Reason);

public sealed record PlatformDifferencesCapabilities(
    PlatformDifferencesPlatformId Platform,
    string AppVersion,
    PlatformDifferencesCapabilitySupport Watcher,
    PlatformDifferencesCapabilitySupport Trash,
    PlatformDifferencesCapabilitySupport ShareExtension,
    PlatformDifferencesCapabilitySupport CloudPlaceholder,
    PlatformDifferencesCapabilitySupport SecurityBookmark)
{
    public IReadOnlyList<string> DisplayRows()
    {
        return
        [
            Row("File watcher", Watcher),
            Row("Trash / Recycle Bin", Trash),
            Row("Share integration", ShareExtension),
            Row("Cloud placeholder", CloudPlaceholder),
            Row("Security bookmark", SecurityBookmark)
        ];
    }

    public static PlatformDifferencesCapabilities UnknownSnapshot(
        PlatformDifferencesPlatformId platform,
        string appVersion,
        string reason)
    {
        PlatformDifferencesCapabilitySupport support = new(
            PlatformDifferencesCapabilityStatus.Unknown,
            false,
            false,
            reason);
        return new PlatformDifferencesCapabilities(
            platform,
            appVersion,
            support,
            support,
            support,
            support,
            support);
    }

    private static string Row(string name, PlatformDifferencesCapabilitySupport support)
    {
        string enabled = support.UiEnabled ? "enabled" : "disabled";
        string permission = support.RequiresPermission ? ", requires permission" : string.Empty;
        string reason = string.IsNullOrWhiteSpace(support.Reason) ? string.Empty : $": {support.Reason}";
        return $"{name} - {support.Status} - UI {enabled}{permission}{reason}";
    }
}
