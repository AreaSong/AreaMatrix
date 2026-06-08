using AreaMatrix.Linux.Features.Onboarding;
using AreaMatrix.Linux.Features.System;
using AreaMatrix.Linux.Tests.ChooseRepository;

namespace AreaMatrix.Linux.Tests.System;

public static class LinuxWatcherStatusViewModelTests
{
    public static async Task RunAllAsync()
    {
        await OpeningWatcherStatusRecordsInotifySnapshotThroughCoreBridge();
        await RestartWatcherRecordsUpdatedSnapshot();
        await RunRescanNowPreviewsCoreImpactBeforeConfirmationHandoff();
        await RunningScanSessionDisablesSecondRescanPreview();
        await StartingSnapshotDisablesRestartAndRescanHandoff();
        await MissingPathMapsToRecoveryTextAndDisablesRescanEntry();
        await DatabaseLockedSnapshotDisablesRescanHandoff();
        await LimitExceededAndNetworkMountRenderLinuxRecoveryGuidance();
        await ExportDiagnosticsUsesPlatformDiagnosticsWithoutFileContent();
        await OpenRepositoryFolderUsesPlatformDiagnosticsAction();
        await CoreErrorMapsToReadableWatcherError();
    }

    private static async Task OpeningWatcherStatusRecordsInotifySnapshotThroughCoreBridge()
    {
        const string path = "/home/me/AreaMatrix";
        FakeLinuxWatcherStatusCoreBridge bridge = new();
        FakeLinuxWatcherDiagnostics diagnostics = new(RunningSignal(path));
        LinuxWatcherStatusViewModel model = new(bridge, diagnostics);

        await model.OpenRouteAsync(Route(path));

        TestAssert.SequenceEqual([path], diagnostics.CapturedPaths, nameof(diagnostics.CapturedPaths));
        TestAssert.Empty(diagnostics.RestartedPaths, nameof(diagnostics.RestartedPaths));
        TestAssert.SequenceEqual([path], bridge.RecordedRepoPaths, nameof(bridge.RecordedRepoPaths));
        TestAssert.SequenceEqual([path], bridge.LatestScanSessionRequests, nameof(bridge.LatestScanSessionRequests));
        TestAssert.Equal(LinuxWatcherStatusBackend.Inotify, model.Snapshot?.Backend, "backend");
        TestAssert.Equal(LinuxWatcherStatusKind.Running, model.Snapshot?.Status, "snapshot status");
        TestAssert.True(model.CanRestartWatcher, nameof(model.CanRestartWatcher));
        TestAssert.True(model.CanOpenRescanConfirm, nameof(model.CanOpenRescanConfirm));
        TestAssert.True(model.CanExportDiagnostics, nameof(model.CanExportDiagnostics));
        TestAssert.Contains("inotify", model.SummaryText, nameof(model.SummaryText));
    }

    private static async Task RestartWatcherRecordsUpdatedSnapshot()
    {
        const string path = "/home/me/AreaMatrix";
        FakeLinuxWatcherStatusCoreBridge bridge = new();
        FakeLinuxWatcherDiagnostics diagnostics = new(PausedSignal(path))
        {
            RestartSignal = RunningSignal(path)
        };
        LinuxWatcherStatusViewModel model = new(bridge, diagnostics);

        await model.OpenRouteAsync(Route(path));
        await model.RestartWatcherAsync();

        TestAssert.SequenceEqual([path], diagnostics.RestartedPaths, nameof(diagnostics.RestartedPaths));
        TestAssert.Equal(2, bridge.RecordedSignals.Count, "recorded signals");
        TestAssert.SequenceEqual([path, path], bridge.LatestScanSessionRequests, nameof(bridge.LatestScanSessionRequests));
        TestAssert.Equal(LinuxWatcherStatusKind.Running, model.Snapshot?.Status, "snapshot status");
        TestAssert.Empty(bridge.PreviewManualRescanRequests, nameof(bridge.PreviewManualRescanRequests));
    }

