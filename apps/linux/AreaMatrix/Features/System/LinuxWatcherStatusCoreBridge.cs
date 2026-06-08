using AreaMatrix.Linux.Features.Onboarding;

namespace AreaMatrix.Linux.Features.System;

public interface ILinuxWatcherStatusCoreBridge
{
    Task<LinuxWatcherStatusSnapshot> RecordWatcherHealthAsync(
        string repoPath,
        LinuxWatcherStatusHealthSignal signal,
        CancellationToken cancellationToken = default);

    Task<LinuxManualRescanPreviewReport> PreviewManualRescanAsync(
        string repoPath,
        CancellationToken cancellationToken = default);

    Task<LinuxScanSession?> GetLatestScanSessionAsync(
        string repoPath,
        CancellationToken cancellationToken = default);

    Task<LinuxReindexReport> ReindexFromFilesystemAsync(
        string repoPath,
        CancellationToken cancellationToken = default);

    Task<LinuxReindexReport> ResumeScanSessionAsync(
        string repoPath,
        long scanSessionId,
        CancellationToken cancellationToken = default);
}

public interface IAreaMatrixLinuxWatcherStatusCoreClient
{
    Task<CoreLinuxWatcherStatusSnapshot> RecordWatcherHealthAsync(
        string repoPath,
        CoreLinuxWatcherStatusHealthSignal signal,
        CancellationToken cancellationToken = default);

    Task<CoreLinuxManualRescanPreviewReport> PreviewManualRescanAsync(
        string repoPath,
        CancellationToken cancellationToken = default);

    Task<CoreLinuxScanSession?> GetLatestScanSessionAsync(
        string repoPath,
        CancellationToken cancellationToken = default);

    Task<CoreLinuxReindexReport> ReindexFromFilesystemAsync(
        string repoPath,
        CancellationToken cancellationToken = default);

    Task<CoreLinuxReindexReport> ResumeScanSessionAsync(
        string repoPath,
        long scanSessionId,
        CancellationToken cancellationToken = default);
}

public sealed class LinuxWatcherStatusCoreBridge : ILinuxWatcherStatusCoreBridge
{
    private readonly IAreaMatrixLinuxWatcherStatusCoreClient coreClient;

    public LinuxWatcherStatusCoreBridge(IAreaMatrixLinuxWatcherStatusCoreClient coreClient)
    {
        this.coreClient = coreClient;
    }

    public async Task<LinuxWatcherStatusSnapshot> RecordWatcherHealthAsync(
        string repoPath,
        LinuxWatcherStatusHealthSignal signal,
        CancellationToken cancellationToken = default)
    {
        CoreLinuxWatcherStatusSnapshot snapshot = await coreClient
            .RecordWatcherHealthAsync(repoPath, signal.ToCoreSignal(), cancellationToken)
            .ConfigureAwait(false);
        return snapshot.ToLinuxSnapshot();
    }

    public async Task<LinuxManualRescanPreviewReport> PreviewManualRescanAsync(
        string repoPath,
        CancellationToken cancellationToken = default)
    {
        CoreLinuxManualRescanPreviewReport report = await coreClient
            .PreviewManualRescanAsync(repoPath, cancellationToken)
            .ConfigureAwait(false);
        return report.ToLinuxManualRescanPreviewReport();
    }

    public async Task<LinuxScanSession?> GetLatestScanSessionAsync(
        string repoPath,
        CancellationToken cancellationToken = default)
    {
        CoreLinuxScanSession? session = await coreClient
            .GetLatestScanSessionAsync(repoPath, cancellationToken)
            .ConfigureAwait(false);
        return session?.ToLinuxScanSession();
    }

    public async Task<LinuxReindexReport> ReindexFromFilesystemAsync(
        string repoPath,
        CancellationToken cancellationToken = default)
    {
        CoreLinuxReindexReport report = await coreClient
            .ReindexFromFilesystemAsync(repoPath, cancellationToken)
            .ConfigureAwait(false);
        return report.ToLinuxReindexReport();
    }

    public async Task<LinuxReindexReport> ResumeScanSessionAsync(
        string repoPath,
        long scanSessionId,
        CancellationToken cancellationToken = default)
    {
        CoreLinuxReindexReport report = await coreClient
            .ResumeScanSessionAsync(repoPath, scanSessionId, cancellationToken)
            .ConfigureAwait(false);
        return report.ToLinuxReindexReport();
    }
}

