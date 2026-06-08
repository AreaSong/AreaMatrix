using AreaMatrix.Features.Library;
using AreaMatrix.Features.Onboarding;
using AreaMatrixTests.ChooseRepository;

namespace AreaMatrixTests.WatcherStatus;

public static class WatcherStatusViewModelTests
{
    public static async Task RunAllAsync()
    {
        await OpeningWatcherStatusRecordsPlatformSnapshotThroughCoreBridge();
        await RestartWatcherUsesExplicitPlatformRestartAndRecordsUpdatedSnapshot();
        await MissingPathMapsToRecoveryTextAndDisablesRescanEntry();
        await DatabaseLockedSnapshotDisablesRescanWithoutCallingManualRescan();
        await CoreErrorMapsToReadableWatcherError();
    }

    private static async Task OpeningWatcherStatusRecordsPlatformSnapshotThroughCoreBridge()
    {
        const string path = @"C:\Users\me\OneDrive\AreaMatrix";
        FakeWatcherStatusCoreBridge bridge = new();
        FakeWindowsWatcherDiagnostics diagnostics = new(RunningSignal(path));
        WatcherStatusViewModel model = new(bridge, diagnostics);

        await model.OpenRouteAsync(Route(path));

        TestAssert.SequenceEqual([path], diagnostics.CapturedPaths, nameof(diagnostics.CapturedPaths));
        TestAssert.Empty(diagnostics.RestartedPaths, nameof(diagnostics.RestartedPaths));
        TestAssert.SequenceEqual([path], bridge.RecordedRepoPaths, nameof(bridge.RecordedRepoPaths));
        TestAssert.Equal(WatcherStatusKind.Running, model.Snapshot?.Status, "snapshot status");
        TestAssert.True(model.CanRestartWatcher, nameof(model.CanRestartWatcher));
        TestAssert.True(model.CanOpenRescanConfirm, nameof(model.CanOpenRescanConfirm));
        TestAssert.False(model.CanExportDiagnostics, nameof(model.CanExportDiagnostics));
        TestAssert.False(model.CanOpenRepositoryFolder, nameof(model.CanOpenRepositoryFolder));
        TestAssert.Contains("OneDrive may generate bursts", model.OneDriveNoticeText, nameof(model.OneDriveNoticeText));
        TestAssert.Contains("AreaMatrix is watching", model.SummaryText, nameof(model.SummaryText));
    }

    private static async Task RestartWatcherUsesExplicitPlatformRestartAndRecordsUpdatedSnapshot()
    {
        const string path = @"C:\Repos\AreaMatrix";
        FakeWatcherStatusCoreBridge bridge = new();
        FakeWindowsWatcherDiagnostics diagnostics = new(PausedSignal(path))
        {
            RestartSignal = RunningSignal(path)
        };
        WatcherStatusViewModel model = new(bridge, diagnostics);

        await model.OpenRouteAsync(Route(path));
        await model.RestartWatcherAsync();

        TestAssert.SequenceEqual([path], diagnostics.RestartedPaths, nameof(diagnostics.RestartedPaths));
        TestAssert.Equal(2, bridge.RecordedSignals.Count, "recorded signals");
        TestAssert.Equal(WatcherStatusKind.Running, model.Snapshot?.Status, "snapshot status");
        TestAssert.Empty(bridge.ManualRescanRequests, nameof(bridge.ManualRescanRequests));
    }

    private static async Task MissingPathMapsToRecoveryTextAndDisablesRescanEntry()
    {
        const string path = @"D:\Disconnected\AreaMatrix";
        FakeWatcherStatusCoreBridge bridge = new();
        FakeWindowsWatcherDiagnostics diagnostics = new(MissingPathSignal(path));
        WatcherStatusViewModel model = new(bridge, diagnostics);

        await model.OpenRouteAsync(Route(path));

        TestAssert.Equal(WatcherStatusKind.Error, model.Snapshot?.Status, "snapshot status");
        TestAssert.False(model.CanOpenRescanConfirm, nameof(model.CanOpenRescanConfirm));
        TestAssert.Contains("Reconnect", model.RescanDisabledReason, nameof(model.RescanDisabledReason));
        TestAssert.Contains("Choose the repository again", model.RecoveryText, nameof(model.RecoveryText));
    }

    private static async Task DatabaseLockedSnapshotDisablesRescanWithoutCallingManualRescan()
    {
        const string path = @"C:\Repos\AreaMatrix";
        WatcherStatusHealthSignal signal = RunningSignal(path) with
        {
            HealthReasons = [WatcherStatusReason.DatabaseLocked],
            ErrorSummary = "Repository database is locked."
        };
        FakeWatcherStatusCoreBridge bridge = new();
        FakeWindowsWatcherDiagnostics diagnostics = new(signal);
        WatcherStatusViewModel model = new(bridge, diagnostics);

        await model.OpenRouteAsync(Route(path));

        TestAssert.False(model.CanOpenRescanConfirm, nameof(model.CanOpenRescanConfirm));
        TestAssert.Contains("database lock", model.RescanDisabledReason, nameof(model.RescanDisabledReason));
        TestAssert.Empty(bridge.ManualRescanRequests, nameof(bridge.ManualRescanRequests));
    }