    private static async Task RunRescanNowPreviewsCoreImpactBeforeConfirmationHandoff()
    {
        const string path = "/home/me/AreaMatrix";
        FakeLinuxWatcherStatusCoreBridge bridge = new()
        {
            PreviewReport = new LinuxManualRescanPreviewReport(
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
                Items: [new LinuxManualRescanPreviewItem(
                    LinuxManualRescanPreviewItemKind.Missing,
                    "docs/missing.pdf",
                    "file not found",
                    "review missing")])
        };
        LinuxWatcherStatusView view = new(new LinuxWatcherStatusViewModel(
            bridge,
            new FakeLinuxWatcherDiagnostics(RunningSignal(path))));
        List<LinuxRescanConfirmRequest> requests = [];
        view.OpenRescanConfirmRequested += request => requests.Add(request);

        await view.OpenRouteAsync(Route(path));
        bool requested = await view.RunRescanNow();

        TestAssert.True(requested, nameof(requested));
        TestAssert.SequenceEqual([path, path], bridge.LatestScanSessionRequests, nameof(bridge.LatestScanSessionRequests));
        TestAssert.SequenceEqual([path], bridge.PreviewManualRescanRequests, nameof(bridge.PreviewManualRescanRequests));
        TestAssert.Empty(bridge.ReindexRequests, nameof(bridge.ReindexRequests));
        TestAssert.Empty(bridge.ResumeScanSessionRequests, nameof(bridge.ResumeScanSessionRequests));
        TestAssert.SequenceEqual([path], requests.Select(request => request.Route.RepoPath).ToArray(), "rescan route");
        TestAssert.Contains("Added 2", view.ViewModel.RescanPreviewText, nameof(view.ViewModel.RescanPreviewText));
        TestAssert.True(requests.Single().Preview.HasNeedsReview, "preview needs review");
    }

    private static async Task RunningScanSessionDisablesSecondRescanPreview()
    {
        const string path = "/home/me/AreaMatrix";
        FakeLinuxWatcherStatusCoreBridge bridge = new()
        {
            LatestScanSession = RunningReindexSession()
        };
        LinuxWatcherStatusView view = new(new LinuxWatcherStatusViewModel(
            bridge,
            new FakeLinuxWatcherDiagnostics(RunningSignal(path))));
        bool handoffRaised = false;
        view.OpenRescanConfirmRequested += _ => handoffRaised = true;

        await view.OpenRouteAsync(Route(path));
        bool requested = await view.RunRescanNow();

        TestAssert.False(view.ViewModel.CanOpenRescanConfirm, nameof(view.ViewModel.CanOpenRescanConfirm));
        TestAssert.False(requested, nameof(requested));
        TestAssert.False(handoffRaised, nameof(handoffRaised));
        TestAssert.Contains("already running", view.ViewModel.RescanDisabledReason, nameof(view.ViewModel.RescanDisabledReason));
        TestAssert.Empty(bridge.PreviewManualRescanRequests, nameof(bridge.PreviewManualRescanRequests));
    }

    private static async Task StartingSnapshotDisablesRestartAndRescanHandoff()
    {
        const string path = "/home/me/AreaMatrix";
        LinuxWatcherStatusView view = new(new LinuxWatcherStatusViewModel(
            new FakeLinuxWatcherStatusCoreBridge(),
            new FakeLinuxWatcherDiagnostics(StartingSignal(path))));
        bool handoffRaised = false;
        view.OpenRescanConfirmRequested += _ => handoffRaised = true;

        await view.OpenRouteAsync(Route(path));
        bool requested = await view.RunRescanNow();

        TestAssert.Equal(LinuxWatcherStatusKind.Starting, view.ViewModel.Snapshot?.Status, "snapshot status");
        TestAssert.False(view.ViewModel.CanRestartWatcher, nameof(view.ViewModel.CanRestartWatcher));
        TestAssert.False(view.ViewModel.CanOpenRescanConfirm, nameof(view.ViewModel.CanOpenRescanConfirm));
        TestAssert.False(requested, nameof(requested));
        TestAssert.False(handoffRaised, nameof(handoffRaised));
        TestAssert.Contains("finish starting", view.ViewModel.RescanDisabledReason, "disabled reason");
    }

