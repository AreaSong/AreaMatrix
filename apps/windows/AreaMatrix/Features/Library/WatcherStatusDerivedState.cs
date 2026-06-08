namespace AreaMatrix.Features.Library;

public sealed partial class WatcherStatusViewModel
{
    public bool IsBusy => IsLoading || IsRestarting || IsPreparingRescan;

    public bool IsWatcherStarting => Snapshot?.Status == WatcherStatusKind.Starting;

    public bool CanRestartWatcher => !IsBusy
        && !IsWatcherStarting
        && Snapshot?.IsBackendUnavailable != true;

    public bool IsRescanRunning => LatestScanSession?.IsRunning == true;
}
