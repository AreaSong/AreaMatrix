namespace AreaMatrix.Linux.Features.Onboarding;

internal static class RepositoryInitConfirmPresentation
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
                "External drives can disconnect during metadata creation; retry after the drive is available.",
            LinuxPlatformPathKind.NetworkShare =>
                "Network mounts can become unavailable; retry if metadata creation fails.",
            LinuxPlatformPathKind.ICloudDrive or LinuxPlatformPathKind.OneDrive =>
                "AreaMatrix does not manage your sync provider or cloud placeholder state.",
            LinuxPlatformPathKind.Unknown =>
                "This folder type is unknown. Confirm it can persist local metadata before creating.",
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
