using System.ComponentModel;
using System.Runtime.CompilerServices;
using AreaMatrix.Linux.Features.Onboarding;

namespace AreaMatrix.Linux.Features.System;

public sealed partial class LinuxWatcherStatusViewModel : INotifyPropertyChanged
{
    private readonly ILinuxWatcherStatusCoreBridge coreBridge;
    private readonly ILinuxWatcherDiagnostics diagnostics;
    private string repoPath = string.Empty;
    private LinuxWatcherStatusSnapshot? snapshot;
    private bool isLoading;
    private bool isRestarting;
    private bool isExporting;
    private LinuxRepositoryError? error;

    public LinuxWatcherStatusViewModel(
        ILinuxWatcherStatusCoreBridge coreBridge,
        ILinuxWatcherDiagnostics diagnostics)
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

    public LinuxWatcherStatusSnapshot? Snapshot
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

    public bool IsExporting
    {
        get => isExporting;
        private set
        {
            if (SetProperty(ref isExporting, value))
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

    public string? LastDiagnosticsExportPath { get; private set; }

    public IReadOnlyList<LinuxWatcherStatusEventSample> RecentEvents => Snapshot?.RecentEvents ?? [];

    public bool IsBusy => IsLoading || IsRestarting || IsPreparingRescan || IsExporting;

    public bool IsWatcherStarting => Snapshot?.Status == LinuxWatcherStatusKind.Starting;

    public bool CanRestartWatcher => !IsBusy
        && !IsWatcherStarting
        && Snapshot?.IsBackendUnavailable != true;

    public bool CanExportDiagnostics => !IsBusy && Snapshot is not null;

    public bool CanOpenRepositoryFolder => !IsBusy
        && Snapshot is not null
        && !Snapshot.IsPathMissing
        && !string.IsNullOrWhiteSpace(RepoPath);

    public bool HasRecentEvents => RecentEvents.Count > 0 && Snapshot?.IsBackendUnavailable != true;

    public bool HasNetworkMountNotice => Snapshot?.HasNetworkMount == true;

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

            if (IsExporting)
            {
                return "Exporting diagnostics...";
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

    public string BackendText => Snapshot?.BackendText ?? "Backend: Unknown";

    public string WatchCountText => Snapshot?.WatchCountText ?? "Watches: Unknown";

    public string LastEventText => Snapshot?.LastEventText ?? "Last event: Unknown";

    public string LastSyncText => Snapshot?.LastSyncText ?? "Last sync: Unknown";

    public string LastRescanText => Snapshot?.LastRescanText ?? "Last rescan: Unknown";

    public string PendingEventsText => Snapshot?.PendingEventsText ?? "Pending events: 0";

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
            if (Snapshot?.HasLimitExceeded == true)
            {
                return "Reduce watched folders or review Linux inotify limits. AreaMatrix will not run sudo.";
            }

            if (Snapshot?.HasPermissionDenied == true)
            {
                return "Check folder permissions before restarting the watcher.";
            }

            if (Snapshot?.IsPathMissing == true)
            {
                return "Choose the repository again or reconnect the drive.";
            }

            if (Snapshot?.HasDatabaseLock == true)
            {
                return "Wait for the database operation to finish before running recovery actions.";
            }

            if (Snapshot?.HasNetworkMount == true)
            {
                return "Network mounts may miss events. Use manual rescan confirmation if files are stale.";
            }

            if (Snapshot?.Status == LinuxWatcherStatusKind.Paused)
            {
                return "Restart the watcher or open rescan confirmation if changes are missing.";
            }

            if (Snapshot?.Status == LinuxWatcherStatusKind.Error)
            {
                return "Restart the watcher after resolving the displayed error.";
            }

            return "Watcher status is current.";
        }
    }

    public string NetworkMountNoticeText => HasNetworkMountNotice
        ? "This location may not report all file changes."
        : string.Empty;

    public async Task OpenRouteAsync(
        LinuxRepositoryRoute route,
        CancellationToken cancellationToken = default)
    {
        RepoPath = route.RepoPath;
        Snapshot = null;
        RescanPreview = null;
        LatestScanSession = null;
        Error = null;
        LastDiagnosticsExportPath = null;
        await RefreshAsync(cancellationToken).ConfigureAwait(false);
    }

    public async Task RefreshAsync(CancellationToken cancellationToken = default)
    {
        if (string.IsNullOrWhiteSpace(RepoPath))
        {
            Error = new LinuxRepositoryError(
                LinuxRepositoryErrorKind.InvalidPath,
                "File watcher is not available for this repository.");
            return;
        }

        IsLoading = true;
        Error = null;
        try
        {
            LinuxWatcherStatusHealthSignal signal = await diagnostics
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
            LinuxWatcherStatusHealthSignal signal = await diagnostics
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

    public async Task<bool> ExportDiagnosticsAsync(CancellationToken cancellationToken = default)
    {
        if (!CanExportDiagnostics || Snapshot is null)
        {
            return false;
        }

        IsExporting = true;
        Error = null;
        try
        {
            LastDiagnosticsExportPath = await diagnostics
                .ExportDiagnosticsAsync(RepoPath, Snapshot, cancellationToken)
                .ConfigureAwait(false);
            OnPropertyChanged(nameof(LastDiagnosticsExportPath));
            return true;
        }
        catch (Exception exception) when (exception is not OperationCanceledException)
        {
            Error = ErrorFromException(exception);
            return false;
        }
        finally
        {
            IsExporting = false;
        }
    }

    public async Task<bool> OpenRepositoryFolderAsync(CancellationToken cancellationToken = default)
    {
        if (!CanOpenRepositoryFolder)
        {
            return false;
        }

        Error = null;
        try
        {
            await diagnostics
                .OpenRepositoryFolderAsync(RepoPath, cancellationToken)
                .ConfigureAwait(false);
            return true;
        }
        catch (Exception exception) when (exception is not OperationCanceledException)
        {
            Error = ErrorFromException(exception);
            return false;
        }
    }

    private LinuxRepositoryError ErrorFromException(Exception exception)
    {
        if (exception is LinuxWatcherStatusCoreException watcherException)
        {
            return new LinuxRepositoryError(
                watcherException.Kind,
                ErrorMessageFor(watcherException.Kind),
                watcherException.Path ?? RepoPath);
        }

        if (exception is LinuxRepositoryCoreException coreException)
        {
            return new LinuxRepositoryError(
                coreException.Kind,
                ErrorMessageFor(coreException.Kind),
                coreException.Path ?? RepoPath);
        }

        return new LinuxRepositoryError(
            LinuxRepositoryErrorKind.Unavailable,
            $"Checking watcher status failed: {exception.Message}",
            RepoPath);
    }

    private static string ErrorMessageFor(LinuxRepositoryErrorKind kind)
    {
        return kind switch
        {
            LinuxRepositoryErrorKind.Db => "Repository database could not be read.",
            LinuxRepositoryErrorKind.PermissionDenied => "AreaMatrix cannot read watcher metadata.",
            LinuxRepositoryErrorKind.InvalidPath or LinuxRepositoryErrorKind.FileNotFound
                => "Repository folder not found.",
            LinuxRepositoryErrorKind.Config => "Watcher status metadata cannot be decoded.",
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
        OnPropertyChanged(nameof(IsBusy));
        OnPropertyChanged(nameof(IsWatcherStarting));
        OnPropertyChanged(nameof(IsRescanRunning));
        OnPropertyChanged(nameof(CanRestartWatcher));
        OnPropertyChanged(nameof(CanExportDiagnostics));
        OnPropertyChanged(nameof(CanOpenRepositoryFolder));
        OnPropertyChanged(nameof(CanOpenRescanConfirm));
        OnPropertyChanged(nameof(HasRecentEvents));
        OnPropertyChanged(nameof(HasNetworkMountNotice));
        OnPropertyChanged(nameof(StatusText));
        OnPropertyChanged(nameof(WatchingText));
        OnPropertyChanged(nameof(BackendText));
        OnPropertyChanged(nameof(WatchCountText));
        OnPropertyChanged(nameof(LastEventText));
        OnPropertyChanged(nameof(LastSyncText));
        OnPropertyChanged(nameof(LastRescanText));
        OnPropertyChanged(nameof(PendingEventsText));
        OnPropertyChanged(nameof(RescanPreviewText));
        OnPropertyChanged(nameof(LatestScanSessionText));
        OnPropertyChanged(nameof(SummaryText));
        OnPropertyChanged(nameof(RecoveryText));
        OnPropertyChanged(nameof(NetworkMountNoticeText));
        OnPropertyChanged(nameof(RescanDisabledReason));
        OnPropertyChanged(nameof(LastDiagnosticsExportPath));
    }

    private void OnPropertyChanged([CallerMemberName] string propertyName = "")
    {
        PropertyChanged?.Invoke(this, new PropertyChangedEventArgs(propertyName));
    }
}
