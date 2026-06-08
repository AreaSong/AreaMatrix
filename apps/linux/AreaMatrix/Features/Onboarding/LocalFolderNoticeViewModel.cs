using System.ComponentModel;
using System.Runtime.CompilerServices;

namespace AreaMatrix.Linux.Features.Onboarding;

public sealed class LocalFolderNoticeViewModel : INotifyPropertyChanged
{
    private readonly ILinuxRepositoryCoreBridge coreBridge;
    private string repositoryPath = string.Empty;
    private bool isChecking;
    private bool isRiskNoticeConfirmed;
    private LinuxRepositoryValidation? latestValidation;
    private LinuxRepositoryError? error;
    private LinuxRepositoryRoute route = LinuxRepositoryRoute.None;

    public LocalFolderNoticeViewModel(ILinuxRepositoryCoreBridge coreBridge)
    {
        this.coreBridge = coreBridge;
    }

    public event PropertyChangedEventHandler? PropertyChanged;

    public string RepositoryPath
    {
        get => repositoryPath;
        private set
        {
            if (SetProperty(ref repositoryPath, value))
            {
                NotifyDisplayPropertiesChanged();
            }
        }
    }

    public bool IsChecking
    {
        get => isChecking;
        private set
        {
            if (SetProperty(ref isChecking, value))
            {
                NotifyDisplayPropertiesChanged();
            }
        }
    }

    public bool IsRiskNoticeConfirmed
    {
        get => isRiskNoticeConfirmed;
        set
        {
            if (SetProperty(ref isRiskNoticeConfirmed, value))
            {
                NotifyDisplayPropertiesChanged();
            }
        }
    }

    public LinuxRepositoryValidation? LatestValidation
    {
        get => latestValidation;
        private set
        {
            if (SetProperty(ref latestValidation, value))
            {
                NotifyDisplayPropertiesChanged();
            }
        }
    }

    public LinuxRepositoryError? Error
    {
        get => error;
        private set
        {
            if (SetProperty(ref error, value))
            {
                NotifyDisplayPropertiesChanged();
            }
        }
    }

    public LinuxRepositoryRoute Route
    {
        get => route;
        private set => SetProperty(ref route, value);
    }

    public bool HasFolder => !string.IsNullOrWhiteSpace(RepositoryPath);

    public bool ShouldShowRiskConfirmation => LatestValidation is { } validation
        && RequiresRiskConfirmation(validation);

    public bool CanContinue
    {
        get
        {
            return !IsChecking
                && Error is null
                && LatestValidation is { } validation
                && CanRouteForward(validation)
                && (!ShouldShowRiskConfirmation || IsRiskNoticeConfirmed);
        }
    }

    public string FolderText => HasFolder
        ? $"Folder: {RepositoryPath}"
        : "Choose a repository folder first.";

    public string TypeText => LatestValidation is { } validation
        ? $"Type: {PathTypeLabel(validation)}"
        : "Type: Unknown";

    public string WritableText => LatestValidation is { } validation
        ? $"Writable: {(validation.IsWritable ? "Yes" : "No")}"
        : "Writable: Unknown";

    public string StatusText
    {
        get
        {
            if (IsChecking)
            {
                return LinuxRepositoryDisplayText.CheckingFolder;
            }

            if (Error is { } currentError)
            {
                return currentError.Message;
            }

            return LatestValidation is { } validation
                ? StatusTextFor(validation)
                : "Choose a repository folder first.";
        }
    }

    public string RiskText => LatestValidation is { } validation
        ? RiskTextFor(validation)
        : string.Empty;

    public string ContinueDisabledReason
    {
        get
        {
            if (CanContinue)
            {
                return string.Empty;
            }

            if (IsChecking)
            {
                return LinuxRepositoryDisplayText.CheckingFolder;
            }

            if (Error is { } currentError)
            {
                return currentError.Message;
            }

            if (ShouldShowRiskConfirmation && !IsRiskNoticeConfirmed)
            {
                return "Confirm this folder location risk before continuing.";
            }

            return "Choose a repository folder first.";
        }
    }

    public async Task LoadRouteAsync(
        LinuxRepositoryRoute route,
        CancellationToken cancellationToken = default)
    {
        RepositoryPath = route.RepoPath.Trim();
        LatestValidation = route.Validation;
        Error = null;
        Route = LinuxRepositoryRoute.None;
        IsRiskNoticeConfirmed = false;

        if (string.IsNullOrWhiteSpace(RepositoryPath))
        {
            Error = new LinuxRepositoryError(
                LinuxRepositoryErrorKind.InvalidPath,
                "Choose a repository folder first.");
            return;
        }

        await RefreshFolderStatusAsync(cancellationToken).ConfigureAwait(false);
    }

