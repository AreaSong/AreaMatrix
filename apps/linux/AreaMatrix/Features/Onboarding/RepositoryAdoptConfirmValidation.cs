namespace AreaMatrix.Linux.Features.Onboarding;

public sealed partial class RepositoryAdoptConfirmViewModel
{
    private static bool IsAdoptEligible(LinuxRepositoryValidation? currentValidation)
    {
        return currentValidation is not null
            && currentValidation.RecommendedMode == LinuxRepositoryInitMode.AdoptExisting
            && currentValidation.Exists
            && currentValidation.IsDirectory
            && currentValidation.IsReadable
            && currentValidation.IsWritable
            && !currentValidation.IsEmpty
            && !currentValidation.IsInitialized
            && !currentValidation.IsInsideAreaMatrix
            && !currentValidation.HasUnfinishedScanSession;
    }

    private static LinuxRepositoryError? BlockingErrorFor(LinuxRepositoryValidation currentValidation)
    {
        return InsideMetadataError(currentValidation)
            ?? MissingOrFileError(currentValidation)
            ?? PermissionError(currentValidation)
            ?? InitializedOrUnfinishedError(currentValidation)
            ?? EmptyFolderError(currentValidation);
    }

    private static LinuxRepositoryError? InsideMetadataError(LinuxRepositoryValidation validation)
    {
        if (!validation.IsInsideAreaMatrix
            && !validation.HasIssue(LinuxRepositoryPathIssue.InsideAreaMatrix))
        {
            return null;
        }

        return new LinuxRepositoryError(
            LinuxRepositoryErrorKind.InvalidPath,
            "Choose the repository folder, not its .areamatrix metadata folder.",
            validation.RepoPath);
    }

    private static LinuxRepositoryError? MissingOrFileError(LinuxRepositoryValidation validation)
    {
        if (!validation.Exists || validation.HasIssue(LinuxRepositoryPathIssue.MissingPath))
        {
            return new LinuxRepositoryError(
                LinuxRepositoryErrorKind.InvalidPath,
                LinuxRepositoryDisplayText.FolderNotFound,
                validation.RepoPath);
        }

        if (!validation.IsDirectory || validation.HasIssue(LinuxRepositoryPathIssue.NotDirectory))
        {
            return new LinuxRepositoryError(
                LinuxRepositoryErrorKind.SelectedFile,
                "Select a folder, not a file.",
                validation.RepoPath);
        }

        return null;
    }

    private static LinuxRepositoryError? PermissionError(LinuxRepositoryValidation validation)
    {
        if (!validation.IsReadable || validation.HasIssue(LinuxRepositoryPathIssue.NotReadable))
        {
            return new LinuxRepositoryError(
                LinuxRepositoryErrorKind.PermissionDenied,
                "AreaMatrix cannot read this folder.",
                validation.RepoPath);
        }

        if (!validation.IsWritable || validation.HasIssue(LinuxRepositoryPathIssue.NotWritable))
        {
            return new LinuxRepositoryError(
                LinuxRepositoryErrorKind.PermissionDenied,
                "AreaMatrix cannot write repository metadata in this folder.",
                validation.RepoPath);
        }

        return null;
    }

    private static LinuxRepositoryError? InitializedOrUnfinishedError(LinuxRepositoryValidation validation)
    {
        if (validation.IsInitialized)
        {
            return new LinuxRepositoryError(
                LinuxRepositoryErrorKind.InvalidRepository,
                "This folder is already an AreaMatrix repository.",
                validation.RepoPath);
        }

        if (!validation.HasUnfinishedScanSession
            && !validation.HasIssue(LinuxRepositoryPathIssue.UnfinishedScanSession))
        {
            return null;
        }

        return new LinuxRepositoryError(
            LinuxRepositoryErrorKind.InvalidRepository,
            "An unfinished repository scan must be recovered before adopting this folder.",
            validation.RepoPath);
    }

    private static LinuxRepositoryError? EmptyFolderError(LinuxRepositoryValidation validation)
    {
        if (!validation.IsEmpty)
        {
            return null;
        }

        return new LinuxRepositoryError(
            LinuxRepositoryErrorKind.InvalidRepository,
            "This folder is empty. Use the create repository confirmation instead.",
            validation.RepoPath);
    }

    private static string DisabledReasonFor(
        LinuxRepositoryValidation? currentValidation,
        LinuxRepositoryError? currentError,
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

        if (model.RequiresLocationRiskAcknowledgement && !model.IsLocationRiskAcknowledged)
        {
            return "Confirm this location may sync or report changes differently.";
        }

        return IsAdoptEligible(currentValidation)
            ? string.Empty
            : "This folder is not eligible for existing-folder adoption.";
    }

    private static bool IsHighRiskPath(LinuxRepositoryValidation? currentValidation)
    {
        return currentValidation is not null
            && (currentValidation.IsICloudPath
                || currentValidation.IsOneDrivePath
                || currentValidation.PlatformPathKind is LinuxPlatformPathKind.ExternalDrive
                    or LinuxPlatformPathKind.ICloudDrive
                    or LinuxPlatformPathKind.OneDrive
                    or LinuxPlatformPathKind.NetworkShare
                    or LinuxPlatformPathKind.Unknown
                || currentValidation.HasIssue(LinuxRepositoryPathIssue.ICloudPath)
                || currentValidation.HasIssue(LinuxRepositoryPathIssue.OneDrivePath));
    }

    private static LinuxRepositoryError ErrorFromCoreException(LinuxRepositoryCoreException exception)
    {
        return new LinuxRepositoryError(
            exception.Kind,
            RepositoryAdoptConfirmPresentation.ErrorMessageFor(exception),
            exception.Path);
    }
}
