using System.Collections.Concurrent;
using AreaMatrix.Linux.Features.Onboarding;

namespace AreaMatrix.Linux.Features.System;

public interface ILinuxWatcherDiagnostics
{
    Task<LinuxWatcherStatusHealthSignal> CaptureSnapshotAsync(
        string repoPath,
        CancellationToken cancellationToken = default);

    Task<LinuxWatcherStatusHealthSignal> RestartWatcherAsync(
        string repoPath,
        CancellationToken cancellationToken = default);

    Task<string> ExportDiagnosticsAsync(
        string repoPath,
        LinuxWatcherStatusSnapshot snapshot,
        CancellationToken cancellationToken = default);

    Task OpenRepositoryFolderAsync(
        string repoPath,
        CancellationToken cancellationToken = default);
}

public sealed class LinuxWatcherDiagnostics : ILinuxWatcherDiagnostics
{
    private const int MaxRecentEvents = 5;

    private readonly IInotifyDiagnostics inotifyDiagnostics;
    private readonly ILinuxFolderOpener folderOpener;
    private readonly ConcurrentQueue<LinuxWatcherStatusEventSample> recentEvents = new();
    private string watchedPath = string.Empty;
    private long nextEventId;

    public LinuxWatcherDiagnostics(
        IInotifyDiagnostics? inotifyDiagnostics = null,
        ILinuxFolderOpener? folderOpener = null)
    {
        this.inotifyDiagnostics = inotifyDiagnostics ?? new ProcFsInotifyDiagnostics();
        this.folderOpener = folderOpener ?? new LinuxSystemFolderOpener();
    }

    public async Task<LinuxWatcherStatusHealthSignal> CaptureSnapshotAsync(
        string repoPath,
        CancellationToken cancellationToken = default)
    {
        cancellationToken.ThrowIfCancellationRequested();
        watchedPath = repoPath;
        LinuxInotifySnapshot inotify = await inotifyDiagnostics
            .ReadSnapshotAsync(repoPath, cancellationToken)
            .ConfigureAwait(false);
        return BuildSignal(repoPath, inotify, LinuxWatcherStatusKind.Running);
    }

    public async Task<LinuxWatcherStatusHealthSignal> RestartWatcherAsync(
        string repoPath,
        CancellationToken cancellationToken = default)
    {
        cancellationToken.ThrowIfCancellationRequested();
        watchedPath = repoPath;
        LinuxInotifySnapshot inotify = await inotifyDiagnostics
            .ReadSnapshotAsync(repoPath, cancellationToken)
            .ConfigureAwait(false);
        return BuildSignal(repoPath, inotify, LinuxWatcherStatusKind.Running);
    }

    public async Task<string> ExportDiagnosticsAsync(
        string repoPath,
        LinuxWatcherStatusSnapshot snapshot,
        CancellationToken cancellationToken = default)
    {
        cancellationToken.ThrowIfCancellationRequested();
        if (string.IsNullOrWhiteSpace(repoPath) || !Directory.Exists(repoPath))
        {
            throw new LinuxWatcherStatusCoreException(
                LinuxRepositoryErrorKind.FileNotFound,
                "Repository folder was not found.",
                repoPath);
        }

        string diagnosticsDirectory = Path.Combine(repoPath, ".areamatrix", "generated", "diagnostics");
        Directory.CreateDirectory(diagnosticsDirectory);
        string outputPath = DiagnosticOutputPath(diagnosticsDirectory);

        await File.WriteAllLinesAsync(
            outputPath,
            DiagnosticLines(snapshot),
            cancellationToken).ConfigureAwait(false);
        return outputPath;
    }

    public Task OpenRepositoryFolderAsync(
        string repoPath,
        CancellationToken cancellationToken = default)
    {
        return folderOpener.OpenFolderAsync(repoPath, cancellationToken);
    }

