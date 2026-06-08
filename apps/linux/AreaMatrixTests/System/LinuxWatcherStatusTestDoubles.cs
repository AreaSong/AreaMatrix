using AreaMatrix.Linux.Features.System;

namespace AreaMatrix.Linux.Tests.System;

internal sealed class FakeLinuxWatcherStatusCoreBridge : ILinuxWatcherStatusCoreBridge
{
    public List<string> RecordedRepoPaths { get; } = [];

    public List<LinuxWatcherStatusHealthSignal> RecordedSignals { get; } = [];

    public List<string> PreviewManualRescanRequests { get; } = [];

    public List<string> ReindexRequests { get; } = [];

    public List<string> LatestScanSessionRequests { get; } = [];

    public List<long> ResumeScanSessionRequests { get; } = [];

    public LinuxManualRescanPreviewReport PreviewReport { get; set; } = new(
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

    public LinuxScanSession? LatestScanSession { get; set; }

    public LinuxReindexReport ReindexReport { get; set; } = new(
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

    public Task<LinuxManualRescanPreviewReport> PreviewManualRescanAsync(
        string repoPath,
        CancellationToken cancellationToken = default)
    {
        cancellationToken.ThrowIfCancellationRequested();
        PreviewManualRescanRequests.Add(repoPath);
        return Task.FromResult(PreviewReport);
    }

    public Task<LinuxScanSession?> GetLatestScanSessionAsync(
        string repoPath,
        CancellationToken cancellationToken = default)
    {
        cancellationToken.ThrowIfCancellationRequested();
        LatestScanSessionRequests.Add(repoPath);
        return Task.FromResult(LatestScanSession);
    }

    public Task<LinuxReindexReport> ReindexFromFilesystemAsync(
        string repoPath,
        CancellationToken cancellationToken = default)
    {
        cancellationToken.ThrowIfCancellationRequested();
        ReindexRequests.Add(repoPath);
        return Task.FromResult(ReindexReport);
    }

    public Task<LinuxReindexReport> ResumeScanSessionAsync(
        string repoPath,
        long scanSessionId,
        CancellationToken cancellationToken = default)
    {
        cancellationToken.ThrowIfCancellationRequested();
        ResumeScanSessionRequests.Add(scanSessionId);
        return Task.FromResult(ReindexReport);
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