public sealed record CoreLinuxWatcherStatusEventSample(
    string Path,
    string Kind,
    long EventId,
    long? OccurredAt);

public sealed record CoreLinuxWatcherStatusHealthSignal(
    string Backend,
    string Status,
    string WatchedPath,
    long? LastEventId,
    long? LastEventAt,
    long? LastSyncEventId,
    long? LastSyncAt,
    long? LastRescanAt,
    long PendingEventCount,
    long? WatchCount,
    string? ErrorSummary,
    IReadOnlyList<string> HealthReasons,
    IReadOnlyList<CoreLinuxWatcherStatusEventSample> RecentEvents,
    long ReportedAt);

public sealed record CoreLinuxWatcherStatusSnapshot(
    string RepoPath,
    string Backend,
    string Status,
    string WatchedPath,
    long? LastEventId,
    long? LastEventAt,
    long? LastSyncEventId,
    long? LastSyncAt,
    long? LastRescanAt,
    long PendingEventCount,
    long? WatchCount,
    string? ErrorSummary,
    IReadOnlyList<string> HealthReasons,
    IReadOnlyList<CoreLinuxWatcherStatusEventSample> RecentEvents,
    long ReportedAt);

public sealed record CoreLinuxManualRescanPreviewItem(
    string Kind,
    string RelativePath,
    string Reason,
    string SuggestedAction);

public sealed record CoreLinuxManualRescanPreviewReport(
    long Added,
    long Updated,
    long MissingOrDeletedFromFs,
    long RenamedCandidates,
    long Conflicts,
    long Unreadable,
    long Unknown,
    long Skipped,
    string SnapshotId,
    long CreatedAt,
    bool IsStale,
    IReadOnlyList<CoreLinuxManualRescanPreviewItem> Items);

public sealed record CoreLinuxReindexReport(
    long? ScanSessionId,
    long Inserted,
    long Updated,
    long Missing,
    long Conflicts,
    long Unreadable,
    long Unknown,
    long Skipped,
    IReadOnlyList<string> Errors);

public sealed record LinuxReindexReport(
    long? ScanSessionId,
    long Inserted,
    long Updated,
    long Missing,
    long Conflicts,
    long Unreadable,
    long Unknown,
    long Skipped,
    IReadOnlyList<string> Errors);

public sealed record CoreLinuxScanSession(
    long Id,
    string Kind,
    string Status,
    string? LastPath,
    long Inserted,
    long Updated,
    long Missing,
    long Conflicts,
    long Unreadable,
    long Unknown,
    long Skipped,
    long StartedAt,
    long UpdatedAt,
    long? FinishedAt,
    IReadOnlyList<string> Errors);

internal static class LinuxWatcherStatusCoreMapping
{
    public static CoreLinuxWatcherStatusHealthSignal ToCoreSignal(
        this LinuxWatcherStatusHealthSignal signal)
    {
        return new CoreLinuxWatcherStatusHealthSignal(
            signal.Backend.ToCoreBackend(),
            signal.Status.ToCoreStatus(),
            signal.WatchedPath,
            signal.LastEventId,
            signal.LastEventAt,
            signal.LastSyncEventId,
            signal.LastSyncAt,
            signal.LastRescanAt,
            signal.PendingEventCount,
            signal.WatchCount,
            signal.ErrorSummary,
            signal.HealthReasons.Select(reason => reason.ToCoreReason()).ToArray(),
            signal.RecentEvents.Select(eventSample => eventSample.ToCoreEventSample()).ToArray(),
            signal.ReportedAt);
    }

    public static LinuxWatcherStatusSnapshot ToLinuxSnapshot(
        this CoreLinuxWatcherStatusSnapshot snapshot)
    {
        return new LinuxWatcherStatusSnapshot(
            snapshot.RepoPath,
            ParseBackend(snapshot.Backend),
            ParseStatus(snapshot.Status),
            snapshot.WatchedPath,
            snapshot.LastEventId,
            snapshot.LastEventAt,
            snapshot.LastSyncEventId,
            snapshot.LastSyncAt,
            snapshot.LastRescanAt,
            snapshot.PendingEventCount,
            snapshot.WatchCount,
            snapshot.ErrorSummary,
            snapshot.HealthReasons.Select(ParseReason).ToArray(),
            snapshot.RecentEvents.Select(eventSample => eventSample.ToLinuxEventSample()).ToArray(),
            snapshot.ReportedAt);
    }

