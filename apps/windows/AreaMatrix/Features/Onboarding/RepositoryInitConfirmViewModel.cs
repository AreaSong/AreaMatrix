using System;
using System.ComponentModel;
using System.Runtime.CompilerServices;
using System.Threading;
using System.Threading.Tasks;

namespace AreaMatrix.Features.Onboarding;

public sealed class RepositoryInitConfirmViewModel : INotifyPropertyChanged
{
    private readonly IWindowsRepositoryCoreBridge coreBridge;
    private string repositoryPath = string.Empty;
    private bool isChecking;
    private bool isCreating;
    private WindowsRepositoryValidation? validation;
    private WindowsRepositoryError? error;
    private WindowsRepositoryRoute completedRoute = WindowsRepositoryRoute.None;

    public RepositoryInitConfirmViewModel(IWindowsRepositoryCoreBridge coreBridge)
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

    public WindowsRepositoryValidation? Validation
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

    public WindowsRepositoryError? Error
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

    public WindowsRepositoryRoute CompletedRoute
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

    public string PathTypeText => $"Type: {PathTypeLabel(Validation?.PlatformPathKind)}";

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
                return Validation.RecommendedMode == WindowsRepositoryInitMode.CreateEmpty
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

    public string RiskText
    {
        get
        {
            return Validation?.PlatformPathKind switch
            {
                WindowsPlatformPathKind.OneDrive
                    => "OneDrive sync is controlled outside AreaMatrix. Review sync risks before creating metadata.",
                WindowsPlatformPathKind.ICloudDrive
                    => "Cloud sync behavior is controlled by the selected provider.",
                WindowsPlatformPathKind.NetworkShare
                    => "Network folders can become unavailable; retry if metadata creation fails.",
                _ => string.Empty
            };
        }
    }

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
                return "Checking folder...";
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
        WindowsRepositoryRoute route,
        CancellationToken cancellationToken = default)
    {
        CompletedRoute = WindowsRepositoryRoute.None;
        Error = null;
        Validation = route.Validation;
        RepositoryPath = route.RepoPath.Trim();

        if (route.Kind != WindowsRepositoryRouteKind.RepositoryInitConfirm
            || string.IsNullOrWhiteSpace(RepositoryPath))
        {
            Error = new WindowsRepositoryError(
                WindowsRepositoryErrorKind.InvalidRepository,
                "Choose a folder first.",
                RepositoryPath);
            return;
        }

        await RefreshValidationAsync(cancellationToken);
    }

    public async Task RefreshValidationAsync(CancellationToken cancellationToken = default)
    {
        if (string.IsNullOrWhiteSpace(RepositoryPath))
        {
            Error = new WindowsRepositoryError(
                WindowsRepositoryErrorKind.InvalidPath,
                "Choose a folder first.",
                RepositoryPath);
            return;
        }

        IsChecking = true;
        Error = null;
        try
        {
            WindowsRepositoryValidation refreshed = await coreBridge
                .ValidateRepoPathAsync(RepositoryPath, cancellationToken);
            Validation = refreshed;
            Error = BlockingErrorFor(refreshed);
        }
        catch (WindowsRepositoryCoreException exception)
        {
            Error = ErrorFromCoreException(exception);
        }
        catch (Exception exception)
        {
            Error = new WindowsRepositoryError(
                WindowsRepositoryErrorKind.Unavailable,
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
        CompletedRoute = WindowsRepositoryRoute.None;
        try
        {
            await coreBridge.InitializeEmptyRepositoryAsync(RepositoryPath, cancellationToken);
            WindowsRepositoryValidation initialized = await coreBridge
                .ValidateRepoPathAsync(RepositoryPath, cancellationToken);
            Validation = initialized;

            if (!initialized.IsInitialized)
            {
                Error = new WindowsRepositoryError(
                    WindowsRepositoryErrorKind.InvalidRepository,
                    "Repository metadata was not detected after creation.",
                    RepositoryPath);
                return;
            }

            WindowsRepositoryConfig config = await coreBridge
                .LoadConfigAsync(RepositoryPath, cancellationToken);
            CompletedRoute = new WindowsRepositoryRoute(
                WindowsRepositoryRouteKind.MainWindow,
                initialized.RepoPath,
                initialized,
                config);
        }
        catch (WindowsRepositoryCoreException exception)
        {
            Error = ErrorFromCoreException(exception);
        }
        catch (Exception exception)
        {
            Error = new WindowsRepositoryError(
                WindowsRepositoryErrorKind.Unavailable,
                exception.Message,
                RepositoryPath);
        }
        finally
        {
            IsCreating = false;
        }
    }

    private static bool IsCreateEmptyEligible(WindowsRepositoryValidation? currentValidation)
    {
        return currentValidation is not null
            && currentValidation.RecommendedMode == WindowsRepositoryInitMode.CreateEmpty
            && currentValidation.IsWritable
            && !currentValidation.IsInitialized
            && !currentValidation.IsInsideAreaMatrix
            && (!currentValidation.Exists
                || (currentValidation.IsDirectory
                    && currentValidation.IsReadable
                    && currentValidation.IsEmpty));
    }

    private static WindowsRepositoryError? BlockingErrorFor(WindowsRepositoryValidation currentValidation)
    {
        if (currentValidation.IsInsideAreaMatrix
            || currentValidation.HasIssue(WindowsRepositoryPathIssue.InsideAreaMatrix))
        {
            return new WindowsRepositoryError(
                WindowsRepositoryErrorKind.InvalidPath,
                "Choose the repository folder, not its .areamatrix metadata folder.",
                currentValidation.RepoPath);
        }

        if (currentValidation.Exists && !currentValidation.IsDirectory)
        {
            return new WindowsRepositoryError(
                WindowsRepositoryErrorKind.SelectedFile,
                "Select a folder, not a file.",
                currentValidation.RepoPath);
        }

        if (currentValidation.Exists && !currentValidation.IsReadable)
        {
            return new WindowsRepositoryError(
                WindowsRepositoryErrorKind.PermissionDenied,
                "AreaMatrix cannot read this folder.",
                currentValidation.RepoPath);
        }

        if (!currentValidation.IsWritable)
        {
            return new WindowsRepositoryError(
                WindowsRepositoryErrorKind.PermissionDenied,
                "AreaMatrix cannot write repository metadata in this folder.",
                currentValidation.RepoPath);
        }

        if (currentValidation.HasIssue(WindowsRepositoryPathIssue.WindowsReservedName))
        {
            return new WindowsRepositoryError(
                WindowsRepositoryErrorKind.InvalidPath,
                "This path contains a reserved Windows name.",
                currentValidation.RepoPath);
        }

        return null;
    }

    private static string DisabledReasonFor(
        WindowsRepositoryValidation? currentValidation,
        WindowsRepositoryError? currentError)
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

        if (currentValidation.RecommendedMode != WindowsRepositoryInitMode.CreateEmpty)
        {
            return "This folder is not eligible for empty repository creation.";
        }

        return BlockingErrorFor(currentValidation)?.Message ?? string.Empty;
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
            WindowsRepositoryErrorKind.DiskUnavailable => "Drive disconnected",
            _ => exception.Message
        };

        return new WindowsRepositoryError(exception.Kind, message, exception.Path);
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
