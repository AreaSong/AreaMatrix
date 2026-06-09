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
            Row(
                "Repository access",
                SecurityBookmark,
                "Folder picker and ACL checks still run in the repository flow."),
            Row(
                "File import",
                LimitedFrom(SecurityBookmark, "Import picker, drop, and replace preflight rerun before import."),
                "This page explains availability; the import flow owns final preflight."),
            Row(
                "File watcher",
                Watcher,
                "ReadDirectoryChangesW support is exposed as platform capability state."),
            Row(
                "Cloud provider",
                CloudPlaceholder,
                "OneDrive or placeholder status is best effort and never reports exact sync progress."),
            Row(
                "Trash / Recycle Bin",
                Trash,
                "Replace and delete flows stay disabled when recoverable Trash support is unavailable."),
            Row(
                "Share integration",
                ShareExtension,
                "Desktop handoff support is explained without starting an import."),
            Row(
                "Camera import",
                LimitedFrom(ShareExtension, "Camera capture is validated by platform import flow, not this page."),
                "Desktop platforms should use file picker, folder picker, or drag and drop.")
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

    private static PlatformDifferencesCapabilitySupport LimitedFrom(
        PlatformDifferencesCapabilitySupport support,
        string reason)
    {
        if (support.Status != PlatformDifferencesCapabilityStatus.Available)
        {
            return support with { Reason = CombinedReason(support.Reason, reason) };
        }

        return new PlatformDifferencesCapabilitySupport(
            PlatformDifferencesCapabilityStatus.Limited,
            UiEnabled: false,
            RequiresPermission: true,
            reason);
    }

    private static string Row(
        string name,
        PlatformDifferencesCapabilitySupport support,
        string detail)
    {
        string enabled = support.UiEnabled ? "enabled" : "disabled";
        string permission = support.RequiresPermission ? ", requires permission" : string.Empty;
        string reason = string.IsNullOrWhiteSpace(support.Reason) ? string.Empty : $": {support.Reason}";
        return $"{name} - {support.Status} - UI {enabled}{permission}{reason}. {detail}";
    }

    private static string CombinedReason(string? originalReason, string additionalReason)
    {
        return string.IsNullOrWhiteSpace(originalReason)
            ? additionalReason
            : $"{originalReason} {additionalReason}";
    }
}
