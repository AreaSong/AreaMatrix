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
            Row("File watcher", capabilities.Watcher),
            Row("Trash / Recycle Bin", capabilities.Trash),
            Row("Share integration", capabilities.ShareExtension),
            Row("Cloud placeholder", capabilities.CloudPlaceholder),
            Row("Security bookmark", capabilities.SecurityBookmark)
        ];
    }

    private static string Row(string name, LinuxPlatformCapabilitySupport support)
    {
        string enabled = support.UiEnabled ? "enabled" : "disabled";
        string permission = support.RequiresPermission ? ", requires permission" : string.Empty;
        string reason = string.IsNullOrWhiteSpace(support.Reason) ? string.Empty : $": {support.Reason}";
        return $"{name} - {support.Status} - UI {enabled}{permission}{reason}";
    }
}
