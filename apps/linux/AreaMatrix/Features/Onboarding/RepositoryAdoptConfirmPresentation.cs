namespace AreaMatrix.Linux.Features.Onboarding;

internal static class RepositoryAdoptConfirmPresentation
{
    public static string PathTypeLabel(LinuxRepositoryValidation? validation)
    {
        if (validation is null)
        {
            return "Unknown";
        }

        return validation.PlatformPathKind switch
        {
            LinuxPlatformPathKind.Local => "Local folder",
            LinuxPlatformPathKind.ExternalDrive => "External drive",
            LinuxPlatformPathKind.ICloudDrive => "Sync folder",
            LinuxPlatformPathKind.OneDrive => "Sync folder",
            LinuxPlatformPathKind.NetworkShare => "Network mount",
            _ => "Unknown"
        };
    }

    public static string RiskTextFor(LinuxRepositoryValidation? validation)
    {
        if (validation is null)
        {
            return string.Empty;
        }

        string pathRisk = validation.PlatformPathKind switch
        {
            LinuxPlatformPathKind.ExternalDrive =>
                "External drives can disconnect while metadata is being created.",
            LinuxPlatformPathKind.NetworkShare =>
                "Network mounts can become unavailable while metadata is being created.",
            LinuxPlatformPathKind.ICloudDrive or LinuxPlatformPathKind.OneDrive =>
                "Sync folders may report changes differently outside AreaMatrix.",
            LinuxPlatformPathKind.Unknown =>
                "This folder type is unknown. Confirm it can persist local metadata before continuing.",
            _ => string.Empty
        };

        if (!validation.IsCaseSensitivePath)
        {
            return MergeRiskText(
                pathRisk,
                "Case-insensitive path detected. Name conflicts will follow Core rules.");
        }

        return pathRisk;
    }

    public static string ErrorMessageFor(LinuxRepositoryCoreException exception)
    {
        return exception.Kind switch
        {
            LinuxRepositoryErrorKind.InvalidPath => "Folder not found",
            LinuxRepositoryErrorKind.SelectedFile => "Select a folder, not a file.",
            LinuxRepositoryErrorKind.PermissionDenied => "Choose another folder.",
            LinuxRepositoryErrorKind.Config => "This repository configuration cannot be opened.",
            LinuxRepositoryErrorKind.Db => "Repository database is locked or unavailable.",
            LinuxRepositoryErrorKind.DiskUnavailable => "Disk unavailable",
            LinuxRepositoryErrorKind.ICloudPlaceholder => "The folder is not available locally.",
            _ => exception.Message
        };
    }

    private static string MergeRiskText(string first, string second)
    {
        if (string.IsNullOrWhiteSpace(first))
        {
            return second;
        }

        return string.IsNullOrWhiteSpace(second)
            ? first
            : $"{first} {second}";
    }
}