    private LinuxWatcherStatusHealthSignal BuildSignal(
        string repoPath,
        LinuxInotifySnapshot inotify,
        LinuxWatcherStatusKind fallbackStatus)
    {
        long reportedAt = DateTimeOffset.UtcNow.ToUnixTimeSeconds();
        IReadOnlyList<LinuxWatcherStatusReason> reasons = ReasonsFor(repoPath, inotify);
        LinuxWatcherStatusKind status = StatusFor(repoPath, inotify, reasons, fallbackStatus);
        string? errorSummary = ErrorSummaryFor(repoPath, status, reasons);
        IReadOnlyList<LinuxWatcherStatusEventSample> events = RecentEvents();

        return new LinuxWatcherStatusHealthSignal(
            LinuxWatcherStatusBackend.Inotify,
            status,
            repoPath,
            events.LastOrDefault()?.EventId,
            events.LastOrDefault()?.OccurredAt,
            null,
            null,
            null,
            0,
            inotify.WatchCount,
            errorSummary,
            reasons,
            events,
            reportedAt);
    }

    private LinuxWatcherStatusKind StatusFor(
        string repoPath,
        LinuxInotifySnapshot inotify,
        IReadOnlyList<LinuxWatcherStatusReason> reasons,
        LinuxWatcherStatusKind fallbackStatus)
    {
        if (string.IsNullOrWhiteSpace(repoPath))
        {
            return LinuxWatcherStatusKind.Unavailable;
        }

        if (reasons.Contains(LinuxWatcherStatusReason.PathMissing)
            || reasons.Contains(LinuxWatcherStatusReason.PermissionDenied))
        {
            return LinuxWatcherStatusKind.Error;
        }

        if (reasons.Contains(LinuxWatcherStatusReason.BackendUnavailable))
        {
            return LinuxWatcherStatusKind.Unavailable;
        }

        return inotify.IsLimitExceeded
            ? LinuxWatcherStatusKind.Error
            : fallbackStatus;
    }

    private static IReadOnlyList<LinuxWatcherStatusReason> ReasonsFor(
        string repoPath,
        LinuxInotifySnapshot inotify)
    {
        List<LinuxWatcherStatusReason> reasons = [];
        if (string.IsNullOrWhiteSpace(repoPath) || !Directory.Exists(repoPath))
        {
            reasons.Add(LinuxWatcherStatusReason.PathMissing);
        }
        else if (!HasReadPermission(repoPath))
        {
            reasons.Add(LinuxWatcherStatusReason.PermissionDenied);
        }

        if (inotify.IsBackendUnavailable)
        {
            reasons.Add(LinuxWatcherStatusReason.BackendUnavailable);
        }

        if (inotify.IsLimitExceeded)
        {
            reasons.Add(LinuxWatcherStatusReason.LimitExceeded);
        }

        if (IsLikelyNetworkMount(repoPath))
        {
            reasons.Add(LinuxWatcherStatusReason.NetworkMount);
        }

        return reasons;
    }

    private static string? ErrorSummaryFor(
        string repoPath,
        LinuxWatcherStatusKind status,
        IReadOnlyList<LinuxWatcherStatusReason> reasons)
    {
        if (reasons.Contains(LinuxWatcherStatusReason.PathMissing))
        {
            return "Repository path is missing or disconnected.";
        }

        if (reasons.Contains(LinuxWatcherStatusReason.PermissionDenied))
        {
            return "AreaMatrix cannot watch this folder because of permissions.";
        }

        if (reasons.Contains(LinuxWatcherStatusReason.LimitExceeded))
        {
            return "Linux has reached the inotify watch limit.";
        }

        if (status == LinuxWatcherStatusKind.Unavailable)
        {
            return "File watcher is not available for this repository.";
        }

        return string.IsNullOrWhiteSpace(repoPath)
            ? "Choose a repository before checking watcher status."
            : null;
    }

    public void RecordPlatformEvent(string fullPath, LinuxWatcherStatusEventKind kind)
    {
        string displayPath = RelativePathFor(fullPath);
        recentEvents.Enqueue(new LinuxWatcherStatusEventSample(
            displayPath,
            kind,
            Interlocked.Increment(ref nextEventId),
            DateTimeOffset.UtcNow.ToUnixTimeSeconds()));

        while (recentEvents.Count > MaxRecentEvents)
        {
            recentEvents.TryDequeue(out _);
        }
    }

    private IReadOnlyList<LinuxWatcherStatusEventSample> RecentEvents()
    {
        return recentEvents.ToArray();
    }

    private string RelativePathFor(string fullPath)
    {
        if (string.IsNullOrWhiteSpace(watchedPath))
        {
            return Path.GetFileName(fullPath);
        }

        string relative = Path.GetRelativePath(watchedPath, fullPath);
        return relative.StartsWith("..", StringComparison.Ordinal)
            ? Path.GetFileName(fullPath)
            : relative;
    }

