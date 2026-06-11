namespace AreaMatrix.Linux.Features.Onboarding;

internal static class LocalFolderNoticePresentation
{
    public static string PathTypeLabel(LinuxRepositoryValidation validation)
    {
        if (validation.IsICloudPath
            || validation.IsOneDrivePath
            || validation.HasIssue(LinuxRepositoryPathIssue.ICloudPath)
            || validation.HasIssue(LinuxRepositoryPathIssue.OneDrivePath))
        {
            return "Sync folder";
        }

        return validation.PlatformPathKind switch
        {
            LinuxPlatformPathKind.Local => "Local folder",
            LinuxPlatformPathKind.ExternalDrive => "External drive",
            LinuxPlatformPathKind.NetworkShare => "Network mount",
            LinuxPlatformPathKind.ICloudDrive => "Sync folder",
            LinuxPlatformPathKind.OneDrive => "Sync folder",
            _ => "Unknown"
        };
    }

    public static string StatusTextFor(LinuxRepositoryValidation validation)
    {
        return PathTypeLabel(validation) switch
        {
            "Local folder" => "This is the recommended setup for Linux.",
            "External drive" => "External drive detected.",
            "Network mount" => "Network mount detected.",
            "Sync folder" => "Sync folder detected.",
            _ => "Unknown"
        };
    }

    public static string PlatformCapabilityTextFor(LinuxPlatformCapabilities capabilities)
    {
        return "Platform capabilities: "
            + $"Watcher {CapabilityLabel(capabilities.Watcher)}; "
            + $"Cloud placeholders {CapabilityLabel(capabilities.CloudPlaceholder)}.";
    }

    public static string RiskTextFor(
        LinuxRepositoryValidation validation,
        LinuxPlatformCapabilities? capabilities)
    {
        string pathRisk = PathTypeLabel(validation) switch
        {
            "External drive" =>
                "If this drive is disconnected, the repository will not be accessible.",
            "Network mount" =>
                "Network drives may delay or reorder file events. Run a rescan if changes look out of date.",
            "Sync folder" =>
                "AreaMatrix does not manage your sync provider. Conflict files will be shown for review when detected.",
            "Unknown" =>
                "This folder type is unknown. Confirm it can report changes reliably before continuing.",
            _ => string.Empty
        };
        return MergeRiskText(pathRisk, PlatformCapabilityRiskText(capabilities));
    }

    public static string NormalizeAppVersion(string value)
    {
        string trimmed = value.Trim();
        return string.IsNullOrWhiteSpace(trimmed) ? "0.1.0" : trimmed;
    }

    private static string MergeRiskText(string pathRisk, string capabilityRisk)
    {
        if (string.IsNullOrWhiteSpace(pathRisk))
        {
            return capabilityRisk;
        }

        return string.IsNullOrWhiteSpace(capabilityRisk)
            ? pathRisk
            : $"{pathRisk} {capabilityRisk}";
    }

    private static string PlatformCapabilityRiskText(LinuxPlatformCapabilities? capabilities)
    {
        if (capabilities is null)
        {
            return string.Empty;
        }

        List<string> risks = [];
        if (capabilities.Watcher.Status is LinuxPlatformCapabilityStatus.Limited
            or LinuxPlatformCapabilityStatus.NotAvailable
            or LinuxPlatformCapabilityStatus.Unknown)
        {
            risks.Add(CapabilityRisk("Watcher", capabilities.Watcher));
        }

        if (capabilities.CloudPlaceholder.Status is not LinuxPlatformCapabilityStatus.Available)
        {
            risks.Add(CapabilityRisk("Cloud placeholders", capabilities.CloudPlaceholder));
        }

        return risks.Count == 0 ? string.Empty : string.Join(" ", risks);
    }

    private static string CapabilityRisk(string label, LinuxPlatformCapabilitySupport support)
    {
        string reason = string.IsNullOrWhiteSpace(support.Reason) ? "Unknown" : support.Reason;
        return $"{label}: {CapabilityLabel(support)}. {reason}";
    }

    private static string CapabilityLabel(LinuxPlatformCapabilitySupport support)
    {
        string label = support.Status switch
        {
            LinuxPlatformCapabilityStatus.Available => "available",
            LinuxPlatformCapabilityStatus.Limited => "limited",
            LinuxPlatformCapabilityStatus.NotAvailable => "not available",
            LinuxPlatformCapabilityStatus.Unknown => "unknown",
            _ => "unknown"
        };

        return support.Reason is { Length: > 0 } reason
            ? $"{label} ({reason})"
            : label;
    }
}
