namespace AreaMatrix.Features.Onboarding;

public sealed partial class RepositoryAdoptConfirmViewModel
{
    private static bool IsAdoptEligible(WindowsRepositoryValidation? currentValidation)
    {
        return currentValidation is not null
            && currentValidation.RecommendedMode == WindowsRepositoryInitMode.AdoptExisting
            && currentValidation.Exists
            && currentValidation.IsDirectory
            && currentValidation.IsReadable
            && currentValidation.IsWritable
            && !currentValidation.IsEmpty
            && !currentValidation.IsInitialized
            && !currentValidation.IsInsideAreaMatrix
            && !currentValidation.HasUnfinishedScanSession;
    }

    private static WindowsRepositoryError? BlockingErrorFor(WindowsRepositoryValidation currentValidation)
    {
        return InsideMetadataError(currentValidation)
            ?? MissingOrFileError(currentValidation)
            ?? PermissionError(currentValidation)
            ?? ReservedNameError(currentValidation)
            ?? InitializedOrUnfinishedError(currentValidation)
            ?? EmptyFolderError(currentValidation);
    }

    private static WindowsRepositoryError? InsideMetadataError(WindowsRepositoryValidation validation)
    {
        if (!validation.IsInsideAreaMatrix
            && !validation.HasIssue(WindowsRepositoryPathIssue.InsideAreaMatrix))
        {
            return null;
        }

        return new WindowsRepositoryError(
            WindowsRepositoryErrorKind.InvalidPath,
            "Choose the repository folder, not its .areamatrix metadata folder.",
            validation.RepoPath);
    }

    private static WindowsRepositoryError? MissingOrFileError(WindowsRepositoryValidation validation)
    {
        if (!validation.Exists || validation.HasIssue(WindowsRepositoryPathIssue.MissingPath))
        {
            return new WindowsRepositoryError(
                WindowsRepositoryErrorKind.InvalidPath,
                "Folder not found",
                validation.RepoPath);
        }

        if (!validation.IsDirectory || validation.HasIssue(WindowsRepositoryPathIssue.NotDirectory))
        {
            return new WindowsRepositoryError(
                WindowsRepositoryErrorKind.SelectedFile,
                "Select a folder, not a file.",
                validation.RepoPath);
        }

        return null;
    }

    private static WindowsRepositoryError? PermissionError(WindowsRepositoryValidation validation)
    {
        if (!validation.IsReadable || validation.HasIssue(WindowsRepositoryPathIssue.NotReadable))
        {
            return new WindowsRepositoryError(
                WindowsRepositoryErrorKind.PermissionDenied,
                "AreaMatrix cannot read this folder.",
                validation.RepoPath);
        }

        if (!validation.IsWritable || validation.HasIssue(WindowsRepositoryPathIssue.NotWritable))
        {
            return new WindowsRepositoryError(
                WindowsRepositoryErrorKind.PermissionDenied,
                "AreaMatrix cannot write repository metadata in this folder.",
                validation.RepoPath);
        }

        return null;
    }

    private static WindowsRepositoryError? ReservedNameError(WindowsRepositoryValidation validation)
    {
        if (!validation.HasIssue(WindowsRepositoryPathIssue.WindowsReservedName))
        {
            return null;
        }

        return new WindowsRepositoryError(
            WindowsRepositoryErrorKind.InvalidPath,
            "This path contains a reserved Windows name.",
            validation.RepoPath);
    }

    private static WindowsRepositoryError? InitializedOrUnfinishedError(WindowsRepositoryValidation validation)
    {
        if (validation.IsInitialized)
        {
            return new WindowsRepositoryError(
                WindowsRepositoryErrorKind.InvalidRepository,
                "This folder is already an AreaMatrix repository.",
                validation.RepoPath);
        }

        if (!validation.HasUnfinishedScanSession
            && !validation.HasIssue(WindowsRepositoryPathIssue.UnfinishedScanSession))
        {
            return null;
        }

        return new WindowsRepositoryError(
            WindowsRepositoryErrorKind.InvalidRepository,
            "An unfinished repository scan must be recovered before adopting this folder.",
            validation.RepoPath);
    }

    private static WindowsRepositoryError? EmptyFolderError(WindowsRepositoryValidation validation)
    {
        if (!validation.IsEmpty)
        {
            return null;
        }

        return new WindowsRepositoryError(
            WindowsRepositoryErrorKind.InvalidRepository,
            "This folder is empty. Use the create repository confirmation instead.",
            validation.RepoPath);
    }

    private static string DisabledReasonFor(
        WindowsRepositoryValidation? currentValidation,
        WindowsRepositoryError? currentError,
        RepositoryAdoptConfirmViewModel model)
    {
        if (currentError is not null)
        {
            return currentError.Message;
        }

        if (currentValidation is null)
        {
            return "Choose a folder first.";
        }

        if (!model.IsMetadataAcknowledged)
        {
            return "Confirm that AreaMatrix will add metadata to this folder.";
        }

        if (model.RequiresSyncRiskAcknowledgement && !model.IsSyncRiskAcknowledged)
        {
            return "Confirm this location may sync or report changes differently.";
        }

        return IsAdoptEligible(currentValidation)
            ? string.Empty
            : "This folder is not eligible for existing-folder adoption.";
    }

    private static bool IsSyncRiskPath(WindowsRepositoryValidation? currentValidation)
    {
        return currentValidation is not null
            && (currentValidation.IsOneDrivePath
                || currentValidation.IsICloudPath
                || currentValidation.PlatformPathKind == WindowsPlatformPathKind.OneDrive
                || currentValidation.PlatformPathKind == WindowsPlatformPathKind.ICloudDrive
                || currentValidation.PlatformPathKind == WindowsPlatformPathKind.NetworkShare
                || currentValidation.HasIssue(WindowsRepositoryPathIssue.OneDrivePath)
                || currentValidation.HasIssue(WindowsRepositoryPathIssue.ICloudPath));
    }

    private static string PathTypeLabel(WindowsPlatformPathKind? kind)
    {
        return kind switch
        {
            WindowsPlatformPathKind.Local => "Local folder",
            WindowsPlatformPathKind.ICloudDrive => "iCloud Drive",
            WindowsPlatformPathKind.OneDrive => "OneDrive",
            WindowsPlatformPathKind.NetworkShare => "Network mount",
            _ => "Unknown"
        };
    }

    private static WindowsRepositoryError ErrorFromCoreException(WindowsRepositoryCoreException exception)
    {
        string message = exception.Kind switch
        {
            WindowsRepositoryErrorKind.InvalidPath => "Folder not found",
            WindowsRepositoryErrorKind.SelectedFile => "Select a folder, not a file.",
            WindowsRepositoryErrorKind.PermissionDenied => "Choose another folder.",
            WindowsRepositoryErrorKind.Config => "This repository configuration cannot be opened.",
            WindowsRepositoryErrorKind.Db => "Repository database is locked or unavailable.",
            WindowsRepositoryErrorKind.DiskUnavailable => "Drive disconnected",
            _ => exception.Message
        };

        return new WindowsRepositoryError(exception.Kind, message, exception.Path);
    }
}
