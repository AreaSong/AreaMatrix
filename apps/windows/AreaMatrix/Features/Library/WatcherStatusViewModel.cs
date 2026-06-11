using System;
using System.Collections.Generic;
using System.ComponentModel;
using System.Runtime.CompilerServices;
using System.Threading;
using System.Threading.Tasks;
using AreaMatrix.Features.Onboarding;

namespace AreaMatrix.Features.Library;

public sealed partial class WatcherStatusViewModel : INotifyPropertyChanged
{
    private readonly IWatcherStatusCoreBridge coreBridge;
    private readonly IWindowsWatcherDiagnostics diagnostics;
    private string repoPath = string.Empty;
    private WatcherStatusSnapshot? snapshot;
    private ManualRescanPreviewReport? rescanPreview;
    private ScanSession? latestScanSession;
    private bool isLoading;
    private bool isRestarting;
    private bool isPreparingRescan;
    private WindowsRepositoryError? error;

    public WatcherStatusViewModel(
        IWatcherStatusCoreBridge coreBridge,
        IWindowsWatcherDiagnostics diagnostics)
    {
        this.coreBridge = coreBridge;
        this.diagnostics = diagnostics;
    }

    public event PropertyChangedEventHandler? PropertyChanged;

    public string RepoPath
    {
        get => repoPath;
        private set
        {
            if (SetProperty(ref repoPath, value))
            {
                NotifyDisplayPropertiesChanged();
            }
        }
    }

    public WatcherStatusSnapshot? Snapshot
    {
        get => snapshot;
        private set
        {
            if (SetProperty(ref snapshot, value))
            {
                NotifyDisplayPropertiesChanged();
            }
        }
    }

    public ManualRescanPreviewReport? RescanPreview
    {
        get => rescanPreview;
        private set
        {
            if (SetProperty(ref rescanPreview, value))
            {
                NotifyDisplayPropertiesChanged();
            }
        }
    }

    public ScanSession? LatestScanSession
    {
        get => latestScanSession;
        private set
        {
            if (SetProperty(ref latestScanSession, value))
            {
                NotifyDisplayPropertiesChanged();
            }
        }
    }

    public bool IsLoading
    {
        get => isLoading;
        private set
        {
            if (SetProperty(ref isLoading, value))
            {
                NotifyDisplayPropertiesChanged();
            }
        }
    }

    public bool IsRestarting
    {
        get => isRestarting;
        private set
        {
            if (SetProperty(ref isRestarting, value))
            {
                NotifyDisplayPropertiesChanged();
            }
        }
    }

