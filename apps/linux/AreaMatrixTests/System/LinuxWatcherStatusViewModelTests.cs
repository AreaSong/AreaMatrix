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
        await RunRescanNowOnlyRaisesConfirmationHandoff();
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
        TestAssert.Equal(LinuxWatcherStatusKind.Running, model.Snapshot?.Status, "snapshot status");
    }

    private static async Task RunRescanNowOnlyRaisesConfirmationHandoff()
    {
        const string path = "/home/me/AreaMatrix";
        LinuxWatcherStatusView view = new(new LinuxWatcherStatusViewModel(
            new FakeLinuxWatcherStatusCoreBridge(),
            new FakeLinuxWatcherDiagnostics(RunningSignal(path))));
        List<LinuxRepositoryRoute> requestedRoutes = [];
        view.OpenRescanConfirmRequested += route => requestedRoutes.Add(route);

        await view.OpenRouteAsync(Route(path));
        bool requested = view.RunRescanNow();

        TestAssert.True(requested, nameof(requested));
        TestAssert.SequenceEqual([path], requestedRoutes.Select(route => route.RepoPath).ToArray(), "rescan route");
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
        bool requested = view.RunRescanNow();

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
        LinuxWatcherStatusViewModel model = new(
            new FakeLinuxWatcherStatusCoreBridge(),
            new FakeLinuxWatcherDiagnostics(signal));

        await model.OpenRouteAsync(Route(path));

        TestAssert.False(model.CanOpenRescanConfirm, nameof(model.CanOpenRescanConfirm));
        TestAssert.Contains("database lock", model.RescanDisabledReason, nameof(model.RescanDisabledReason));
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
}

internal sealed class FakeLinuxWatcherStatusCoreBridge : ILinuxWatcherStatusCoreBridge
{
    public List<string> RecordedRepoPaths { get; } = [];

    public List<LinuxWatcherStatusHealthSignal> RecordedSignals { get; } = [];

    public Exception? Error { get; set; }

    public Task<LinuxWatcherStatusSnapshot> RecordWatcherHealthAsync(
        string repoPath,
        LinuxWatcherStatusHealthSignal signal,
        CancellationToken cancellationToken = default)
    {
        cancellationToken.ThrowIfCancellationRequested();
        if (Error is not null)
        {
            throw Error;
        }

        RecordedRepoPaths.Add(repoPath);
        RecordedSignals.Add(signal);
        return Task.FromResult(new LinuxWatcherStatusSnapshot(
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

internal sealed class FakeLinuxWatcherDiagnostics : ILinuxWatcherDiagnostics
{
    private readonly LinuxWatcherStatusHealthSignal captureSignal;

    public FakeLinuxWatcherDiagnostics(LinuxWatcherStatusHealthSignal captureSignal)
    {
        this.captureSignal = captureSignal;
    }

    public LinuxWatcherStatusHealthSignal? RestartSignal { get; set; }

    public List<string> CapturedPaths { get; } = [];

    public List<string> RestartedPaths { get; } = [];

    public List<string> ExportedPaths { get; } = [];

    public List<LinuxWatcherStatusSnapshot> ExportedSnapshots { get; } = [];

    public List<string> OpenedFolders { get; } = [];

    public Task<LinuxWatcherStatusHealthSignal> CaptureSnapshotAsync(
        string repoPath,
        CancellationToken cancellationToken = default)
    {
        cancellationToken.ThrowIfCancellationRequested();
        CapturedPaths.Add(repoPath);
        return Task.FromResult(captureSignal);
    }

    public Task<LinuxWatcherStatusHealthSignal> RestartWatcherAsync(
        string repoPath,
        CancellationToken cancellationToken = default)
    {
        cancellationToken.ThrowIfCancellationRequested();
        RestartedPaths.Add(repoPath);
        return Task.FromResult(RestartSignal ?? captureSignal);
    }

    public Task<string> ExportDiagnosticsAsync(
        string repoPath,
        LinuxWatcherStatusSnapshot snapshot,
        CancellationToken cancellationToken = default)
    {
        cancellationToken.ThrowIfCancellationRequested();
        ExportedPaths.Add(repoPath);
        ExportedSnapshots.Add(snapshot);
        return Task.FromResult(
            $"{repoPath}/.areamatrix/generated/diagnostics/watcher-status.txt");
    }

    public Task OpenRepositoryFolderAsync(
        string repoPath,
        CancellationToken cancellationToken = default)
    {
        cancellationToken.ThrowIfCancellationRequested();
        OpenedFolders.Add(repoPath);
        return Task.CompletedTask;
    }
}
