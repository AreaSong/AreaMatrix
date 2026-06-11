using AreaMatrix.Linux.Features.Onboarding;

namespace AreaMatrix.Linux.Features.Help;

public static class PlatformDifferencesCapabilitiesDisplay
{
    public static LinuxPlatformCapabilities UnknownSnapshot(
        LinuxPlatformId platform,
        string appVersion,
        string reason)
    {
        LinuxPlatformCapabilitySupport support = new(
            LinuxPlatformCapabilityStatus.Unknown,
            UiEnabled: false,
            RequiresPermission: false,
            reason);
        return new LinuxPlatformCapabilities(
            platform,
            appVersion,
            support,
            support,
            support,
            support,
            support);
    }

    public static IReadOnlyList<string> RowsFor(LinuxPlatformCapabilities capabilities)
    {
        return
        [
            Row(
                "Repository access",
                capabilities.SecurityBookmark,
                "Local folder and POSIX permission checks still run in repository flows."),
            Row(
                "File import",
                LimitedFrom(
                    capabilities.SecurityBookmark,
                    "File picker, folder picker, and replace preflight rerun before import."),
                "This page explains availability; the import flow owns final preflight."),
            Row(
                "File watcher",
                capabilities.Watcher,
                "inotify support is exposed as platform capability state."),
            Row(
                "Cloud provider",
                capabilities.CloudPlaceholder,
                "Third-party sync is best effort and exact sync progress is not shown."),
            Row(
                "Trash / Recycle Bin",
                capabilities.Trash,
                "Replace and delete flows stay disabled when recoverable Trash support is unavailable."),
            Row(
                "Share integration",
                capabilities.ShareExtension,
                "Desktop handoff support is explained without starting an import."),
            Row(
                "Camera import",
                LimitedFrom(
                    capabilities.ShareExtension,
                    "Camera capture is validated by platform import flow, not this page."),
                "Desktop platforms should use file picker, folder picker, or drag and drop.")
        ];
    }

    private static LinuxPlatformCapabilitySupport LimitedFrom(
        LinuxPlatformCapabilitySupport support,
        string reason)
    {
        if (support.Status != LinuxPlatformCapabilityStatus.Available)
        {
            return support with { Reason = CombinedReason(support.Reason, reason) };
        }

        return new LinuxPlatformCapabilitySupport(
            LinuxPlatformCapabilityStatus.Limited,
            UiEnabled: false,
            RequiresPermission: true,
            reason);
    }

    private static string Row(
        string name,
        LinuxPlatformCapabilitySupport support,
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