    private static async Task MissingPathMapsToRecoveryTextAndDisablesRescanEntry()
    {
        const string path = "/mnt/disconnected/AreaMatrix";
        LinuxWatcherStatusViewModel model = new(
            new FakeLinuxWatcherStatusCoreBridge(),
            new FakeLinuxWatcherDiagnostics(MissingPathSignal(path)));

        await model.OpenRouteAsync(Route(path));

        TestAssert.Equal(LinuxWatcherStatusKind.Error, model.Snapshot?.Status, "snapshot status");
        TestAssert.False(model.CanOpenRescanConfirm, nameof(model.CanOpenRescanConfirm));
        TestAssert.Contains("Reconnect", model.RescanDisabledReason, nameof(model.RescanDisabledReason));
        TestAssert.Contains("Choose the repository again", model.RecoveryText, nameof(model.RecoveryText));
    }

    private static async Task DatabaseLockedSnapshotDisablesRescanHandoff()
    {
        const string path = "/home/me/AreaMatrix";
        LinuxWatcherStatusHealthSignal signal = RunningSignal(path) with
        {
            HealthReasons = [LinuxWatcherStatusReason.DatabaseLocked],
            ErrorSummary = "Repository database is locked."
        };
        FakeLinuxWatcherStatusCoreBridge bridge = new();
        LinuxWatcherStatusViewModel model = new(
            bridge,
            new FakeLinuxWatcherDiagnostics(signal));

        await model.OpenRouteAsync(Route(path));

        TestAssert.False(model.CanOpenRescanConfirm, nameof(model.CanOpenRescanConfirm));
        TestAssert.Contains("database lock", model.RescanDisabledReason, nameof(model.RescanDisabledReason));
        TestAssert.Empty(bridge.PreviewManualRescanRequests, nameof(bridge.PreviewManualRescanRequests));
    }

    private static async Task LimitExceededAndNetworkMountRenderLinuxRecoveryGuidance()
    {
        const string path = "/mnt/share/AreaMatrix";
        LinuxWatcherStatusHealthSignal signal = RunningSignal(path) with
        {
            Status = LinuxWatcherStatusKind.Error,
            ErrorSummary = null,
            HealthReasons =
            [
                LinuxWatcherStatusReason.LimitExceeded,
                LinuxWatcherStatusReason.NetworkMount
            ]
        };
        LinuxWatcherStatusViewModel model = new(
            new FakeLinuxWatcherStatusCoreBridge(),
            new FakeLinuxWatcherDiagnostics(signal));

        await model.OpenRouteAsync(Route(path));

        TestAssert.Contains("inotify watch limit", model.SummaryText, nameof(model.SummaryText));
        TestAssert.Contains("will not run sudo", model.RecoveryText, nameof(model.RecoveryText));
        TestAssert.Contains("not report all file changes", model.NetworkMountNoticeText, "network notice");
    }

    private static async Task ExportDiagnosticsUsesPlatformDiagnosticsWithoutFileContent()
    {
        const string path = "/home/me/AreaMatrix";
        FakeLinuxWatcherDiagnostics diagnostics = new(RunningSignal(path));
        LinuxWatcherStatusViewModel model = new(new FakeLinuxWatcherStatusCoreBridge(), diagnostics);

        await model.OpenRouteAsync(Route(path));
        bool exported = await model.ExportDiagnosticsAsync();

        TestAssert.True(exported, nameof(exported));
        TestAssert.SequenceEqual([path], diagnostics.ExportedPaths, nameof(diagnostics.ExportedPaths));
        TestAssert.Equal(model.Snapshot, diagnostics.ExportedSnapshots.Single(), "exported snapshot");
        TestAssert.Equal(
            "/home/me/AreaMatrix/.areamatrix/generated/diagnostics/watcher-status.txt",
            model.LastDiagnosticsExportPath,
            nameof(model.LastDiagnosticsExportPath));
    }

