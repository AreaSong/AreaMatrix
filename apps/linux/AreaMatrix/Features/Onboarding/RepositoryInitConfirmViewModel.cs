using System.ComponentModel;
using System.Runtime.CompilerServices;

namespace AreaMatrix.Linux.Features.Onboarding;

public sealed class RepositoryInitConfirmViewModel : INotifyPropertyChanged
{
    private readonly ILinuxRepositoryCoreBridge coreBridge;
    private string repositoryPath = string.Empty;
    private bool isChecking;
    private bool isCreating;
    private LinuxRepositoryValidation? validation;
    private LinuxRepositoryError? error;
    private LinuxRepositoryRoute completedRoute = LinuxRepositoryRoute.None;

    public RepositoryInitConfirmViewModel(ILinuxRepositoryCoreBridge coreBridge)
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

    public bool IsCreating
    {
        get => isCreating;
        private set
        {
            if (SetProperty(ref isCreating, value))
            {
                NotifyDisplayPropertiesChanged();
            }
        }
    }

    public LinuxRepositoryValidation? Validation
    {
        get => validation;
        private set
        {
            if (SetProperty(ref validation, value))
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

    public LinuxRepositoryRoute CompletedRoute
    {
        get => completedRoute;
        private set => SetProperty(ref completedRoute, value);
    }

    public bool CanCreateRepository => Error is null
        && !IsChecking
        && !IsCreating
        && IsCreateEmptyEligible(Validation);

    public bool CanRetryCreate => !IsChecking
        && !IsCreating
        && IsCreateEmptyEligible(Validation);

    public string FolderText => string.IsNullOrWhiteSpace(RepositoryPath)
        ? "Folder: Choose a folder first."
        : $"Folder: {RepositoryPath}";

    public string PathTypeText => $"Type: {RepositoryInitConfirmPresentation.PathTypeLabel(Validation)}";

    public string WritableText => Validation?.IsWritable == true
        ? "Writable: Yes"
        : "Writable: No";

    public string SafetyText => "AreaMatrix will create a .areamatrix folder here.";

    public string NoOverwriteText => "No existing files will be moved, deleted, renamed, or overwritten.";

    public string FolderCheckText
    {
        get
        {
            if (Validation is null)
            {
                return "Folder is empty: Unknown";
            }

            if (!Validation.Exists)
            {
                return Validation.RecommendedMode == LinuxRepositoryInitMode.CreateEmpty
                    ? "Folder can be created: Yes"
                    : "Folder can be created: No";
            }

            return Validation.IsEmpty
                ? "Folder is empty: Yes"
                : "Folder is empty: No";
        }
    }

    public string WritePermissionText => Validation?.IsWritable == true
        ? "Write permission available: Yes"
        : "Write permission available: No";

    public string DiskSpaceText => "Enough disk space: Core verifies metadata writes during creation.";

    public string RiskText => RepositoryInitConfirmPresentation.RiskTextFor(Validation);

    public string DisabledReason => DisabledReasonFor(Validation, Error);

    public string StatusText
    {
        get
        {
            if (IsCreating)
            {
                return "Creating metadata...";
            }

            if (IsChecking)
            {
                return LinuxRepositoryDisplayText.CheckingFolder;
            }

            if (Error is { } currentError)
            {
                return currentError.Message;
            }

            return CanCreateRepository
                ? "Ready to create .areamatrix metadata."
                : DisabledReason;
        }
    }

    public async Task OpenRouteAsync(
        LinuxRepositoryRoute route,
        CancellationToken cancellationToken = default)
    {
        CompletedRoute = LinuxRepositoryRoute.None;
        Error = null;
        Validation = route.Validation;
        RepositoryPath = route.RepoPath.Trim();

        if (route.Kind != LinuxRepositoryRouteKind.RepositoryInitConfirm
            || string.IsNullOrWhiteSpace(RepositoryPath))
        {
            Error = new LinuxRepositoryError(
                LinuxRepositoryErrorKind.InvalidRepository,
                "Choose a folder first.",
                RepositoryPath);
            return;
        }

        await RefreshValidationAsync(cancellationToken).ConfigureAwait(false);
    }

    public async Task RefreshValidationAsync(CancellationToken cancellationToken = default)
    {
        if (string.IsNullOrWhiteSpace(RepositoryPath))
        {
            Error = new LinuxRepositoryError(
                LinuxRepositoryErrorKind.InvalidPath,
                "Choose a folder first.",
                RepositoryPath);
            return;
        }

        IsChecking = true;
        Error = null;
        try
        {
            LinuxRepositoryValidation refreshed = await coreBridge
                .ValidateRepoPathAsync(RepositoryPath, cancellationToken)
                .ConfigureAwait(false);
            Validation = refreshed;
            Error = BlockingErrorFor(refreshed);
        }
        catch (OperationCanceledException) when (cancellationToken.IsCancellationRequested)
        {
        }
        catch (LinuxRepositoryCoreException exception)
        {
            Error = ErrorFromCoreException(exception);
        }
        catch (Exception exception)
        {
            Error = new LinuxRepositoryError(
                LinuxRepositoryErrorKind.Unavailable,
                exception.Message,
                RepositoryPath);
        }
        finally
        {
            IsChecking = false;
        }
    }

    public async Task CreateRepositoryAsync(CancellationToken cancellationToken = default)
    {
        if (!CanCreateRepository)
        {
            return;
        }

        IsCreating = true;
        Error = null;
        CompletedRoute = LinuxRepositoryRoute.None;
        try
        {
            await coreBridge
                .InitializeEmptyRepositoryAsync(RepositoryPath, cancellationToken)
                .ConfigureAwait(false);
            LinuxRepositoryValidation initialized = await coreBridge
                .ValidateRepoPathAsync(RepositoryPath, cancellationToken)
                .ConfigureAwait(false);
            Validation = initialized;

            if (!initialized.IsInitialized)
            {
                Error = new LinuxRepositoryError(
                    LinuxRepositoryErrorKind.InvalidRepository,
                    "Repository metadata was not detected after creation.",
                    RepositoryPath);
                return;
            }

            CompletedRoute = new LinuxRepositoryRoute(
                LinuxRepositoryRouteKind.MainWindow,
                initialized.RepoPath,
                initialized);
        }
        catch (OperationCanceledException) when (cancellationToken.IsCancellationRequested)
        {
        }
        catch (LinuxRepositoryCoreException exception)
        {
            Error = ErrorFromCoreException(exception);
        }
        catch (Exception exception)
        {
            Error = new LinuxRepositoryError(
                LinuxRepositoryErrorKind.Unavailable,
                exception.Message,
                RepositoryPath);
        }
        finally
        {
            IsCreating = false;
        }
    }

    private static bool IsCreateEmptyEligible(LinuxRepositoryValidation? currentValidation)
    {
        return currentValidation is not null
            && currentValidation.RecommendedMode == LinuxRepositoryInitMode.CreateEmpty
            && currentValidation.IsWritable
            && !currentValidation.IsInitialized
            && !currentValidation.IsInsideAreaMatrix
            && (!currentValidation.Exists
                || (currentValidation.IsDirectory
                    && currentValidation.IsReadable
                    && currentValidation.IsEmpty));
    }

    private static LinuxRepositoryError? BlockingErrorFor(LinuxRepositoryValidation currentValidation)
    {
        if (currentValidation.IsInsideAreaMatrix
            || currentValidation.HasIssue(LinuxRepositoryPathIssue.InsideAreaMatrix))
        {
            return new LinuxRepositoryError(
                LinuxRepositoryErrorKind.InvalidPath,
                "Choose the repository folder, not its .areamatrix metadata folder.",
                currentValidation.RepoPath);
        }

        if (currentValidation.Exists && !currentValidation.IsDirectory)
        {
            return new LinuxRepositoryError(
                LinuxRepositoryErrorKind.SelectedFile,
                "Select a folder, not a file.",
                currentValidation.RepoPath);
        }

        if (currentValidation.Exists && !currentValidation.IsReadable)
        {
            return new LinuxRepositoryError(
                LinuxRepositoryErrorKind.PermissionDenied,
                "AreaMatrix cannot read this folder.",
                currentValidation.RepoPath);
        }

        if (!currentValidation.IsWritable)
        {
            return new LinuxRepositoryError(
                LinuxRepositoryErrorKind.PermissionDenied,
                "AreaMatrix cannot write repository metadata in this folder.",
                currentValidation.RepoPath);
        }

        return null;
    }

    private static string DisabledReasonFor(
        LinuxRepositoryValidation? currentValidation,
        LinuxRepositoryError? currentError)
    {
        if (currentError is not null)
        {
            return currentError.Message;
        }

        if (currentValidation is null)
        {
            return "Choose a folder first.";
        }

        if (currentValidation.IsInitialized)
        {
            return "This folder is already an AreaMatrix repository.";
        }

        if (currentValidation.RecommendedMode != LinuxRepositoryInitMode.CreateEmpty)
        {
            return "This folder is not eligible for empty repository creation.";
        }

        return BlockingErrorFor(currentValidation)?.Message ?? string.Empty;
    }

    private static LinuxRepositoryError ErrorFromCoreException(LinuxRepositoryCoreException exception)
    {
        return new LinuxRepositoryError(
            exception.Kind,
            RepositoryInitConfirmPresentation.ErrorMessageFor(exception),
            exception.Path);
    }

    private void NotifyDisplayPropertiesChanged()
    {
        OnPropertyChanged(nameof(CanCreateRepository));
        OnPropertyChanged(nameof(CanRetryCreate));
        OnPropertyChanged(nameof(FolderText));
        OnPropertyChanged(nameof(PathTypeText));
        OnPropertyChanged(nameof(WritableText));
        OnPropertyChanged(nameof(FolderCheckText));
        OnPropertyChanged(nameof(WritePermissionText));
        OnPropertyChanged(nameof(DiskSpaceText));
        OnPropertyChanged(nameof(RiskText));
        OnPropertyChanged(nameof(DisabledReason));
        OnPropertyChanged(nameof(StatusText));
    }

    private bool SetProperty<T>(
        ref T storage,
        T value,
        [CallerMemberName] string propertyName = "")
    {
        if (Equals(storage, value))
        {
            return false;
        }

        storage = value;
        OnPropertyChanged(propertyName);
        return true;
    }

    private void OnPropertyChanged([CallerMemberName] string propertyName = "")
    {
        PropertyChanged?.Invoke(this, new PropertyChangedEventArgs(propertyName));
    }
}
