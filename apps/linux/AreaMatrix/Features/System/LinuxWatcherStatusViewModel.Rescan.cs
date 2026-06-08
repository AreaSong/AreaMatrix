namespace AreaMatrix.Linux.Features.System;

public sealed partial class LinuxWatcherStatusViewModel
{
    private LinuxManualRescanPreviewReport? rescanPreview;
    private LinuxScanSession? latestScanSession;
    private bool isPreparingRescan;

    public LinuxManualRescanPreviewReport? RescanPreview
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

    public LinuxScanSession? LatestScanSession
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

    public bool IsRescanRunning => LatestScanSession?.IsRunning == true;

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

    public string RescanPreviewText => RescanPreview?.SummaryText
        ?? "Run rescan now opens confirmation after a read-only preview.";

    public string LatestScanSessionText => LatestScanSession?.DisplayText
        ?? "Latest rescan session: None.";

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

            return "Opens S4-X-07 rescan confirmation before scanning.";
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

    public bool CanRequestRescanConfirm()
    {
        return CanOpenRescanConfirm;
    }
}
