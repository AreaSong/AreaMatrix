using System.Globalization;
using AreaMatrix.Linux.Features.Onboarding;

namespace AreaMatrix.Linux.Features.System;

public enum LinuxWatcherStatusBackend
{
    ReadDirectoryChangesW,
    Inotify,
    Unknown
}

public enum LinuxWatcherStatusKind
{
    Starting,
    Running,
    Paused,
    Error,
    Unavailable
}

public enum LinuxWatcherStatusReason
{
    PermissionDenied,
    PathMissing,
    BackendUnavailable,
    DatabaseLocked,
    LimitExceeded,
    NetworkMount,
    CloudSyncNoise,
    Unknown
}

public enum LinuxWatcherStatusEventKind
{
    Created,
    Removed,
    Modified,
    Renamed
}

public enum LinuxManualRescanPreviewItemKind
{
    Added,
    Updated,
    Missing,
    RenamedCandidate,
    Conflict,
    Unreadable,
    Unknown,
    Skipped
}

public enum LinuxScanSessionKind
{
    Adopt,
    Reindex
}

public enum LinuxScanSessionStatus
{
    Running,
    Completed,
    Paused,
    Failed,
    Interrupted
}

public sealed record LinuxWatcherStatusEventSample(
    string Path,
    LinuxWatcherStatusEventKind Kind,
    long EventId,
    long? OccurredAt)
{
    public string DisplayText => $"{Kind}: {Path}";

    public string OccurredAtText => FormatTimestamp(OccurredAt);

    private static string FormatTimestamp(long? unixSeconds)
    {
        if (unixSeconds is null or <= 0)
        {
            return "Unknown";
        }

        return DateTimeOffset
            .FromUnixTimeSeconds(unixSeconds.Value)
            .ToLocalTime()
            .ToString("g", CultureInfo.CurrentCulture);
    }
}

public sealed record LinuxManualRescanPreviewItem(
    LinuxManualRescanPreviewItemKind Kind,
    string RelativePath,
    string Reason,
    string SuggestedAction)
{
    public string DisplayText => $"{Kind}: {RelativePath}";

    public string DetailText => string.IsNullOrWhiteSpace(Reason)
        ? SuggestedAction
        : $"{Reason} - {SuggestedAction}";
}

public sealed record LinuxManualRescanPreviewReport(
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
    IReadOnlyList<LinuxManualRescanPreviewItem> Items)
{
    public bool HasNeedsReview => MissingOrDeletedFromFs > 0
        || Conflicts > 0
        || Unreadable > 0
        || Unknown > 0;

    public bool CanRunRescan => !IsStale;

    public string EstimatedItemsText => "Estimated items: "
        + (Added + Updated + MissingOrDeletedFromFs + RenamedCandidates + Conflicts + Unreadable + Unknown)
            .ToString(CultureInfo.CurrentCulture);

    public string SummaryText => "Preview impact: "
        + $"Added {Added.ToString(CultureInfo.CurrentCulture)}, "
        + $"Updated {Updated.ToString(CultureInfo.CurrentCulture)}, "
        + $"Missing {MissingOrDeletedFromFs.ToString(CultureInfo.CurrentCulture)}, "
        + $"Renamed candidates {RenamedCandidates.ToString(CultureInfo.CurrentCulture)}, "
        + $"Conflicts {Conflicts.ToString(CultureInfo.CurrentCulture)}, "
        + $"Unreadable {Unreadable.ToString(CultureInfo.CurrentCulture)}, "
        + $"Unknown {Unknown.ToString(CultureInfo.CurrentCulture)}, "
        + $"Skipped {Skipped.ToString(CultureInfo.CurrentCulture)}.";
}

public sealed record LinuxRescanConfirmRequest(
    LinuxRepositoryRoute Route,
    LinuxManualRescanPreviewReport Preview);

public sealed record LinuxScanSession(
    long Id,
    LinuxScanSessionKind Kind,
    LinuxScanSessionStatus Status,
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
    IReadOnlyList<string> Errors)
{
    public bool IsManualRescan => Kind == LinuxScanSessionKind.Reindex;

    public bool IsRunning => Status == LinuxScanSessionStatus.Running;

    public string DisplayText => $"Latest rescan session: {Status}, "
        + $"inserted {Inserted.ToString(CultureInfo.CurrentCulture)}, "
        + $"updated {Updated.ToString(CultureInfo.CurrentCulture)}, "
        + $"missing {Missing.ToString(CultureInfo.CurrentCulture)}, "
        + $"conflicts {Conflicts.ToString(CultureInfo.CurrentCulture)}.";
}

