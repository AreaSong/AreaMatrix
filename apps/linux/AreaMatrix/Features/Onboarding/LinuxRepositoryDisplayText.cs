namespace AreaMatrix.Linux.Features.Onboarding;

public static class LinuxRepositoryDisplayText
{
    public const string CheckingFolder = "Checking folder...";
    public const string SelectRepositoryFolder = "Select a repository folder.";
    public const string FolderNotFound = "Folder not found";
    public const string PermissionDenied = "Permission denied. Choose a folder you can read and write.";

    public static string StatusTextFor(LinuxRepositoryValidation validation)
    {
        if (RequiresLocalFolderNotice(validation))
        {
            return "Network or removable path detected";
        }

        if (validation.IsInitialized)
        {
            return "Existing AreaMatrix repository";
        }

        if (validation.IsEmpty)
        {
            return "Empty folder";
        }

        if (!validation.IsDirectory)
        {
            return "Select a folder, not a file.";
        }

        return "Non-empty folder";
    }

    public static string RiskTextFor(LinuxRepositoryValidation validation)
    {
        if (RequiresLocalFolderNotice(validation))
        {
            return "AreaMatrix will show a local folder notice before continuing.";
        }

        if (!validation.IsCaseSensitivePath)
        {
            return "Case-insensitive path detected. Name conflicts will follow Core rules.";
        }

        return string.Empty;
    }

    public static bool RequiresLocalFolderNotice(LinuxRepositoryValidation validation)
    {
        return validation.PlatformPathKind is LinuxPlatformPathKind.NetworkShare
                or LinuxPlatformPathKind.ExternalDrive
                or LinuxPlatformPathKind.ICloudDrive
                or LinuxPlatformPathKind.OneDrive
                or LinuxPlatformPathKind.Unknown
            || validation.IsICloudPath
            || validation.IsOneDrivePath
            || validation.HasIssue(LinuxRepositoryPathIssue.ICloudPath)
            || validation.HasIssue(LinuxRepositoryPathIssue.OneDrivePath);
    }

    public static string ErrorMessageFor(LinuxRepositoryCoreException exception)
    {
        return exception.Kind switch
        {
            LinuxRepositoryErrorKind.InvalidPath => "Choose a valid repository folder.",
            LinuxRepositoryErrorKind.PermissionDenied => PermissionDenied,
            LinuxRepositoryErrorKind.ICloudPlaceholder => "The folder is not available locally.",
            LinuxRepositoryErrorKind.Db => "Existing repository metadata could not be read.",
            LinuxRepositoryErrorKind.Config => "This repository version is not compatible.",
            LinuxRepositoryErrorKind.DiskUnavailable => "The selected disk is unavailable.",
            LinuxRepositoryErrorKind.FileNotFound => FolderNotFound,
            _ => "Folder check failed. Choose another local folder or retry."
        };
    }
}