    public async Task RefreshFolderStatusAsync(CancellationToken cancellationToken = default)
    {
        if (string.IsNullOrWhiteSpace(RepositoryPath))
        {
            Error = new LinuxRepositoryError(
                LinuxRepositoryErrorKind.InvalidPath,
                "Choose a repository folder first.");
            return;
        }

        IsChecking = true;
        Error = null;
        try
        {
            LinuxRepositoryValidation validation = await coreBridge
                .ValidateRepoPathAsync(RepositoryPath, cancellationToken)
                .ConfigureAwait(false);
            cancellationToken.ThrowIfCancellationRequested();
            LatestValidation = validation;
            Error = BlockingErrorFor(validation);
        }
        catch (OperationCanceledException) when (cancellationToken.IsCancellationRequested)
        {
        }
        catch (LinuxRepositoryCoreException exception)
        {
            Error = new LinuxRepositoryError(
                exception.Kind,
                LinuxRepositoryDisplayText.ErrorMessageFor(exception),
                exception.Path);
        }
        catch (Exception exception)
        {
            Error = new LinuxRepositoryError(
                LinuxRepositoryErrorKind.Unavailable,
                exception.Message);
        }
        finally
        {
            IsChecking = false;
        }
    }

    public Task<bool> ContinueAsync(CancellationToken cancellationToken = default)
    {
        cancellationToken.ThrowIfCancellationRequested();
        if (!CanContinue || LatestValidation is not { } validation)
        {
            return Task.FromResult(false);
        }

        Route = RouteFor(validation);
        return Task.FromResult(Route.Kind != LinuxRepositoryRouteKind.None);
    }

    public void ChooseAnotherFolder()
    {
        Route = new LinuxRepositoryRoute(
            LinuxRepositoryRouteKind.ChooseRepository,
            string.Empty,
            null);
    }

    public void ReportOpenFolderError(string message)
    {
        Error = new LinuxRepositoryError(
            LinuxRepositoryErrorKind.Unavailable,
            message,
            RepositoryPath);
    }

    private static LinuxRepositoryRoute RouteFor(LinuxRepositoryValidation validation)
    {
        if (validation.IsInitialized)
        {
            return new LinuxRepositoryRoute(
                LinuxRepositoryRouteKind.MainWindow,
                validation.RepoPath,
                validation);
        }

        LinuxRepositoryRouteKind kind = validation.RecommendedMode switch
        {
            LinuxRepositoryInitMode.CreateEmpty => LinuxRepositoryRouteKind.RepositoryInitConfirm,
            LinuxRepositoryInitMode.AdoptExisting => LinuxRepositoryRouteKind.RepositoryAdoptConfirm,
            _ => LinuxRepositoryRouteKind.None
        };
        return new LinuxRepositoryRoute(kind, validation.RepoPath, validation);
    }

    private static bool CanRouteForward(LinuxRepositoryValidation validation)
    {
        return validation.IsReadable
            && validation.IsWritable
            && (validation.IsInitialized || validation.RecommendedMode is not null);
    }

    private static bool RequiresRiskConfirmation(LinuxRepositoryValidation validation)
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

    private static LinuxRepositoryError? BlockingErrorFor(LinuxRepositoryValidation validation)
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

        return PermissionError(validation) ?? MetadataError(validation);
    }

    private static LinuxRepositoryError? PermissionError(LinuxRepositoryValidation validation)
    {
        if (validation.IsReadable && validation.IsWritable)
        {
            return null;
        }

        return new LinuxRepositoryError(
            LinuxRepositoryErrorKind.PermissionDenied,
            "The folder is not writable. Choose another folder before initializing or importing.",
            validation.RepoPath);
    }

    private static LinuxRepositoryError? MetadataError(LinuxRepositoryValidation validation)
    {
        return validation.IsInsideAreaMatrix || validation.HasIssue(LinuxRepositoryPathIssue.InsideAreaMatrix)
            ? new LinuxRepositoryError(
                LinuxRepositoryErrorKind.InvalidPath,
                "Choose the repository root folder.",
                validation.RepoPath)
            : null;
    }

    private static string PathTypeLabel(LinuxRepositoryValidation validation)
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

    private static string StatusTextFor(LinuxRepositoryValidation validation)
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

    private static string RiskTextFor(LinuxRepositoryValidation validation)
    {
        return PathTypeLabel(validation) switch
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
    }

    private bool SetProperty<T>(ref T field, T value, [CallerMemberName] string propertyName = "")
    {
        if (EqualityComparer<T>.Default.Equals(field, value))
        {
            return false;
        }

        field = value;
        OnPropertyChanged(propertyName);
        return true;
    }

    private void NotifyDisplayPropertiesChanged()
    {
        OnPropertyChanged(nameof(HasFolder));
        OnPropertyChanged(nameof(ShouldShowRiskConfirmation));
        OnPropertyChanged(nameof(CanContinue));
        OnPropertyChanged(nameof(FolderText));
        OnPropertyChanged(nameof(TypeText));
        OnPropertyChanged(nameof(WritableText));
        OnPropertyChanged(nameof(StatusText));
        OnPropertyChanged(nameof(RiskText));
        OnPropertyChanged(nameof(ContinueDisabledReason));
    }

    private void OnPropertyChanged([CallerMemberName] string propertyName = "")
    {
        PropertyChanged?.Invoke(this, new PropertyChangedEventArgs(propertyName));
    }
}