public sealed record LinuxWatcherStatusHealthSignal(
    LinuxWatcherStatusBackend Backend,
    LinuxWatcherStatusKind Status,
    string WatchedPath,
    long? LastEventId,
    long? LastEventAt,
    long? LastSyncEventId,
    long? LastSyncAt,
    long? LastRescanAt,
    long PendingEventCount,
    long? WatchCount,
    string? ErrorSummary,
    IReadOnlyList<LinuxWatcherStatusReason> HealthReasons,
    IReadOnlyList<LinuxWatcherStatusEventSample> RecentEvents,
    long ReportedAt);

public sealed record LinuxWatcherStatusSnapshot(
    string RepoPath,
    LinuxWatcherStatusBackend Backend,
    LinuxWatcherStatusKind Status,
    string WatchedPath,
    long? LastEventId,
    long? LastEventAt,
    long? LastSyncEventId,
    long? LastSyncAt,
    long? LastRescanAt,
    long PendingEventCount,
    long? WatchCount,
    string? ErrorSummary,
    IReadOnlyList<LinuxWatcherStatusReason> HealthReasons,
    IReadOnlyList<LinuxWatcherStatusEventSample> RecentEvents,
    long ReportedAt)
{
    public bool IsPathMissing => HealthReasons.Contains(LinuxWatcherStatusReason.PathMissing);

    public bool HasDatabaseLock => HealthReasons.Contains(LinuxWatcherStatusReason.DatabaseLocked);

    public bool HasLimitExceeded => HealthReasons.Contains(LinuxWatcherStatusReason.LimitExceeded);

    public bool HasNetworkMount => HealthReasons.Contains(LinuxWatcherStatusReason.NetworkMount);

    public bool HasPermissionDenied => HealthReasons.Contains(LinuxWatcherStatusReason.PermissionDenied);

    public bool IsBackendUnavailable => Status == LinuxWatcherStatusKind.Unavailable
        || HealthReasons.Contains(LinuxWatcherStatusReason.BackendUnavailable);

    public string StatusText => $"Status: {Status}";

    public string BackendText => $"Backend: {Backend}";

    public string WatchingText => string.IsNullOrWhiteSpace(WatchedPath)
        ? "Watching: Unavailable"
        : $"Watching: {WatchedPath}";

    public string WatchCountText => WatchCount is { } count
        ? $"Watches: {count.ToString(CultureInfo.CurrentCulture)}"
        : "Watches: Unknown";

    public string LastEventText => $"Last event: {FormatTimestamp(LastEventAt)}";

    public string LastSyncText => $"Last sync: {FormatTimestamp(LastSyncAt)}";

    public string LastRescanText => $"Last rescan: {FormatTimestamp(LastRescanAt)}";

    public string PendingEventsText => $"Pending events: {PendingEventCount.ToString(CultureInfo.CurrentCulture)}";

    public string SummaryText
    {
        get
        {
            if (!string.IsNullOrWhiteSpace(ErrorSummary))
            {
                return ErrorSummary;
            }

            if (HasLimitExceeded)
            {
                return "Linux has reached the inotify watch limit.";
            }

            if (HasPermissionDenied)
            {
                return "AreaMatrix cannot watch this folder because of permissions.";
            }

            if (HasNetworkMount)
            {
                return "This location may not report all file changes.";
            }

            return Status switch
            {
                LinuxWatcherStatusKind.Running
                    => "AreaMatrix is watching this folder through inotify.",
                LinuxWatcherStatusKind.Starting
                    => "AreaMatrix is starting the file watcher.",
                LinuxWatcherStatusKind.Paused
                    => "File changes may not appear until the watcher is restarted or a rescan runs.",
                LinuxWatcherStatusKind.Error
                    => "The watcher reported an error. Review the recovery actions below.",
                LinuxWatcherStatusKind.Unavailable
                    => "File watcher is not available for this repository.",
                _ => "File watcher status is unknown."
            };
        }
    }

    private static string FormatTimestamp(long? unixSeconds)
    {
        if (unixSeconds is null or <= 0)
        {
            return "Unknown";
        }

        return DateTimeOffset
            .FromUnixTimeSeconds(unixSeconds.Value)
            .ToLocalTime()
            .ToString("g", CultureInfo.CurrentCulture);
    }
}

public sealed class LinuxWatcherStatusCoreException : Exception
{
    public LinuxWatcherStatusCoreException(
        LinuxRepositoryErrorKind kind,
        string message,
        string? path = null)
        : base(message)
    {
        Kind = kind;
        Path = path;
    }

    public LinuxRepositoryErrorKind Kind { get; }

    public string? Path { get; }
}