    private static async Task CoreErrorMapsToReadableWatcherError()
    {
        const string path = @"C:\Repos\AreaMatrix";
        FakeWatcherStatusCoreBridge bridge = new()
        {
            Error = new WatcherStatusCoreException(
                WindowsRepositoryErrorKind.Db,
                "raw db error",
                path)
        };
        FakeWindowsWatcherDiagnostics diagnostics = new(RunningSignal(path));
        WatcherStatusViewModel model = new(bridge, diagnostics);

        await model.OpenRouteAsync(Route(path));

        TestAssert.Equal(WindowsRepositoryErrorKind.Db, model.Error?.Kind, "error kind");
        TestAssert.Contains("database", model.SummaryText, nameof(model.SummaryText));
        TestAssert.Null(model.Snapshot, nameof(model.Snapshot));
    }

    private static WindowsRepositoryRoute Route(string path)
    {
        return new WindowsRepositoryRoute(
            WindowsRepositoryRouteKind.WatcherStatus,
            path,
            null,
            null);
    }

    private static WatcherStatusHealthSignal RunningSignal(string path)
    {
        return new WatcherStatusHealthSignal(
            WatcherStatusBackend.ReadDirectoryChangesW,
            WatcherStatusKind.Running,
            path,
            42,
            1_700_000_000,
            42,
            1_700_000_010,
            1_700_000_020,
            0,
            1,
            null,
            path.Contains("OneDrive", StringComparison.OrdinalIgnoreCase)
                ? [WatcherStatusReason.CloudSyncNoise]
                : [],
            [new WatcherStatusEventSample("docs\\contract.pdf", WatcherStatusEventKind.Modified, 42, 1_700_000_000)],
            1_700_000_030);
    }

    private static WatcherStatusHealthSignal PausedSignal(string path)
    {
        return RunningSignal(path) with
        {
            Status = WatcherStatusKind.Paused,
            PendingEventCount = 3,
            HealthReasons = []
        };
    }

    private static WatcherStatusHealthSignal MissingPathSignal(string path)
    {
        return RunningSignal(path) with
        {
            Status = WatcherStatusKind.Error,
            WatchedPath = path,
            ErrorSummary = "Repository path is missing or disconnected.",
            HealthReasons = [WatcherStatusReason.PathMissing],
            RecentEvents = []
        };
    }
}

internal sealed class FakeWatcherStatusCoreBridge : IWatcherStatusCoreBridge
{
    public List<string> RecordedRepoPaths { get; } = [];

    public List<WatcherStatusHealthSignal> RecordedSignals { get; } = [];

    public List<string> ManualRescanRequests { get; } = [];

    public Exception? Error { get; set; }

    public Task<WatcherStatusSnapshot> RecordWatcherHealthAsync(
        string repoPath,
        WatcherStatusHealthSignal signal,
        CancellationToken cancellationToken = default)
    {
        if (Error is not null)
        {
            throw Error;
        }

        RecordedRepoPaths.Add(repoPath);
        RecordedSignals.Add(signal);
        return Task.FromResult(new WatcherStatusSnapshot(
            repoPath,
            signal.Backend,
            signal.Status,
            signal.WatchedPath,
            signal.LastEventId,
            signal.LastEventAt,
            signal.LastSyncEventId,
            signal.LastSyncAt,
            signal.LastRescanAt,
            signal.PendingEventCount,
            signal.WatchCount,
            signal.ErrorSummary,
            signal.HealthReasons,
            signal.RecentEvents,
            signal.ReportedAt));
    }
}

internal sealed class FakeWindowsWatcherDiagnostics : IWindowsWatcherDiagnostics
{
    private readonly WatcherStatusHealthSignal captureSignal;

    public FakeWindowsWatcherDiagnostics(WatcherStatusHealthSignal captureSignal)
    {
        this.captureSignal = captureSignal;
        RestartSignal = captureSignal;
    }

    public List<string> CapturedPaths { get; } = [];

    public List<string> RestartedPaths { get; } = [];

    public WatcherStatusHealthSignal RestartSignal { get; set; }

    public Task<WatcherStatusHealthSignal> CaptureSnapshotAsync(
        string repoPath,
        CancellationToken cancellationToken = default)
    {
        CapturedPaths.Add(repoPath);
        return Task.FromResult(captureSignal);
    }

    public Task<WatcherStatusHealthSignal> RestartWatcherAsync(
        string repoPath,
        CancellationToken cancellationToken = default)
    {
        RestartedPaths.Add(repoPath);
        return Task.FromResult(RestartSignal);
    }
}
