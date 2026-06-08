using System;
using System.Collections.Generic;
using System.ComponentModel;
using System.Linq;
using System.Runtime.CompilerServices;
using System.Threading;
using System.Threading.Tasks;

namespace AreaMatrix.Features.Onboarding;

public sealed class OneDriveNoticeViewModel : INotifyPropertyChanged
{
    private readonly IWindowsRepositoryCoreBridge coreBridge;
    private WindowsRepositoryValidation? routeValidation;
    private string repositoryPath = string.Empty;
    private bool isChecking;
    private bool isAcknowledging;
    private bool isRiskNoticeConfirmed;
    private WindowsCloudStorageState? cloudState;
    private WindowsRepositoryError? error;
    private IReadOnlyList<string> riskReasons = [];

    public OneDriveNoticeViewModel(IWindowsRepositoryCoreBridge coreBridge)
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

    public bool IsAcknowledging
    {
        get => isAcknowledging;
        private set
        {
            if (SetProperty(ref isAcknowledging, value))
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

    public WindowsCloudStorageState? CloudState
    {
        get => cloudState;
        private set
        {
            if (SetProperty(ref cloudState, value))
            {
                RiskReasons = value?.RiskReasons.Where(item => !string.IsNullOrWhiteSpace(item)).ToArray()
                    ?? [];
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

    public IReadOnlyList<string> RiskReasons
    {
        get => riskReasons;
        private set
        {
            if (SetProperty(ref riskReasons, value))
            {
                NotifyDisplayPropertiesChanged();
            }
        }
    }

    public bool ShouldShowConfirmation => CloudState?.RequiresOneDriveNotice == true
        || CloudState?.RecommendedAction == WindowsCloudStorageRecommendedAction.AcknowledgeNotice;

    public bool ShouldShowConnectedActions => !ShouldShowConfirmation
        && !IsChecking
        && !IsAcknowledging
        && !string.IsNullOrWhiteSpace(RepositoryPath)
        && CloudState?.ProviderKind == WindowsCloudStorageProviderKind.OneDrive;

    public bool CanOpenWatcherStatus => ShouldShowConnectedActions && Error is null;

    public bool CanContinueWithOneDrive
    {
        get
        {
            return ShouldShowConfirmation
                && IsRiskNoticeConfirmed
                && !IsChecking
                && !IsAcknowledging
                && Error is null
                && CloudState?.ProviderKind == WindowsCloudStorageProviderKind.OneDrive;
        }
    }

    public string ContinueDisabledReason
    {
        get
        {
            if (!ShouldShowConfirmation)
            {
                return string.Empty;
            }

            if (IsAcknowledging)
            {
                return "Saving OneDrive acknowledgement...";
            }

            if (IsChecking)
            {
                return "Checking OneDrive status...";
            }

            if (Error is { } currentError)
            {
                return currentError.Message;
            }

            if (CloudState?.ProviderKind != WindowsCloudStorageProviderKind.OneDrive)
            {
                return "This folder is no longer detected as OneDrive.";
            }

            return IsRiskNoticeConfirmed
                ? string.Empty
                : "Confirm OneDrive sync risks before continuing.";
        }
    }

    public string FolderText
    {
        get
        {
            return string.IsNullOrWhiteSpace(RepositoryPath)
                ? "Choose a folder first."
                : $"Folder: {RepositoryPath}";
        }
    }

    public string SyncProviderText
    {
        get
        {
            return CloudState?.ProviderKind switch
            {
                WindowsCloudStorageProviderKind.OneDrive => "Sync provider: OneDrive",
                WindowsCloudStorageProviderKind.ICloudDrive => "Sync provider: iCloud Drive",
                WindowsCloudStorageProviderKind.Local => "Sync provider: Local",
                WindowsCloudStorageProviderKind.Unknown => "Sync provider: Unknown",
                _ => "Sync provider: OneDrive"
            };
        }
    }

    public string StatusText
    {
        get
        {
            return IsChecking
                ? "Status: Checking OneDrive status..."
                : $"Status: {StatusLabel()}";
        }
    }

    public string StatusSummary
    {
        get
        {
            if (IsAcknowledging)
            {
                return "Saving OneDrive risk acknowledgement...";
            }

            if (IsChecking)
            {
                return "Checking OneDrive status...";
            }

            if (Error is { } currentError)
            {
                return $"{currentError.Message} AreaMatrix cannot control OneDrive sync timing.";
            }

            string? summary = CloudState?.StatusSummary;
            if (!string.IsNullOrWhiteSpace(summary))
            {
                return summary;
            }

            return "AreaMatrix cannot control OneDrive sync timing.";
        }
    }

    public string ErrorText => Error?.Message ?? string.Empty;

    public bool CanRetryStatusCheck
    {
        get
        {
            return !IsChecking
                && !IsAcknowledging
                && !string.IsNullOrWhiteSpace(RepositoryPath)
                && (CloudState?.CanRetry == true || Error is not null);
        }
    }

    public bool CanOpenOneDriveFolder
    {
        get
        {
            return !IsChecking
                && !IsAcknowledging
                && !string.IsNullOrWhiteSpace(RepositoryPath)
                && Error?.Kind is not WindowsRepositoryErrorKind.InvalidPath
                && Error?.Kind is not WindowsRepositoryErrorKind.FileNotFound;
        }
    }

    public async Task LoadRouteAsync(
        WindowsRepositoryRoute route,
        CancellationToken cancellationToken = default)
    {
        routeValidation = route.Validation;
        RepositoryPath = route.RepoPath;
        IsRiskNoticeConfirmed = false;
        Error = null;
        CloudState = route.CloudStorageState;

        if (string.IsNullOrWhiteSpace(RepositoryPath))
        {
            Error = new WindowsRepositoryError(
                WindowsRepositoryErrorKind.InvalidPath,
                "Choose a folder first.");
            return;
        }

        if (CloudState is null)
        {
            await RetryStatusCheckAsync(cancellationToken).ConfigureAwait(false);
            return;
        }

        ApplyStateError(CloudState);
    }

    public async Task RetryStatusCheckAsync(CancellationToken cancellationToken = default)
    {
        if (string.IsNullOrWhiteSpace(RepositoryPath))
        {
            Error = new WindowsRepositoryError(
                WindowsRepositoryErrorKind.InvalidPath,
                "Choose a folder first.");
            return;
        }

        IsChecking = true;
        Error = null;
        try
        {
            WindowsCloudStorageState state = await coreBridge
                .DetectCloudStorageStateAsync(RepositoryPath, cancellationToken)
                .ConfigureAwait(false);

            IsRiskNoticeConfirmed = false;
            CloudState = state;
            ApplyStateError(state);
        }
        catch (OperationCanceledException) when (cancellationToken.IsCancellationRequested)
        {
        }
        catch (WindowsRepositoryCoreException exception)
        {
            CloudState = null;
            RiskReasons = [];
            Error = ErrorFromCoreException(exception);
        }
        catch (Exception exception)
        {
            CloudState = null;
            RiskReasons = [];
            Error = new WindowsRepositoryError(
                WindowsRepositoryErrorKind.Unavailable,
                $"Checking OneDrive status failed: {exception.Message}",
                RepositoryPath);
        }
        finally
        {
            IsChecking = false;
        }
    }

    public async Task<bool> ContinueWithOneDriveAsync(CancellationToken cancellationToken = default)
    {
        if (!CanContinueWithOneDrive)
        {
            return false;
        }

        if (routeValidation?.IsInitialized != true)
        {
            return true;
        }

        IsAcknowledging = true;
        Error = null;
        try
        {
            WindowsCloudStorageState state = await coreBridge
                .AcknowledgeOneDriveRiskNoticeAsync(RepositoryPath, cancellationToken)
                .ConfigureAwait(false);

            CloudState = state;
            ApplyStateError(state);
            return Error is null
                && state.NoticeAcknowledged
                && !state.RequiresNoticeAcknowledgement
                && state.RecommendedAction == WindowsCloudStorageRecommendedAction.None;
        }
        catch (OperationCanceledException) when (cancellationToken.IsCancellationRequested)
        {
            return false;
        }
        catch (WindowsRepositoryCoreException exception)
        {
            Error = ErrorFromCoreException(exception);
            return false;
        }
        catch (Exception exception)
        {
            Error = new WindowsRepositoryError(
                WindowsRepositoryErrorKind.Unavailable,
                $"Saving OneDrive acknowledgement failed: {exception.Message}",
                RepositoryPath);
            return false;
        }
        finally
        {
            IsAcknowledging = false;
        }
    }

    public void ReportOpenFolderError(Exception exception)
    {
        Error = new WindowsRepositoryError(
            WindowsRepositoryErrorKind.Unavailable,
            $"Open OneDrive folder failed: {exception.Message}",
            RepositoryPath);
    }

    private void ApplyStateError(WindowsCloudStorageState state)
    {
        Error = StateError(state);
    }

    private WindowsRepositoryError? StateError(WindowsCloudStorageState state)
    {
        if (state.ProviderKind != WindowsCloudStorageProviderKind.OneDrive)
        {
            return new WindowsRepositoryError(
                WindowsRepositoryErrorKind.InvalidPath,
                "This folder is no longer detected as OneDrive.",
                state.RepoPath);
        }

        if (state.PermissionState == WindowsCloudPermissionState.PermissionDenied)
        {
            return new WindowsRepositoryError(
                WindowsRepositoryErrorKind.PermissionDenied,
                "AreaMatrix cannot read OneDrive metadata for this folder.",
                state.RepoPath);
        }

        if (state.PermissionState == WindowsCloudPermissionState.AccessExpired
            || state.RequiresReconnect)
        {
            return new WindowsRepositoryError(
                WindowsRepositoryErrorKind.PermissionDenied,
                "Reconnect this folder before continuing.",
                state.RepoPath);
        }

        return null;
    }

    private string StatusLabel()
    {
        if (Error is not null || CloudState is null)
        {
            return "Unknown";
        }

        if (CloudState.PermissionState != WindowsCloudPermissionState.Accessible
            || CloudState.PlaceholderState == WindowsCloudPlaceholderState.Unknown
            || CloudState.Risk == WindowsCloudStorageRiskLevel.Unknown)
        {
            return "Unknown";
        }

        return "Available";
    }

    private WindowsRepositoryError ErrorFromCoreException(WindowsRepositoryCoreException exception)
    {
        string message = exception.Kind switch
        {
            WindowsRepositoryErrorKind.PermissionDenied
                => "AreaMatrix cannot read OneDrive metadata for this folder.",
            WindowsRepositoryErrorKind.InvalidPath or WindowsRepositoryErrorKind.FileNotFound
                => "Folder not found.",
            WindowsRepositoryErrorKind.DiskUnavailable
                => "Drive disconnected.",
            WindowsRepositoryErrorKind.Config
                => "This repository configuration cannot be opened.",
            _ => "Checking OneDrive status failed."
        };

        return new WindowsRepositoryError(exception.Kind, message, exception.Path ?? RepositoryPath);
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

    private void NotifyDisplayPropertiesChanged()
    {
        OnPropertyChanged(nameof(FolderText));
        OnPropertyChanged(nameof(SyncProviderText));
        OnPropertyChanged(nameof(StatusText));
        OnPropertyChanged(nameof(StatusSummary));
        OnPropertyChanged(nameof(ErrorText));
        OnPropertyChanged(nameof(CanRetryStatusCheck));
        OnPropertyChanged(nameof(CanOpenOneDriveFolder));
        OnPropertyChanged(nameof(ShouldShowConfirmation));
        OnPropertyChanged(nameof(ShouldShowConnectedActions));
        OnPropertyChanged(nameof(CanOpenWatcherStatus));
        OnPropertyChanged(nameof(CanContinueWithOneDrive));
        OnPropertyChanged(nameof(ContinueDisabledReason));
    }

    private void OnPropertyChanged([CallerMemberName] string propertyName = "")
    {
        PropertyChanged?.Invoke(this, new PropertyChangedEventArgs(propertyName));
    }
}
