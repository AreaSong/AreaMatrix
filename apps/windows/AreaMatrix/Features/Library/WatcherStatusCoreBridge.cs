using System.Collections.Generic;
using System.Linq;
using System.Threading;
using System.Threading.Tasks;
using AreaMatrix.Features.Onboarding;

namespace AreaMatrix.Features.Library;

public interface IWatcherStatusCoreBridge
{
    Task<WatcherStatusSnapshot> RecordWatcherHealthAsync(
        string repoPath,
        WatcherStatusHealthSignal signal,
        CancellationToken cancellationToken = default);

    Task<ManualRescanPreviewReport> PreviewManualRescanAsync(
        string repoPath,
        CancellationToken cancellationToken = default);

    Task<ReindexReport> ReindexFromFilesystemAsync(
        string repoPath,
        CancellationToken cancellationToken = default);

    Task<ScanSession?> GetLatestScanSessionAsync(
        string repoPath,
        CancellationToken cancellationToken = default);

    Task<ReindexReport> ResumeScanSessionAsync(
        string repoPath,
        long scanSessionId,
        CancellationToken cancellationToken = default);
}

public interface IAreaMatrixWatcherStatusCoreClient
{
    Task<CoreWatcherStatusSnapshot> RecordWatcherHealthAsync(
        string repoPath,
        CoreWatcherStatusHealthSignal signal,
        CancellationToken cancellationToken = default);

    Task<CoreManualRescanPreviewReport> PreviewManualRescanAsync(
        string repoPath,
        CancellationToken cancellationToken = default);

    Task<CoreReindexReport> ReindexFromFilesystemAsync(
        string repoPath,
        CancellationToken cancellationToken = default);

    Task<CoreScanSession?> GetLatestScanSessionAsync(
        string repoPath,
        CancellationToken cancellationToken = default);

    Task<CoreReindexReport> ResumeScanSessionAsync(
        string repoPath,
        long scanSessionId,
        CancellationToken cancellationToken = default);
}

public sealed class WatcherStatusCoreBridge : IWatcherStatusCoreBridge
{
    private readonly IAreaMatrixWatcherStatusCoreClient coreClient;

    public WatcherStatusCoreBridge(IAreaMatrixWatcherStatusCoreClient coreClient)
    {
        this.coreClient = coreClient;
    }

    public async Task<WatcherStatusSnapshot> RecordWatcherHealthAsync(
        string repoPath,
        WatcherStatusHealthSignal signal,
        CancellationToken cancellationToken = default)
    {
        CoreWatcherStatusSnapshot snapshot = await coreClient
            .RecordWatcherHealthAsync(repoPath, signal.ToCoreSignal(), cancellationToken)
            .ConfigureAwait(false);
        return snapshot.ToWatcherStatusSnapshot();
    }

    public async Task<ManualRescanPreviewReport> PreviewManualRescanAsync(
        string repoPath,
        CancellationToken cancellationToken = default)
    {
        CoreManualRescanPreviewReport report = await coreClient
            .PreviewManualRescanAsync(repoPath, cancellationToken)
            .ConfigureAwait(false);
        return report.ToManualRescanPreviewReport();
    }

    public async Task<ReindexReport> ReindexFromFilesystemAsync(
        string repoPath,
        CancellationToken cancellationToken = default)
    {
        CoreReindexReport report = await coreClient
            .ReindexFromFilesystemAsync(repoPath, cancellationToken)
            .ConfigureAwait(false);
        return report.ToReindexReport();
    }

    public async Task<ScanSession?> GetLatestScanSessionAsync(
        string repoPath,
        CancellationToken cancellationToken = default)
    {
        CoreScanSession? session = await coreClient
            .GetLatestScanSessionAsync(repoPath, cancellationToken)
            .ConfigureAwait(false);
        return session?.ToScanSession();
    }

    public async Task<ReindexReport> ResumeScanSessionAsync(
        string repoPath,
        long scanSessionId,
        CancellationToken cancellationToken = default)
    {
        CoreReindexReport report = await coreClient
            .ResumeScanSessionAsync(repoPath, scanSessionId, cancellationToken)
            .ConfigureAwait(false);
        return report.ToReindexReport();
    }
}

public sealed record CoreWatcherStatusEventSample(
    string Path,
    string Kind,
    long EventId,
    long? OccurredAt);