    private static async Task OpenRepositoryFolderUsesPlatformDiagnosticsAction()
    {
        const string path = "/home/me/AreaMatrix";
        FakeLinuxWatcherDiagnostics diagnostics = new(RunningSignal(path));
        LinuxWatcherStatusViewModel model = new(new FakeLinuxWatcherStatusCoreBridge(), diagnostics);

        await model.OpenRouteAsync(Route(path));
        bool opened = await model.OpenRepositoryFolderAsync();

        TestAssert.True(opened, nameof(opened));
        TestAssert.SequenceEqual([path], diagnostics.OpenedFolders, nameof(diagnostics.OpenedFolders));
    }

    private static async Task CoreErrorMapsToReadableWatcherError()
    {
        const string path = "/home/me/AreaMatrix";
        FakeLinuxWatcherStatusCoreBridge bridge = new()
        {
            Error = new LinuxWatcherStatusCoreException(
                LinuxRepositoryErrorKind.Db,
                "raw db error",
                path)
        };
        LinuxWatcherStatusViewModel model = new(
            bridge,
            new FakeLinuxWatcherDiagnostics(RunningSignal(path)));

        await model.OpenRouteAsync(Route(path));

        TestAssert.Equal(LinuxRepositoryErrorKind.Db, model.Error?.Kind, "error kind");
        TestAssert.Contains("database", model.SummaryText, nameof(model.SummaryText));
        TestAssert.Null(model.Snapshot, nameof(model.Snapshot));
    }

    private static LinuxRepositoryRoute Route(string path)
    {
        return new LinuxRepositoryRoute(
            LinuxRepositoryRouteKind.MainWindow,
            path,
            LinuxRepositoryValidationSamples.Initialized(path));
    }

    private static LinuxWatcherStatusHealthSignal RunningSignal(string path)
    {
        return new LinuxWatcherStatusHealthSignal(
            LinuxWatcherStatusBackend.Inotify,
            LinuxWatcherStatusKind.Running,
            path,
            42,
            1_700_000_000,
            42,
            1_700_000_010,
            1_700_000_020,
            0,
            128,
            null,
            path.StartsWith("/mnt/", StringComparison.Ordinal)
                ? [LinuxWatcherStatusReason.NetworkMount]
                : [],
            [new LinuxWatcherStatusEventSample("docs/contract.pdf", LinuxWatcherStatusEventKind.Modified, 42, 1_700_000_000)],
            1_700_000_030);
    }

    private static LinuxWatcherStatusHealthSignal PausedSignal(string path)
    {
        return RunningSignal(path) with
        {
            Status = LinuxWatcherStatusKind.Paused,
            PendingEventCount = 3,
            HealthReasons = []
        };
    }

    private static LinuxWatcherStatusHealthSignal StartingSignal(string path)
    {
        return RunningSignal(path) with
        {
            Status = LinuxWatcherStatusKind.Starting,
            PendingEventCount = 0,
            RecentEvents = []
        };
    }

    private static LinuxWatcherStatusHealthSignal MissingPathSignal(string path)
    {
        return RunningSignal(path) with
        {
            Status = LinuxWatcherStatusKind.Error,
            HealthReasons = [LinuxWatcherStatusReason.PathMissing],
            ErrorSummary = "Repository path is missing or disconnected."
        };
    }

    private static LinuxScanSession RunningReindexSession()
    {
        return new LinuxScanSession(
            Id: 7,
            Kind: LinuxScanSessionKind.Reindex,
            Status: LinuxScanSessionStatus.Running,
            LastPath: "docs/contract.pdf",
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
