using AreaMatrix.Linux.Features.Onboarding;

namespace AreaMatrix.Linux.Features.System;

public interface ILinuxWatcherStatusCoreBridge
{
    Task<LinuxWatcherStatusSnapshot> RecordWatcherHealthAsync(
        string repoPath,
        LinuxWatcherStatusHealthSignal signal,
        CancellationToken cancellationToken = default);
}

public interface IAreaMatrixLinuxWatcherStatusCoreClient
{
    Task<CoreLinuxWatcherStatusSnapshot> RecordWatcherHealthAsync(
        string repoPath,
        CoreLinuxWatcherStatusHealthSignal signal,
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

    private static LinuxWatcherStatusCoreException UnsupportedValue(string label, string value)
    {
        return new LinuxWatcherStatusCoreException(
            LinuxRepositoryErrorKind.Config,
            $"Unsupported {label} `{value}`.");
    }
}
