using System;
using System.Collections.Generic;
using System.IO;
using System.Linq;
using System.Threading;
using System.Threading.Tasks;

namespace AreaMatrix.Features.Library;

public interface IWindowsWatcherDiagnostics
{
    Task<WatcherStatusHealthSignal> CaptureSnapshotAsync(
        string repoPath,
        CancellationToken cancellationToken = default);

    Task<WatcherStatusHealthSignal> RestartWatcherAsync(
        string repoPath,
        CancellationToken cancellationToken = default);
}

public sealed class WindowsWatcherDiagnostics : IWindowsWatcherDiagnostics, IDisposable
{
    private const int MaxRecentEvents = 5;

    private readonly object syncRoot = new();
    private readonly Queue<WatcherStatusEventSample> recentEvents = new();
    private FileSystemWatcher? watcher;
    private string watchedPath = string.Empty;
    private long nextEventId;
    private bool disposed;

    public Task<WatcherStatusHealthSignal> CaptureSnapshotAsync(
        string repoPath,
        CancellationToken cancellationToken = default)
    {
        cancellationToken.ThrowIfCancellationRequested();
        lock (syncRoot)
        {
            ResetIfRepositoryChanged(repoPath);
            watchedPath = repoPath;
            return Task.FromResult(BuildSignal(repoPath));
        }
    }

    public Task<WatcherStatusHealthSignal> RestartWatcherAsync(
        string repoPath,
        CancellationToken cancellationToken = default)
    {
        cancellationToken.ThrowIfCancellationRequested();
        lock (syncRoot)
        {
            StopWatcher();
            EnsureWatcher(repoPath);
            return Task.FromResult(BuildSignal(repoPath));
        }
    }

    public void Dispose()
    {
        if (disposed)
        {
            return;
        }

        lock (syncRoot)
        {
            StopWatcher();
            disposed = true;
        }
    }

    private void EnsureWatcher(string repoPath)
    {
        if (string.IsNullOrWhiteSpace(repoPath) || !Directory.Exists(repoPath))
        {
            StopWatcher();
            watchedPath = repoPath;
            return;
        }

        if (watcher is not null && string.Equals(watchedPath, repoPath, StringComparison.OrdinalIgnoreCase))
        {
            return;
        }

        StopWatcher();
        watchedPath = repoPath;
        FileSystemWatcher newWatcher = new(repoPath)
        {
            IncludeSubdirectories = true,
            NotifyFilter = NotifyFilters.FileName | NotifyFilters.DirectoryName | NotifyFilters.LastWrite,
            EnableRaisingEvents = true
        };
        newWatcher.Created += Watcher_Created;
        newWatcher.Changed += Watcher_Changed;
        newWatcher.Deleted += Watcher_Deleted;
        newWatcher.Renamed += Watcher_Renamed;
        newWatcher.Error += Watcher_Error;
        watcher = newWatcher;
    }

    private WatcherStatusHealthSignal BuildSignal(string repoPath)
    {
        long reportedAt = DateTimeOffset.UtcNow.ToUnixTimeSeconds();
        IReadOnlyList<WatcherStatusEventSample> events = recentEvents.ToArray();
        WatcherStatusKind status = StatusFor(repoPath);
        IReadOnlyList<WatcherStatusReason> reasons = ReasonsFor(repoPath, status);
        string? errorSummary = ErrorSummaryFor(repoPath, status, reasons);

        return new WatcherStatusHealthSignal(
            WatcherStatusBackend.ReadDirectoryChangesW,
            status,
            watchedPath,
            events.LastOrDefault()?.EventId,
            events.LastOrDefault()?.OccurredAt,
            null,
            null,
            null,
            0,
            watcher is null ? null : 1,
            errorSummary,
            reasons,
            events,
            reportedAt);
    }

    private WatcherStatusKind StatusFor(string repoPath)
    {
        if (string.IsNullOrWhiteSpace(repoPath))
        {
            return WatcherStatusKind.Unavailable;
        }

        if (!Directory.Exists(repoPath))
        {
            return WatcherStatusKind.Error;
        }

        if (watcher is null)
        {
            return WatcherStatusKind.Paused;
        }

        return watcher.EnableRaisingEvents
            ? WatcherStatusKind.Running
            : WatcherStatusKind.Paused;
    }

    private IReadOnlyList<WatcherStatusReason> ReasonsFor(string repoPath, WatcherStatusKind status)
    {
        List<WatcherStatusReason> reasons = [];
        if (string.IsNullOrWhiteSpace(repoPath) || !Directory.Exists(repoPath))
        {
            reasons.Add(WatcherStatusReason.PathMissing);
        }

        if (status == WatcherStatusKind.Unavailable)
        {
            reasons.Add(WatcherStatusReason.BackendUnavailable);
        }

        if (repoPath.Contains("OneDrive", StringComparison.OrdinalIgnoreCase))
        {
            reasons.Add(WatcherStatusReason.CloudSyncNoise);
        }

        return reasons;
    }

    private static string? ErrorSummaryFor(
        string repoPath,
        WatcherStatusKind status,
        IReadOnlyList<WatcherStatusReason> reasons)
    {
        if (reasons.Contains(WatcherStatusReason.PathMissing))
        {
            return "Repository path is missing or disconnected.";
        }

        if (status == WatcherStatusKind.Unavailable)
        {
            return "File watcher is not available for this repository.";
        }

        return string.IsNullOrWhiteSpace(repoPath)
            ? "Choose a repository before checking watcher status."
            : null;
    }

    private void StopWatcher()
    {
        if (watcher is null)
        {
            return;
        }

        watcher.EnableRaisingEvents = false;
        watcher.Created -= Watcher_Created;
        watcher.Changed -= Watcher_Changed;
        watcher.Deleted -= Watcher_Deleted;
        watcher.Renamed -= Watcher_Renamed;
        watcher.Error -= Watcher_Error;
        watcher.Dispose();
        watcher = null;
    }

    private void ResetIfRepositoryChanged(string repoPath)
    {
        if (watcher is not null && !string.Equals(watchedPath, repoPath, StringComparison.OrdinalIgnoreCase))
        {
            StopWatcher();
        }
    }

    private void Watcher_Created(object sender, FileSystemEventArgs e)
    {
        AddEvent(e.FullPath, WatcherStatusEventKind.Created);
    }

    private void Watcher_Changed(object sender, FileSystemEventArgs e)
    {
        AddEvent(e.FullPath, WatcherStatusEventKind.Modified);
    }

    private void Watcher_Deleted(object sender, FileSystemEventArgs e)
    {
        AddEvent(e.FullPath, WatcherStatusEventKind.Removed);
    }

    private void Watcher_Renamed(object sender, RenamedEventArgs e)
    {
        AddEvent(e.FullPath, WatcherStatusEventKind.Renamed);
    }

    private void Watcher_Error(object sender, ErrorEventArgs e)
    {
        lock (syncRoot)
        {
            StopWatcher();
        }
    }

    private void AddEvent(string fullPath, WatcherStatusEventKind kind)
    {
        lock (syncRoot)
        {
            string displayPath = RelativePathFor(fullPath);
            recentEvents.Enqueue(new WatcherStatusEventSample(
                displayPath,
                kind,
                nextEventId,
                DateTimeOffset.UtcNow.ToUnixTimeSeconds()));
            nextEventId += 1;

            while (recentEvents.Count > MaxRecentEvents)
            {
                recentEvents.Dequeue();
            }
        }
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
}