    private static bool HasReadPermission(string repoPath)
    {
        try
        {
            Directory.EnumerateFileSystemEntries(repoPath).Take(1).ToArray();
            return true;
        }
        catch (UnauthorizedAccessException)
        {
            return false;
        }
    }

    private static bool IsLikelyNetworkMount(string repoPath)
    {
        string normalized = repoPath.Trim().Replace('\\', '/');
        return normalized.StartsWith("//", StringComparison.Ordinal)
            || normalized.StartsWith("/mnt/", StringComparison.Ordinal)
            || normalized.StartsWith("/net/", StringComparison.Ordinal);
    }

    private static string DiagnosticOutputPath(string diagnosticsDirectory)
    {
        return Path.Combine(
            diagnosticsDirectory,
            $"watcher-status-{DateTimeOffset.UtcNow:yyyyMMdd-HHmmss-fff}.txt");
    }

    private static IReadOnlyList<string> DiagnosticLines(LinuxWatcherStatusSnapshot snapshot)
    {
        List<string> lines =
        [
            "AreaMatrix Linux watcher diagnostics",
            $"Status: {snapshot.Status}",
            $"Backend: {snapshot.Backend}",
            $"Watched path: {snapshot.WatchedPath}",
            $"Pending events: {snapshot.PendingEventCount}",
            $"Last event id: {snapshot.LastEventId?.ToString() ?? "Unknown"}",
            $"Last event at: {snapshot.LastEventAt?.ToString() ?? "Unknown"}",
            $"Last sync event id: {snapshot.LastSyncEventId?.ToString() ?? "Unknown"}",
            $"Last sync at: {snapshot.LastSyncAt?.ToString() ?? "Unknown"}",
            $"Last rescan at: {snapshot.LastRescanAt?.ToString() ?? "Unknown"}",
            $"Watch count: {snapshot.WatchCount?.ToString() ?? "Unknown"}",
            $"Error summary: {snapshot.ErrorSummary ?? "None"}",
            $"Health reasons: {string.Join(", ", snapshot.HealthReasons)}",
            "Recent events are relative paths only; file contents are not exported."
        ];

        lines.AddRange(snapshot.RecentEvents.Select(eventSample =>
            $"- {eventSample.Kind}: {eventSample.Path} ({eventSample.EventId})"));
        return lines;
    }
}

public interface IInotifyDiagnostics
{
    Task<LinuxInotifySnapshot> ReadSnapshotAsync(
        string repoPath,
        CancellationToken cancellationToken = default);
}

public sealed record LinuxInotifySnapshot(
    long? WatchCount,
    long? MaxUserWatches,
    bool IsBackendUnavailable,
    bool IsLimitExceeded);

public sealed class ProcFsInotifyDiagnostics : IInotifyDiagnostics
{
    private const string MaxUserWatchesPath = "/proc/sys/fs/inotify/max_user_watches";

    public Task<LinuxInotifySnapshot> ReadSnapshotAsync(
        string repoPath,
        CancellationToken cancellationToken = default)
    {
        cancellationToken.ThrowIfCancellationRequested();
        long? maxWatches = ReadMaxUserWatches();
        bool backendUnavailable = !File.Exists(MaxUserWatchesPath);
        long? watchCount = Directory.Exists(repoPath) ? CountWatchedDirectories(repoPath) : null;
        bool limitExceeded = watchCount is { } count
            && maxWatches is { } max
            && count >= max;

        return Task.FromResult(new LinuxInotifySnapshot(
            watchCount,
            maxWatches,
            backendUnavailable,
            limitExceeded));
    }

    private static long? ReadMaxUserWatches()
    {
        try
        {
            return File.Exists(MaxUserWatchesPath)
                && long.TryParse(File.ReadAllText(MaxUserWatchesPath).Trim(), out long value)
                    ? value
                    : null;
        }
        catch (IOException)
        {
            return null;
        }
        catch (UnauthorizedAccessException)
        {
            return null;
        }
    }

    private static long CountWatchedDirectories(string repoPath)
    {
        try
        {
            return Directory.EnumerateDirectories(repoPath, "*", SearchOption.AllDirectories)
                .LongCount() + 1;
        }
        catch (Exception exception) when (exception is IOException or UnauthorizedAccessException)
        {
            return 1;
        }
    }
}
