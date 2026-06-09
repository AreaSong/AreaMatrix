using System;
using System.ComponentModel;
using System.Runtime.CompilerServices;
using System.Threading;
using System.Threading.Tasks;

namespace AreaMatrix.Features.Onboarding;

public sealed partial class RepositoryAdoptConfirmViewModel : INotifyPropertyChanged
{
    private readonly IWindowsRepositoryCoreBridge coreBridge;
    private string repositoryPath = string.Empty;
    private bool isChecking;
    private bool isAdopting;
    private bool isMetadataAcknowledged;
    private bool isSyncRiskAcknowledged;
    private WindowsRepositoryValidation? validation;
    private WindowsRepositoryError? error;
    private WindowsRepositoryRoute completedRoute = WindowsRepositoryRoute.None;

    public RepositoryAdoptConfirmViewModel(IWindowsRepositoryCoreBridge coreBridge)
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

    public bool IsAdopting
    {
        get => isAdopting;
        private set
        {
            if (SetProperty(ref isAdopting, value))
            {
                NotifyDisplayPropertiesChanged();
            }
        }
    }

    public bool IsMetadataAcknowledged
    {
        get => isMetadataAcknowledged;
        set
        {
            if (SetProperty(ref isMetadataAcknowledged, value))
            {
                NotifyDisplayPropertiesChanged();
            }
        }
    }

    public bool IsSyncRiskAcknowledged
    {
        get => isSyncRiskAcknowledged;
        set
        {
            if (SetProperty(ref isSyncRiskAcknowledged, value))
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

    public bool RequiresSyncRiskAcknowledgement => IsSyncRiskPath(Validation);

    public bool CanAdoptRepository => Error is null
        && !IsChecking
        && !IsAdopting
        && IsMetadataAcknowledged
        && (!RequiresSyncRiskAcknowledgement || IsSyncRiskAcknowledged)
        && IsAdoptEligible(Validation);

    public bool CanRetryAdopt => !IsChecking
        && !IsAdopting
        && IsMetadataAcknowledged
        && (!RequiresSyncRiskAcknowledgement || IsSyncRiskAcknowledged)
        && IsAdoptEligible(Validation);

    public string FolderText => string.IsNullOrWhiteSpace(RepositoryPath)
        ? "Folder: Choose a folder first."
        : $"Folder: {RepositoryPath}";

    public string EstimatedItemsText => Validation switch
    {
        null => "Estimated items: Unknown",
        { IsEmpty: true } => "Estimated items: No existing user-visible files detected.",
        _ => "Estimated items: Existing files detected by Core validation."
    };

    public string WritableText => Validation?.IsWritable == true
        ? "Writable: Yes"
        : "Writable: No";

    public string MetadataText => Validation?.IsInitialized == true
        ? "Existing metadata: Yes"
        : "Existing metadata: No";

    public string LocationTypeText => $"Location type: {PathTypeLabel(Validation?.PlatformPathKind)}";

    public string SafetyText => "AreaMatrix will not move, delete, rename, or overwrite existing files.";

    public string MetadataAddText => "It will create a .areamatrix folder for metadata and scan this folder.";

    public string RollbackText => "Removing .areamatrix metadata later must not remove user files.";

    public string AddedDetailsText =>
        ".areamatrix stores metadata, generated overview files, staging state, and the repository database.";

    public string RiskText => Validation?.PlatformPathKind switch
    {
        WindowsPlatformPathKind.OneDrive
            => "OneDrive sync is controlled outside AreaMatrix. AreaMatrix will not change OneDrive settings.",
        WindowsPlatformPathKind.ICloudDrive
            => "Cloud sync behavior is controlled by the selected provider.",
        WindowsPlatformPathKind.NetworkShare
            => "Network folders can become unavailable while metadata is being created.",
        _ => string.Empty
    };

    public string DisabledReason => DisabledReasonFor(Validation, Error, this);

    public string StatusText
    {
        get
        {
            if (IsAdopting)
            {
                return "Preparing repository...";
            }

            if (IsChecking)
            {
                return "Checking folder...";
            }

            if (Error is { } currentError)
            {
                return currentError.Message;
            }

            return CanAdoptRepository
                ? "Ready to use this folder."
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
        IsMetadataAcknowledged = false;
        IsSyncRiskAcknowledged = false;

        if (route.Kind != WindowsRepositoryRouteKind.RepositoryAdoptConfirm
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

    public async Task AdoptRepositoryAsync(CancellationToken cancellationToken = default)
    {
        if (!CanAdoptRepository)
        {
            return;
        }

        IsAdopting = true;
        Error = null;
        CompletedRoute = WindowsRepositoryRoute.None;
        try
        {
            await coreBridge.AdoptExistingRepositoryAsync(RepositoryPath, cancellationToken);
            await CompleteAdoptedRepositoryAsync(cancellationToken);
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
            IsAdopting = false;
        }
    }

    private async Task CompleteAdoptedRepositoryAsync(CancellationToken cancellationToken)
    {
        WindowsRepositoryValidation initialized = await coreBridge
            .ValidateRepoPathAsync(RepositoryPath, cancellationToken);
        Validation = initialized;

        if (!initialized.IsInitialized)
        {
            Error = new WindowsRepositoryError(
                WindowsRepositoryErrorKind.InvalidRepository,
                "Repository metadata was not detected after adoption.",
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

    private void NotifyDisplayPropertiesChanged()
    {
        OnPropertyChanged(nameof(RequiresSyncRiskAcknowledgement));
        OnPropertyChanged(nameof(CanAdoptRepository));
        OnPropertyChanged(nameof(CanRetryAdopt));
        OnPropertyChanged(nameof(FolderText));
        OnPropertyChanged(nameof(EstimatedItemsText));
        OnPropertyChanged(nameof(WritableText));
        OnPropertyChanged(nameof(MetadataText));
        OnPropertyChanged(nameof(LocationTypeText));
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