public sealed record CoreWatcherStatusHealthSignal(
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
    IReadOnlyList<CoreWatcherStatusEventSample> RecentEvents,
    long ReportedAt);

public sealed record CoreWatcherStatusSnapshot(
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
    IReadOnlyList<CoreWatcherStatusEventSample> RecentEvents,
    long ReportedAt);

public sealed record CoreManualRescanPreviewItem(
    string Kind,
    string RelativePath,
    string Reason,
    string SuggestedAction);

public sealed record CoreManualRescanPreviewReport(
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
    IReadOnlyList<CoreManualRescanPreviewItem> Items);

public sealed record CoreReindexReport(
    long? ScanSessionId,
    long Inserted,
    long Updated,
    long Missing,
    long Conflicts,
    long Unreadable,
    long Unknown,
    long Skipped,
    IReadOnlyList<string> Errors);

public sealed record CoreScanSession(
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

internal static class WatcherStatusCoreMapping
{
    public static CoreWatcherStatusHealthSignal ToCoreSignal(this WatcherStatusHealthSignal signal)
    {
        return new CoreWatcherStatusHealthSignal(
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

    public static WatcherStatusSnapshot ToWatcherStatusSnapshot(this CoreWatcherStatusSnapshot snapshot)
    {
        return new WatcherStatusSnapshot(
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
            snapshot.RecentEvents.Select(eventSample => eventSample.ToWatcherEventSample()).ToArray(),
            snapshot.ReportedAt);
    }

    public static ManualRescanPreviewReport ToManualRescanPreviewReport(
        this CoreManualRescanPreviewReport report)
    {
        return new ManualRescanPreviewReport(
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
            report.Items.Select(item => item.ToManualRescanPreviewItem()).ToArray());
    }

    public static ReindexReport ToReindexReport(this CoreReindexReport report)
    {
        return new ReindexReport(
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

    public static ScanSession ToScanSession(this CoreScanSession session)
    {
        return new ScanSession(
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

    private static CoreWatcherStatusEventSample ToCoreEventSample(this WatcherStatusEventSample eventSample)
    {
        return new CoreWatcherStatusEventSample(
            eventSample.Path,
            eventSample.Kind.ToCoreKind(),
            eventSample.EventId,
            eventSample.OccurredAt);
    }

    private static WatcherStatusEventSample ToWatcherEventSample(this CoreWatcherStatusEventSample eventSample)
    {
        return new WatcherStatusEventSample(
            eventSample.Path,
            ParseEventKind(eventSample.Kind),
            eventSample.EventId,
            eventSample.OccurredAt);
    }

    private static ManualRescanPreviewItem ToManualRescanPreviewItem(this CoreManualRescanPreviewItem item)
    {
        return new ManualRescanPreviewItem(
            ParseManualRescanPreviewItemKind(item.Kind),
            item.RelativePath,
            item.Reason,
            item.SuggestedAction);
    }

    private static string ToCoreBackend(this WatcherStatusBackend backend)
    {
        return backend switch
        {
            WatcherStatusBackend.ReadDirectoryChangesW => "ReadDirectoryChangesW",
            WatcherStatusBackend.Inotify => "Inotify",
            WatcherStatusBackend.Unknown => "Unknown",
            _ => throw UnsupportedValue("watcher backend", backend.ToString())
        };
    }

    private static string ToCoreStatus(this WatcherStatusKind status)
    {
        return status switch
        {
            WatcherStatusKind.Starting => "Starting",
            WatcherStatusKind.Running => "Running",
            WatcherStatusKind.Paused => "Paused",
            WatcherStatusKind.Error => "Error",
            WatcherStatusKind.Unavailable => "Unavailable",
            _ => throw UnsupportedValue("watcher status", status.ToString())
        };
    }

    private static string ToCoreReason(this WatcherStatusReason reason)
    {
        return reason switch
        {
            WatcherStatusReason.PermissionDenied => "PermissionDenied",
            WatcherStatusReason.PathMissing => "PathMissing",
            WatcherStatusReason.BackendUnavailable => "BackendUnavailable",
            WatcherStatusReason.DatabaseLocked => "DatabaseLocked",
            WatcherStatusReason.LimitExceeded => "LimitExceeded",
            WatcherStatusReason.NetworkMount => "NetworkMount",
            WatcherStatusReason.CloudSyncNoise => "CloudSyncNoise",
            WatcherStatusReason.Unknown => "Unknown",
            _ => throw UnsupportedValue("watcher health reason", reason.ToString())
        };
    }

    private static string ToCoreKind(this WatcherStatusEventKind kind)
    {
        return kind switch
        {
            WatcherStatusEventKind.Created => "Created",
            WatcherStatusEventKind.Removed => "Removed",
            WatcherStatusEventKind.Modified => "Modified",
            WatcherStatusEventKind.Renamed => "Renamed",
            _ => throw UnsupportedValue("watcher event kind", kind.ToString())
        };
    }

    private static WatcherStatusBackend ParseBackend(string value)
    {
        return value switch
        {
            "ReadDirectoryChangesW" => WatcherStatusBackend.ReadDirectoryChangesW,
            "Inotify" => WatcherStatusBackend.Inotify,
            "Unknown" => WatcherStatusBackend.Unknown,
            _ => throw UnsupportedValue("watcher backend", value)
        };
    }

    private static WatcherStatusKind ParseStatus(string value)
    {
        return value switch
        {
            "Starting" => WatcherStatusKind.Starting,
            "Running" => WatcherStatusKind.Running,
            "Paused" => WatcherStatusKind.Paused,
            "Error" => WatcherStatusKind.Error,
            "Unavailable" => WatcherStatusKind.Unavailable,
            _ => throw UnsupportedValue("watcher status", value)
        };
    }

    private static WatcherStatusReason ParseReason(string value)
    {
        return value switch
        {
            "PermissionDenied" => WatcherStatusReason.PermissionDenied,
            "PathMissing" => WatcherStatusReason.PathMissing,
            "BackendUnavailable" => WatcherStatusReason.BackendUnavailable,
            "DatabaseLocked" => WatcherStatusReason.DatabaseLocked,
            "LimitExceeded" => WatcherStatusReason.LimitExceeded,
            "NetworkMount" => WatcherStatusReason.NetworkMount,
            "CloudSyncNoise" => WatcherStatusReason.CloudSyncNoise,
            "Unknown" => WatcherStatusReason.Unknown,
            _ => throw UnsupportedValue("watcher health reason", value)
        };
    }

    private static WatcherStatusEventKind ParseEventKind(string value)
    {
        return value switch
        {
            "Created" => WatcherStatusEventKind.Created,
            "Removed" => WatcherStatusEventKind.Removed,
            "Modified" => WatcherStatusEventKind.Modified,
            "Renamed" => WatcherStatusEventKind.Renamed,
            _ => throw UnsupportedValue("watcher event kind", value)
        };
    }

    private static ManualRescanPreviewItemKind ParseManualRescanPreviewItemKind(string value)
    {
        return value switch
        {
            "Added" => ManualRescanPreviewItemKind.Added,
            "Updated" => ManualRescanPreviewItemKind.Updated,
            "Missing" => ManualRescanPreviewItemKind.Missing,
            "RenamedCandidate" => ManualRescanPreviewItemKind.RenamedCandidate,
            "Conflict" => ManualRescanPreviewItemKind.Conflict,
            "Unreadable" => ManualRescanPreviewItemKind.Unreadable,
            "Unknown" => ManualRescanPreviewItemKind.Unknown,
            "Skipped" => ManualRescanPreviewItemKind.Skipped,
            _ => throw UnsupportedValue("manual rescan preview item kind", value)
        };
    }

    private static ScanSessionKind ParseScanSessionKind(string value)
    {
        return value switch
        {
            "Adopt" => ScanSessionKind.Adopt,
            "Reindex" => ScanSessionKind.Reindex,
            _ => throw UnsupportedValue("scan session kind", value)
        };
    }

    private static ScanSessionStatus ParseScanSessionStatus(string value)
    {
        return value switch
        {
            "Running" => ScanSessionStatus.Running,
            "Completed" => ScanSessionStatus.Completed,
            "Paused" => ScanSessionStatus.Paused,
            "Failed" => ScanSessionStatus.Failed,
            "Interrupted" => ScanSessionStatus.Interrupted,
            _ => throw UnsupportedValue("scan session status", value)
        };
    }

    private static WatcherStatusCoreException UnsupportedValue(string label, string value)
    {
        return new WatcherStatusCoreException(
            WindowsRepositoryErrorKind.Config,
            $"Unsupported {label} `{value}`.");
    }
}
