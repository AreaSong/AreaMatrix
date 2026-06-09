using System.ComponentModel;
using System.Runtime.CompilerServices;

namespace AreaMatrix.Linux.Features.Onboarding;

public sealed partial class RepositoryAdoptConfirmViewModel : INotifyPropertyChanged
{
    private readonly ILinuxRepositoryCoreBridge coreBridge;
    private string repositoryPath = string.Empty;
    private bool isChecking;
    private bool isAdopting;
    private bool isMetadataAcknowledged;
    private bool isLocationRiskAcknowledged;
    private LinuxRepositoryValidation? validation;
    private LinuxRepositoryError? error;
    private LinuxRepositoryRoute completedRoute = LinuxRepositoryRoute.None;

    public RepositoryAdoptConfirmViewModel(ILinuxRepositoryCoreBridge coreBridge)
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

    public bool IsLocationRiskAcknowledged
    {
        get => isLocationRiskAcknowledged;
        set
        {
            if (SetProperty(ref isLocationRiskAcknowledged, value))
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

    public bool RequiresLocationRiskAcknowledgement => IsHighRiskPath(Validation);

    public bool CanAdoptRepository => Error is null
        && !IsChecking
        && !IsAdopting
        && IsMetadataAcknowledged
        && (!RequiresLocationRiskAcknowledgement || IsLocationRiskAcknowledged)
        && IsAdoptEligible(Validation);

    public bool CanRetryAdopt => !IsChecking
        && !IsAdopting
        && IsMetadataAcknowledged
        && (!RequiresLocationRiskAcknowledgement || IsLocationRiskAcknowledged)
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
        ? "Existing .areamatrix: Yes"
        : "Existing .areamatrix: No";

    public string LocationTypeText =>
        $"Location type: {RepositoryAdoptConfirmPresentation.PathTypeLabel(Validation)}";

    public string SafetyText => "AreaMatrix will not move, delete, rename, or overwrite existing files.";

    public string MetadataAddText => "It will create a .areamatrix folder for metadata and scan this folder.";

    public string RollbackText => "Removing .areamatrix metadata later must not remove user files.";

    public string AddedDetailsText =>
        ".areamatrix stores metadata, generated overview files, staging state, and the repository database.";

    public string RiskText => RepositoryAdoptConfirmPresentation.RiskTextFor(Validation);

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
                return LinuxRepositoryDisplayText.CheckingFolder;
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
        LinuxRepositoryRoute route,
        CancellationToken cancellationToken = default)
    {
        CompletedRoute = LinuxRepositoryRoute.None;
        Error = null;
        Validation = route.Validation;
        RepositoryPath = route.RepoPath.Trim();
        IsMetadataAcknowledged = false;
        IsLocationRiskAcknowledged = false;

        if (route.Kind != LinuxRepositoryRouteKind.RepositoryAdoptConfirm
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

    public async Task AdoptRepositoryAsync(CancellationToken cancellationToken = default)
    {
        if (!CanAdoptRepository)
        {
            return;
        }

        IsAdopting = true;
        Error = null;
        CompletedRoute = LinuxRepositoryRoute.None;
        try
        {
            await coreBridge
                .AdoptExistingRepositoryAsync(RepositoryPath, cancellationToken)
                .ConfigureAwait(false);
            LinuxRepositoryValidation initialized = await coreBridge
                .ValidateRepoPathAsync(RepositoryPath, cancellationToken)
                .ConfigureAwait(false);
            Validation = initialized;

            if (!initialized.IsInitialized)
            {
                Error = new LinuxRepositoryError(
                    LinuxRepositoryErrorKind.InvalidRepository,
                    "Repository metadata was not detected after preparation.",
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
            IsAdopting = false;
        }
    }

    private void NotifyDisplayPropertiesChanged()
    {
        OnPropertyChanged(nameof(RequiresLocationRiskAcknowledgement));
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