    public static LinuxManualRescanPreviewReport ToLinuxManualRescanPreviewReport(
        this CoreLinuxManualRescanPreviewReport report)
    {
        return new LinuxManualRescanPreviewReport(
            report.Added,
            report.Updated,
            report.MissingOrDeletedFromFs,
            report.RenamedCandidates,
            report.Conflicts,
            report.Unreadable,
            report.Unknown,
            report.Skipped,
            report.SnapshotId,
            report.CreatedAt,
            report.IsStale,
            report.Items.Select(item => item.ToLinuxManualRescanPreviewItem()).ToArray());
    }

    public static LinuxReindexReport ToLinuxReindexReport(this CoreLinuxReindexReport report)
    {
        return new LinuxReindexReport(
            report.ScanSessionId,
            report.Inserted,
            report.Updated,
            report.Missing,
            report.Conflicts,
            report.Unreadable,
            report.Unknown,
            report.Skipped,
            report.Errors);
    }

    public static LinuxScanSession ToLinuxScanSession(this CoreLinuxScanSession session)
    {
        return new LinuxScanSession(
            session.Id,
            ParseScanSessionKind(session.Kind),
            ParseScanSessionStatus(session.Status),
            session.LastPath,
            session.Inserted,
            session.Updated,
            session.Missing,
            session.Conflicts,
            session.Unreadable,
            session.Unknown,
            session.Skipped,
            session.StartedAt,
            session.UpdatedAt,
            session.FinishedAt,
            session.Errors);
    }

    private static CoreLinuxWatcherStatusEventSample ToCoreEventSample(
        this LinuxWatcherStatusEventSample eventSample)
    {
        return new CoreLinuxWatcherStatusEventSample(
            eventSample.Path,
            eventSample.Kind.ToCoreKind(),
            eventSample.EventId,
            eventSample.OccurredAt);
    }

    private static LinuxWatcherStatusEventSample ToLinuxEventSample(
        this CoreLinuxWatcherStatusEventSample eventSample)
    {
        return new LinuxWatcherStatusEventSample(
            eventSample.Path,
            ParseEventKind(eventSample.Kind),
            eventSample.EventId,
            eventSample.OccurredAt);
    }

    private static LinuxManualRescanPreviewItem ToLinuxManualRescanPreviewItem(
        this CoreLinuxManualRescanPreviewItem item)
    {
        return new LinuxManualRescanPreviewItem(
            ParseManualRescanPreviewItemKind(item.Kind),
            item.RelativePath,
            item.Reason,
            item.SuggestedAction);
    }

    private static string ToCoreBackend(this LinuxWatcherStatusBackend backend)
    {
        return backend switch
        {
            LinuxWatcherStatusBackend.ReadDirectoryChangesW => "ReadDirectoryChangesW",
            LinuxWatcherStatusBackend.Inotify => "Inotify",
            LinuxWatcherStatusBackend.Unknown => "Unknown",
            _ => throw UnsupportedValue("watcher backend", backend.ToString())
        };
    }

    private static string ToCoreStatus(this LinuxWatcherStatusKind status)
    {
        return status switch
        {
            LinuxWatcherStatusKind.Starting => "Starting",
            LinuxWatcherStatusKind.Running => "Running",
            LinuxWatcherStatusKind.Paused => "Paused",
            LinuxWatcherStatusKind.Error => "Error",
            LinuxWatcherStatusKind.Unavailable => "Unavailable",
            _ => throw UnsupportedValue("watcher status", status.ToString())
        };
    }

    private static string ToCoreReason(this LinuxWatcherStatusReason reason)
    {
        return reason switch
        {
            LinuxWatcherStatusReason.PermissionDenied => "PermissionDenied",
            LinuxWatcherStatusReason.PathMissing => "PathMissing",
            LinuxWatcherStatusReason.BackendUnavailable => "BackendUnavailable",
            LinuxWatcherStatusReason.DatabaseLocked => "DatabaseLocked",
            LinuxWatcherStatusReason.LimitExceeded => "LimitExceeded",
            LinuxWatcherStatusReason.NetworkMount => "NetworkMount",
            LinuxWatcherStatusReason.CloudSyncNoise => "CloudSyncNoise",
            LinuxWatcherStatusReason.Unknown => "Unknown",
            _ => throw UnsupportedValue("watcher health reason", reason.ToString())
        };
    }

