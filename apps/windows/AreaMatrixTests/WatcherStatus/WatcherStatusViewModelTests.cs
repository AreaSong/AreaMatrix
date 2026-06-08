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
        await RunRescanNowPreparesCorePreviewBeforeConfirmationHandoff();
        await StartingSnapshotDisablesRecoveryActionsAndRescanPreview();
        await RunningScanSessionDisablesSecondRescan();
        await MissingPathMapsToRecoveryTextAndDisablesRescanEntry();
        await DatabaseLockedSnapshotDisablesRescanWithoutCallingManualRescan();
        await ExportDiagnosticsWritesRedactedWatcherSnapshot();
        await OpenRepositoryFolderUsesPlatformDiagnosticsAction();
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
        TestAssert.True(model.CanExportDiagnostics, nameof(model.CanExportDiagnostics));
        TestAssert.True(model.CanOpenRepositoryFolder, nameof(model.CanOpenRepositoryFolder));
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
        TestAssert.Empty(bridge.PreviewManualRescanRequests, nameof(bridge.PreviewManualRescanRequests));
    }

    private static async Task ExportDiagnosticsWritesRedactedWatcherSnapshot()
    {
        const string path = @"C:\Repos\AreaMatrix";
        FakeWatcherStatusCoreBridge bridge = new();
        FakeWindowsWatcherDiagnostics diagnostics = new(RunningSignal(path));
        WatcherStatusViewModel model = new(bridge, diagnostics);

        await model.OpenRouteAsync(Route(path));
        bool exported = await model.ExportDiagnosticsAsync();

        TestAssert.True(exported, nameof(exported));
        TestAssert.SequenceEqual([path], diagnostics.ExportedPaths, nameof(diagnostics.ExportedPaths));
        TestAssert.Equal(model.Snapshot, diagnostics.ExportedSnapshots.Single(), "exported snapshot");
        TestAssert.Equal(
            @"C:\Repos\AreaMatrix\.areamatrix\generated\diagnostics\watcher-status.txt",
            model.LastDiagnosticsExportPath,
            nameof(model.LastDiagnosticsExportPath));
        TestAssert.Null(model.Error, nameof(model.Error));
    }

    private static async Task OpenRepositoryFolderUsesPlatformDiagnosticsAction()
    {
        const string path = @"C:\Repos\AreaMatrix";
        FakeWatcherStatusCoreBridge bridge = new();
        FakeWindowsWatcherDiagnostics diagnostics = new(RunningSignal(path));
        WatcherStatusViewModel model = new(bridge, diagnostics);

        await model.OpenRouteAsync(Route(path));
        bool opened = await model.OpenRepositoryFolderAsync();

        TestAssert.True(opened, nameof(opened));
        TestAssert.SequenceEqual([path], diagnostics.OpenedFolders, nameof(diagnostics.OpenedFolders));
        TestAssert.Null(model.Error, nameof(model.Error));
    }

    private static async Task RunRescanNowPreparesCorePreviewBeforeConfirmationHandoff()
    {
        const string path = @"C:\Repos\AreaMatrix";
        FakeWatcherStatusCoreBridge bridge = new()
        {
            PreviewReport = new ManualRescanPreviewReport(
                Added: 2,
                Updated: 1,
                MissingOrDeletedFromFs: 1,
                RenamedCandidates: 0,
                Conflicts: 1,
                Unreadable: 0,
                Unknown: 1,
                Skipped: 3,
                SnapshotId: "preview-1",
                CreatedAt: 1_700_000_040,
                IsStale: false,
                Items: [new ManualRescanPreviewItem(
                    ManualRescanPreviewItemKind.Missing,
                    "docs\\missing.pdf",
                    "file not found",
                    "review missing")])
        };
        FakeWindowsWatcherDiagnostics diagnostics = new(RunningSignal(path));
        WatcherStatusViewModel model = new(bridge, diagnostics);

        await model.OpenRouteAsync(Route(path));
        bool canOpenConfirm = await model.PrepareRescanConfirmAsync();

        TestAssert.True(canOpenConfirm, nameof(canOpenConfirm));
        TestAssert.SequenceEqual([path, path], bridge.LatestScanSessionRequests, nameof(bridge.LatestScanSessionRequests));
        TestAssert.SequenceEqual([path], bridge.PreviewManualRescanRequests, nameof(bridge.PreviewManualRescanRequests));
        TestAssert.Contains("Added 2", model.RescanPreviewText, nameof(model.RescanPreviewText));
        TestAssert.Contains("Missing 1", model.RescanPreviewText, nameof(model.RescanPreviewText));
        TestAssert.True(model.RescanPreview?.HasNeedsReview == true, nameof(model.RescanPreview.HasNeedsReview));
    }

    private static async Task RunningScanSessionDisablesSecondRescan()
    {
        const string path = @"C:\Repos\AreaMatrix";
        FakeWatcherStatusCoreBridge bridge = new()
        {
            LatestScanSession = RunningReindexSession()
        };
        FakeWindowsWatcherDiagnostics diagnostics = new(RunningSignal(path));
        WatcherStatusViewModel model = new(bridge, diagnostics);

        await model.OpenRouteAsync(Route(path));
        bool canOpenConfirm = await model.PrepareRescanConfirmAsync();

        TestAssert.False(model.CanOpenRescanConfirm, nameof(model.CanOpenRescanConfirm));
        TestAssert.False(canOpenConfirm, nameof(canOpenConfirm));
        TestAssert.Contains("already running", model.RescanDisabledReason, nameof(model.RescanDisabledReason));
        TestAssert.Empty(bridge.PreviewManualRescanRequests, nameof(bridge.PreviewManualRescanRequests));
    }

    private static async Task StartingSnapshotDisablesRecoveryActionsAndRescanPreview()
    {
        const string path = @"C:\Repos\AreaMatrix";
        FakeWatcherStatusCoreBridge bridge = new();
        FakeWindowsWatcherDiagnostics diagnostics = new(StartingSignal(path));
        WatcherStatusViewModel model = new(bridge, diagnostics);

        await model.OpenRouteAsync(Route(path));
        bool canOpenConfirm = await model.PrepareRescanConfirmAsync();

        TestAssert.Equal(WatcherStatusKind.Starting, model.Snapshot?.Status, "snapshot status");
        TestAssert.True(model.IsWatcherStarting, nameof(model.IsWatcherStarting));
        TestAssert.False(model.CanRestartWatcher, nameof(model.CanRestartWatcher));
        TestAssert.False(model.CanOpenRescanConfirm, nameof(model.CanOpenRescanConfirm));
        TestAssert.False(canOpenConfirm, nameof(canOpenConfirm));
        TestAssert.Contains("finish starting", model.RescanDisabledReason, nameof(model.RescanDisabledReason));
        TestAssert.Empty(bridge.PreviewManualRescanRequests, nameof(bridge.PreviewManualRescanRequests));
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
        TestAssert.Empty(bridge.PreviewManualRescanRequests, nameof(bridge.PreviewManualRescanRequests));
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

    private static WatcherStatusHealthSignal StartingSignal(string path)
    {
        return RunningSignal(path) with
        {
            Status = WatcherStatusKind.Starting,
            PendingEventCount = 0,
            RecentEvents = []
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

    private static ScanSession RunningReindexSession()
    {
        return new ScanSession(
            Id: 7,
            Kind: ScanSessionKind.Reindex,
            Status: ScanSessionStatus.Running,
            LastPath: "docs\\contract.pdf",
            Inserted: 1,
            Updated: 2,
            Missing: 0,
            Conflicts: 0,
            Unreadable: 0,
            Unknown: 0,
            Skipped: 0,
            StartedAt: 1_700_000_000,
            UpdatedAt: 1_700_000_010,
            FinishedAt: null,
            Errors: []);
    }
}

internal sealed class FakeWatcherStatusCoreBridge : IWatcherStatusCoreBridge
{
    public List<string> RecordedRepoPaths { get; } = [];

    public List<WatcherStatusHealthSignal> RecordedSignals { get; } = [];

    public List<string> PreviewManualRescanRequests { get; } = [];

    public List<string> ReindexRequests { get; } = [];

    public List<string> LatestScanSessionRequests { get; } = [];

    public List<long> ResumeScanSessionRequests { get; } = [];

    public ManualRescanPreviewReport PreviewReport { get; set; } = new(
        Added: 0,
        Updated: 0,
        MissingOrDeletedFromFs: 0,
        RenamedCandidates: 0,
        Conflicts: 0,
        Unreadable: 0,
        Unknown: 0,
        Skipped: 0,
        SnapshotId: "empty",
        CreatedAt: 1_700_000_000,
        IsStale: false,
        Items: []);

    public ScanSession? LatestScanSession { get; set; }

    public ReindexReport ReindexReport { get; set; } = new(
        ScanSessionId: null,
        Inserted: 0,
        Updated: 0,
        Missing: 0,
        Conflicts: 0,
        Unreadable: 0,
        Unknown: 0,
        Skipped: 0,
        Errors: []);

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

    public Task<ManualRescanPreviewReport> PreviewManualRescanAsync(
        string repoPath,
        CancellationToken cancellationToken = default)
    {
        PreviewManualRescanRequests.Add(repoPath);
        return Task.FromResult(PreviewReport);
    }

    public Task<ReindexReport> ReindexFromFilesystemAsync(
        string repoPath,
        CancellationToken cancellationToken = default)
    {
        ReindexRequests.Add(repoPath);
        return Task.FromResult(ReindexReport);
    }

    public Task<ScanSession?> GetLatestScanSessionAsync(
        string repoPath,
        CancellationToken cancellationToken = default)
    {
        LatestScanSessionRequests.Add(repoPath);
        return Task.FromResult(LatestScanSession);
    }

    public Task<ReindexReport> ResumeScanSessionAsync(
        string repoPath,
        long scanSessionId,
        CancellationToken cancellationToken = default)
    {
        ResumeScanSessionRequests.Add(scanSessionId);
        return Task.FromResult(ReindexReport);
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

    public List<string> ExportedPaths { get; } = [];

    public List<WatcherStatusSnapshot> ExportedSnapshots { get; } = [];

    public List<string> OpenedFolders { get; } = [];

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

    public Task<string> ExportDiagnosticsAsync(
        string repoPath,
        WatcherStatusSnapshot snapshot,
        CancellationToken cancellationToken = default)
    {
        ExportedPaths.Add(repoPath);
        ExportedSnapshots.Add(snapshot);
        return Task.FromResult(
            @"C:\Repos\AreaMatrix\.areamatrix\generated\diagnostics\watcher-status.txt");
    }

    public Task OpenRepositoryFolderAsync(
        string repoPath,
        CancellationToken cancellationToken = default)
    {
        OpenedFolders.Add(repoPath);
        return Task.CompletedTask;
    }
}