    public bool IsPreparingRescan
    {
        get => isPreparingRescan;
        private set
        {
            if (SetProperty(ref isPreparingRescan, value))
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

    public IReadOnlyList<WatcherStatusEventSample> RecentEvents => Snapshot?.RecentEvents ?? [];

    public string StatusText
    {
        get
        {
            if (IsLoading)
            {
                return "Checking watcher status...";
            }

            if (IsRestarting)
            {
                return "Restarting watcher...";
            }

            if (IsPreparingRescan)
            {
                return "Preparing rescan preview...";
            }

            return Snapshot?.StatusText ?? "Status: Unavailable";
        }
    }

    public string WatchingText => Snapshot?.WatchingText
        ?? (string.IsNullOrWhiteSpace(RepoPath)
            ? "File watcher is not available for this repository."
            : $"Watching: {RepoPath}");

    public string LastEventText => Snapshot?.LastEventText ?? "Last event: Unknown";

    public string PendingEventsText => Snapshot?.PendingEventsText ?? "Pending events: 0";

    public string LastRescanText => Snapshot?.LastRescanText ?? "Last rescan: Unknown";

    public string LastSyncText => Snapshot?.LastSyncText ?? "Last sync: Unknown";

    public string BackendText => Snapshot?.BackendText ?? "Backend: Unknown";

    public string WatchCountText => Snapshot?.WatchCountText ?? "Watch count: Unknown";

    public string RescanPreviewText
    {
        get
        {
            if (RescanPreview is { } preview)
            {
                return preview.SummaryText;
            }

            return "Run rescan now opens confirmation after a read-only preview.";
        }
    }

    public string LatestScanSessionText => LatestScanSession?.DisplayText
        ?? "Latest rescan session: None.";

    public string SummaryText
    {
        get
        {
            if (Error is { } currentError)
            {
                return currentError.Message;
            }

            return Snapshot?.SummaryText ?? "File watcher is not available for this repository.";
        }
    }

    public string RecoveryText
    {
        get
        {
            if (Snapshot?.IsPathMissing == true)
            {
                return "Choose the repository again or reconnect the drive.";
            }

            if (Snapshot?.HasDatabaseLock == true)
            {
                return "Wait for the database operation to finish before running recovery actions.";
            }

            if (Snapshot?.Status == WatcherStatusKind.Paused)
            {
                return "Restart the watcher or run a confirmed rescan if changes are missing.";
            }

            if (Snapshot?.Status == WatcherStatusKind.Error)
            {
                return "Restart the watcher. If the path is unavailable, reconnect the drive first.";
            }

            return "Watcher status is current.";
        }
    }

    public string OneDriveNoticeText => Snapshot?.HasOneDriveNoise == true
        ? "OneDrive may generate bursts of file events."
        : string.Empty;

    public bool HasOneDriveNotice => !string.IsNullOrWhiteSpace(OneDriveNoticeText);

    public bool HasRecentEvents => RecentEvents.Count > 0 && Snapshot?.IsBackendUnavailable != true;

    public bool CanOpenRescanConfirm
    {
        get
        {
            return !IsBusy
                && Snapshot is not null
                && !IsWatcherStarting
                && !IsRescanRunning
                && Snapshot.PendingEventCount >= 0
                && !Snapshot.IsPathMissing
                && !Snapshot.HasDatabaseLock
                && !Snapshot.IsBackendUnavailable;
        }
    }

    public string RescanDisabledReason
    {
        get
        {
            if (IsBusy)
            {
                return "Checking watcher status...";
            }

            if (Snapshot is null || Snapshot.IsBackendUnavailable)
            {
                return "Watcher snapshot is unavailable.";
            }

            if (IsWatcherStarting)
            {
                return "Wait for the watcher to finish starting.";
            }

            if (IsRescanRunning)
            {
                return "A manual rescan is already running.";
            }

            if (Snapshot.IsPathMissing)
            {
                return "Reconnect the repository path before running a rescan.";
            }

            if (Snapshot.HasDatabaseLock)
            {
                return "Wait for the database lock to clear before running a rescan.";
            }

            return "Opens rescan confirmation before scanning.";
        }
    }

    public async Task OpenRouteAsync(
        WindowsRepositoryRoute route,
        CancellationToken cancellationToken = default)
    {
        RepoPath = route.RepoPath;
        Snapshot = null;
        RescanPreview = null;
        LatestScanSession = null;
        Error = null;
        await RefreshAsync(cancellationToken).ConfigureAwait(false);
    }

    public async Task RefreshAsync(CancellationToken cancellationToken = default)
    {
        if (string.IsNullOrWhiteSpace(RepoPath))
        {
            Error = new WindowsRepositoryError(
                WindowsRepositoryErrorKind.InvalidPath,
                "File watcher is not available for this repository.");
            return;
        }

        IsLoading = true;
        Error = null;
        try
        {
            WatcherStatusHealthSignal signal = await diagnostics
                .CaptureSnapshotAsync(RepoPath, cancellationToken)
                .ConfigureAwait(false);
            Snapshot = await coreBridge
                .RecordWatcherHealthAsync(RepoPath, signal, cancellationToken)
                .ConfigureAwait(false);
            LatestScanSession = await coreBridge
                .GetLatestScanSessionAsync(RepoPath, cancellationToken)
                .ConfigureAwait(false);
        }
        catch (Exception exception) when (exception is not OperationCanceledException)
        {
            Error = ErrorFromException(exception);
        }
        finally
        {
            IsLoading = false;
        }
    }

    public async Task RestartWatcherAsync(CancellationToken cancellationToken = default)
    {
        if (!CanRestartWatcher)
        {
            return;
        }

        IsRestarting = true;
        Error = null;
        try
        {
            WatcherStatusHealthSignal signal = await diagnostics
                .RestartWatcherAsync(RepoPath, cancellationToken)
                .ConfigureAwait(false);
            Snapshot = await coreBridge
                .RecordWatcherHealthAsync(RepoPath, signal, cancellationToken)
                .ConfigureAwait(false);
            LatestScanSession = await coreBridge
                .GetLatestScanSessionAsync(RepoPath, cancellationToken)
                .ConfigureAwait(false);
        }
        catch (Exception exception) when (exception is not OperationCanceledException)
        {
            Error = ErrorFromException(exception);
        }
        finally
        {
            IsRestarting = false;
        }
    }

    public async Task<bool> PrepareRescanConfirmAsync(CancellationToken cancellationToken = default)
    {
        if (!CanOpenRescanConfirm)
        {
            return false;
        }

        IsPreparingRescan = true;
        Error = null;
        try
        {
            LatestScanSession = await coreBridge
                .GetLatestScanSessionAsync(RepoPath, cancellationToken)
                .ConfigureAwait(false);
            if (IsRescanRunning)
            {
                return false;
            }

            RescanPreview = await coreBridge
                .PreviewManualRescanAsync(RepoPath, cancellationToken)
                .ConfigureAwait(false);
            return true;
        }
        catch (Exception exception) when (exception is not OperationCanceledException)
        {
            Error = ErrorFromException(exception);
            return false;
        }
        finally
        {
            IsPreparingRescan = false;
        }
    }

    public void ReportPlatformActionError(string action, Exception exception)
    {
        Error = new WindowsRepositoryError(
            WindowsRepositoryErrorKind.Unavailable,
            $"{action} failed: {exception.Message}",
            RepoPath);
    }

    private WindowsRepositoryError ErrorFromException(Exception exception)
    {
        if (exception is WatcherStatusCoreException watcherException)
        {
            return new WindowsRepositoryError(
                watcherException.Kind,
                ErrorMessageFor(watcherException.Kind),
                watcherException.Path ?? RepoPath);
        }

        if (exception is WindowsRepositoryCoreException coreException)
        {
            return new WindowsRepositoryError(
                coreException.Kind,
                ErrorMessageFor(coreException.Kind),
                coreException.Path ?? RepoPath);
        }

        return new WindowsRepositoryError(
            WindowsRepositoryErrorKind.Unavailable,
            $"Checking watcher status failed: {exception.Message}",
            RepoPath);
    }

    private static string ErrorMessageFor(WindowsRepositoryErrorKind kind)
    {
        return kind switch
        {
            WindowsRepositoryErrorKind.Db => "Repository database could not be read.",
            WindowsRepositoryErrorKind.PermissionDenied => "AreaMatrix cannot read watcher metadata.",
            WindowsRepositoryErrorKind.InvalidPath or WindowsRepositoryErrorKind.FileNotFound
                => "Repository folder not found.",
            WindowsRepositoryErrorKind.Config => "Watcher status metadata cannot be decoded.",
            _ => "Checking watcher status failed."
        };
    }

    private bool SetProperty<T>(
        ref T storage,
        T value,
        [CallerMemberName] string propertyName = "")
    {
        if (EqualityComparer<T>.Default.Equals(storage, value))
        {
            return false;
        }

        storage = value;
        OnPropertyChanged(propertyName);
        return true;
    }

    private void NotifyDisplayPropertiesChanged()
    {
        OnPropertyChanged(nameof(RecentEvents));
        OnPropertyChanged(nameof(StatusText));
        OnPropertyChanged(nameof(WatchingText));
        OnPropertyChanged(nameof(LastEventText));
        OnPropertyChanged(nameof(PendingEventsText));
        OnPropertyChanged(nameof(LastRescanText));
        OnPropertyChanged(nameof(LastSyncText));
        OnPropertyChanged(nameof(BackendText));
        OnPropertyChanged(nameof(WatchCountText));
        OnPropertyChanged(nameof(RescanPreviewText));
        OnPropertyChanged(nameof(LatestScanSessionText));
        OnPropertyChanged(nameof(SummaryText));
        OnPropertyChanged(nameof(RecoveryText));
        OnPropertyChanged(nameof(OneDriveNoticeText));
        OnPropertyChanged(nameof(HasOneDriveNotice));
        OnPropertyChanged(nameof(HasRecentEvents));
        OnPropertyChanged(nameof(IsBusy));
        OnPropertyChanged(nameof(IsWatcherStarting));
        OnPropertyChanged(nameof(CanRestartWatcher));
        OnPropertyChanged(nameof(IsRescanRunning));
        OnPropertyChanged(nameof(CanOpenRescanConfirm));
        OnPropertyChanged(nameof(RescanDisabledReason));
        OnPropertyChanged(nameof(CanExportDiagnostics));
        OnPropertyChanged(nameof(CanOpenRepositoryFolder));
        OnPropertyChanged(nameof(LastDiagnosticsExportPath));
    }

    private void OnPropertyChanged([CallerMemberName] string propertyName = "")
    {
        PropertyChanged?.Invoke(this, new PropertyChangedEventArgs(propertyName));
    }
}