    private static string ToCoreKind(this LinuxWatcherStatusEventKind kind)
    {
        return kind switch
        {
            LinuxWatcherStatusEventKind.Created => "Created",
            LinuxWatcherStatusEventKind.Removed => "Removed",
            LinuxWatcherStatusEventKind.Modified => "Modified",
            LinuxWatcherStatusEventKind.Renamed => "Renamed",
            _ => throw UnsupportedValue("watcher event kind", kind.ToString())
        };
    }

    private static LinuxWatcherStatusBackend ParseBackend(string value)
    {
        return value switch
        {
            "ReadDirectoryChangesW" => LinuxWatcherStatusBackend.ReadDirectoryChangesW,
            "Inotify" => LinuxWatcherStatusBackend.Inotify,
            "Unknown" => LinuxWatcherStatusBackend.Unknown,
            _ => throw UnsupportedValue("watcher backend", value)
        };
    }

    private static LinuxWatcherStatusKind ParseStatus(string value)
    {
        return value switch
        {
            "Starting" => LinuxWatcherStatusKind.Starting,
            "Running" => LinuxWatcherStatusKind.Running,
            "Paused" => LinuxWatcherStatusKind.Paused,
            "Error" => LinuxWatcherStatusKind.Error,
            "Unavailable" => LinuxWatcherStatusKind.Unavailable,
            _ => throw UnsupportedValue("watcher status", value)
        };
    }

    private static LinuxWatcherStatusReason ParseReason(string value)
    {
        return value switch
        {
            "PermissionDenied" => LinuxWatcherStatusReason.PermissionDenied,
            "PathMissing" => LinuxWatcherStatusReason.PathMissing,
            "BackendUnavailable" => LinuxWatcherStatusReason.BackendUnavailable,
            "DatabaseLocked" => LinuxWatcherStatusReason.DatabaseLocked,
            "LimitExceeded" => LinuxWatcherStatusReason.LimitExceeded,
            "NetworkMount" => LinuxWatcherStatusReason.NetworkMount,
            "CloudSyncNoise" => LinuxWatcherStatusReason.CloudSyncNoise,
            "Unknown" => LinuxWatcherStatusReason.Unknown,
            _ => throw UnsupportedValue("watcher health reason", value)
        };
    }

    private static LinuxWatcherStatusEventKind ParseEventKind(string value)
    {
        return value switch
        {
            "Created" => LinuxWatcherStatusEventKind.Created,
            "Removed" => LinuxWatcherStatusEventKind.Removed,
            "Modified" => LinuxWatcherStatusEventKind.Modified,
            "Renamed" => LinuxWatcherStatusEventKind.Renamed,
            _ => throw UnsupportedValue("watcher event kind", value)
        };
    }

    private static LinuxManualRescanPreviewItemKind ParseManualRescanPreviewItemKind(string value)
    {
        return value switch
        {
            "Added" => LinuxManualRescanPreviewItemKind.Added,
            "Updated" => LinuxManualRescanPreviewItemKind.Updated,
            "Missing" => LinuxManualRescanPreviewItemKind.Missing,
            "RenamedCandidate" => LinuxManualRescanPreviewItemKind.RenamedCandidate,
            "Conflict" => LinuxManualRescanPreviewItemKind.Conflict,
            "Unreadable" => LinuxManualRescanPreviewItemKind.Unreadable,
            "Unknown" => LinuxManualRescanPreviewItemKind.Unknown,
            "Skipped" => LinuxManualRescanPreviewItemKind.Skipped,
            _ => throw UnsupportedValue("manual rescan item kind", value)
        };
    }

    private static LinuxScanSessionKind ParseScanSessionKind(string value)
    {
        return value switch
        {
            "Adopt" => LinuxScanSessionKind.Adopt,
            "Reindex" => LinuxScanSessionKind.Reindex,
            _ => throw UnsupportedValue("scan session kind", value)
        };
    }

    private static LinuxScanSessionStatus ParseScanSessionStatus(string value)
    {
        return value switch
        {
            "Running" => LinuxScanSessionStatus.Running,
            "Completed" => LinuxScanSessionStatus.Completed,
            "Paused" => LinuxScanSessionStatus.Paused,
            "Failed" => LinuxScanSessionStatus.Failed,
            "Interrupted" => LinuxScanSessionStatus.Interrupted,
            _ => throw UnsupportedValue("scan session status", value)
        };
    }

    private static LinuxWatcherStatusCoreException UnsupportedValue(string label, string value)
    {
        return new LinuxWatcherStatusCoreException(
            LinuxRepositoryErrorKind.Config,
            $"Unsupported {label} `{value}`.");
    }
}
