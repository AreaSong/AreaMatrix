using System;
using System.Collections.Generic;
using System.Globalization;
using System.Linq;
using AreaMatrix.Features.Onboarding;

namespace AreaMatrix.Features.Library;

public enum WatcherStatusBackend
{
    ReadDirectoryChangesW,
    Inotify,
    Unknown
}

public enum WatcherStatusKind
{
    Starting,
    Running,
    Paused,
    Error,
    Unavailable
}

public enum WatcherStatusReason
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

public enum WatcherStatusEventKind
{
    Created,
    Removed,
    Modified,
    Renamed
}

public enum ManualRescanPreviewItemKind
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

public enum ScanSessionKind
{
    Adopt,
    Reindex
}

public enum ScanSessionStatus
{
    Running,
    Completed,
    Paused,
    Failed,
    Interrupted
}

public sealed record WatcherStatusEventSample(
    string Path,
    WatcherStatusEventKind Kind,
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

public sealed record ManualRescanPreviewItem(
    ManualRescanPreviewItemKind Kind,
    string RelativePath,
    string Reason,
    string SuggestedAction)
{
    public string DisplayText => $"{Kind}: {RelativePath}";

    public string DetailText => string.IsNullOrWhiteSpace(Reason)
        ? SuggestedAction
        : $"{Reason} - {SuggestedAction}";
}

public sealed record ManualRescanPreviewReport(
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
    IReadOnlyList<ManualRescanPreviewItem> Items)
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

public sealed record ReindexReport(
    long? ScanSessionId,
    long Inserted,
    long Updated,
    long Missing,
    long Conflicts,
    long Unreadable,
    long Unknown,
    long Skipped,
    IReadOnlyList<string> Errors)
{
    public string SummaryText => "Rescan result: "
        + $"Inserted {Inserted.ToString(CultureInfo.CurrentCulture)}, "
        + $"Updated {Updated.ToString(CultureInfo.CurrentCulture)}, "
        + $"Missing {Missing.ToString(CultureInfo.CurrentCulture)}, "
        + $"Conflicts {Conflicts.ToString(CultureInfo.CurrentCulture)}, "
        + $"Unreadable {Unreadable.ToString(CultureInfo.CurrentCulture)}, "
        + $"Unknown {Unknown.ToString(CultureInfo.CurrentCulture)}, "
        + $"Skipped {Skipped.ToString(CultureInfo.CurrentCulture)}.";

    public bool HasNeedsReview => Missing > 0
        || Conflicts > 0
        || Unreadable > 0
        || Unknown > 0;
}

public sealed record RescanConfirmRequest(
    WindowsRepositoryRoute Route,
    ManualRescanPreviewReport Preview);

public sealed record ScanSession(
    long Id,
    ScanSessionKind Kind,
    ScanSessionStatus Status,
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
    public bool IsManualRescan => Kind == ScanSessionKind.Reindex;

    public bool IsRunning => Status == ScanSessionStatus.Running;

    public bool CanResume => IsManualRescan
        && (Status == ScanSessionStatus.Paused
            || Status == ScanSessionStatus.Failed
            || Status == ScanSessionStatus.Interrupted);

    public string DisplayText => $"Latest rescan session: {Status}, "
        + $"inserted {Inserted.ToString(CultureInfo.CurrentCulture)}, "
        + $"updated {Updated.ToString(CultureInfo.CurrentCulture)}, "
        + $"missing {Missing.ToString(CultureInfo.CurrentCulture)}, "
        + $"conflicts {Conflicts.ToString(CultureInfo.CurrentCulture)}.";
}

public sealed record WatcherStatusHealthSignal(
    WatcherStatusBackend Backend,
    WatcherStatusKind Status,
    string WatchedPath,
    long? LastEventId,
    long? LastEventAt,
    long? LastSyncEventId,
    long? LastSyncAt,
    long? LastRescanAt,
    long PendingEventCount,
    long? WatchCount,
    string? ErrorSummary,
    IReadOnlyList<WatcherStatusReason> HealthReasons,
    IReadOnlyList<WatcherStatusEventSample> RecentEvents,
    long ReportedAt);

public sealed record WatcherStatusSnapshot(
    string RepoPath,
    WatcherStatusBackend Backend,
    WatcherStatusKind Status,
    string WatchedPath,
    long? LastEventId,
    long? LastEventAt,
    long? LastSyncEventId,
    long? LastSyncAt,
    long? LastRescanAt,
    long PendingEventCount,
    long? WatchCount,
    string? ErrorSummary,
    IReadOnlyList<WatcherStatusReason> HealthReasons,
    IReadOnlyList<WatcherStatusEventSample> RecentEvents,
    long ReportedAt)
{
    public bool HasOneDriveNoise => HealthReasons.Contains(WatcherStatusReason.CloudSyncNoise)
        || WatchedPath.Contains("OneDrive", StringComparison.OrdinalIgnoreCase);

    public bool IsPathMissing => HealthReasons.Contains(WatcherStatusReason.PathMissing);

    public bool HasDatabaseLock => HealthReasons.Contains(WatcherStatusReason.DatabaseLocked);

    public bool IsBackendUnavailable => Status == WatcherStatusKind.Unavailable
        || HealthReasons.Contains(WatcherStatusReason.BackendUnavailable);

    public string StatusText => $"Status: {Status}";

    public string WatchingText => string.IsNullOrWhiteSpace(WatchedPath)
        ? "Watching: Unavailable"
        : $"Watching: {WatchedPath}";

    public string LastEventText => $"Last event: {FormatTimestamp(LastEventAt)}";

    public string PendingEventsText => $"Pending events: {PendingEventCount.ToString(CultureInfo.CurrentCulture)}";

    public string LastRescanText => $"Last rescan: {FormatTimestamp(LastRescanAt)}";

    public string LastSyncText => $"Last sync: {FormatTimestamp(LastSyncAt)}";

    public string BackendText => $"Backend: {Backend}";

    public string WatchCountText => WatchCount is { } count
        ? $"Watch count: {count.ToString(CultureInfo.CurrentCulture)}"
        : "Watch count: Unknown";

    public string SummaryText
    {
        get
        {
            if (!string.IsNullOrWhiteSpace(ErrorSummary))
            {
                return ErrorSummary;
            }

            return Status switch
            {
                WatcherStatusKind.Running
                    => "AreaMatrix is watching this folder for external changes.",
                WatcherStatusKind.Starting
                    => "AreaMatrix is starting the file watcher.",
                WatcherStatusKind.Paused
                    => "File changes may not appear until the watcher is restarted or a rescan runs.",
                WatcherStatusKind.Error
                    => "The watcher reported an error. Review the recovery actions below.",
                WatcherStatusKind.Unavailable
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

public sealed class WatcherStatusCoreException : Exception
{
    public WatcherStatusCoreException(
        WindowsRepositoryErrorKind kind,
        string message,
        string? path = null)
        : base(message)
    {
        Kind = kind;
        Path = path;
    }

    public WindowsRepositoryErrorKind Kind { get; }

    public string? Path { get; }
}
