using AreaMatrix.Linux.Features.Onboarding;
using AreaMatrix.Linux.Features.System;

namespace AreaMatrix.Linux.Core;

public sealed partial class AreaMatrixNativeCoreClient
{
    public Task<CoreLinuxManualRescanPreviewReport> PreviewManualRescanAsync(
        string repoPath,
        CancellationToken cancellationToken = default)
    {
        cancellationToken.ThrowIfCancellationRequested();
        CoreLinuxManualRescanPreviewReport report = CallWithResult(
            (ref RustCallStatus status) => native.PreviewManualRescan(
                LowerString(repoPath),
                ref status),
            ReadManualRescanPreviewReport);
        return Task.FromResult(report);
    }

    public Task<CoreLinuxReindexReport> ReindexFromFilesystemAsync(
        string repoPath,
        CancellationToken cancellationToken = default)
    {
        cancellationToken.ThrowIfCancellationRequested();
        CoreLinuxReindexReport report = CallWithResult(
            (ref RustCallStatus status) => native.ReindexFromFilesystem(
                LowerString(repoPath),
                ref status),
            ReadReindexReport);
        return Task.FromResult(report);
    }

    public Task<CoreLinuxScanSession?> GetLatestScanSessionAsync(
        string repoPath,
        CancellationToken cancellationToken = default)
    {
        cancellationToken.ThrowIfCancellationRequested();
        CoreLinuxScanSession? session = CallWithResult(
            (ref RustCallStatus status) => native.GetLatestScanSession(
                LowerString(repoPath),
                ref status),
            ReadOptionalScanSession);
        return Task.FromResult(session);
    }

    public Task<CoreLinuxReindexReport> ResumeScanSessionAsync(
        string repoPath,
        long scanSessionId,
        CancellationToken cancellationToken = default)
    {
        cancellationToken.ThrowIfCancellationRequested();
        CoreLinuxReindexReport report = CallWithResult(
            (ref RustCallStatus status) => native.ResumeScanSession(
                LowerString(repoPath),
                scanSessionId,
                ref status),
            ReadReindexReport);
        return Task.FromResult(report);
    }

    public Task<CoreLinuxWatcherStatusSnapshot> RecordWatcherHealthAsync(
        string repoPath,
        CoreLinuxWatcherStatusHealthSignal signal,
        CancellationToken cancellationToken = default)
    {
        cancellationToken.ThrowIfCancellationRequested();
        CoreLinuxWatcherStatusSnapshot snapshot = CallWithResult(
            (ref RustCallStatus status) => native.RecordWatcherHealth(
                LowerString(repoPath),
                LowerWatcherHealthSignal(signal),
                ref status),
            ReadWatcherStatusSnapshot);
        return Task.FromResult(snapshot);
    }

    private CoreLinuxManualRescanPreviewReport ReadManualRescanPreviewReport(UniFfiReader reader)
    {
        return new CoreLinuxManualRescanPreviewReport(
            reader.ReadInt64(),
            reader.ReadInt64(),
            reader.ReadInt64(),
            reader.ReadInt64(),
            reader.ReadInt64(),
            reader.ReadInt64(),
            reader.ReadInt64(),
            reader.ReadInt64(),
            reader.ReadString(),
            reader.ReadInt64(),
            reader.ReadBool(),
            ReadManualRescanPreviewItems(reader));
    }

    private IReadOnlyList<CoreLinuxManualRescanPreviewItem> ReadManualRescanPreviewItems(
        UniFfiReader reader)
    {
        int count = reader.ReadInt32();
        List<CoreLinuxManualRescanPreviewItem> items = new(count);
        for (int index = 0; index < count; index += 1)
        {
            items.Add(new CoreLinuxManualRescanPreviewItem(
                ReadManualRescanPreviewItemKind(reader),
                reader.ReadString(),
                reader.ReadString(),
                reader.ReadString()));
        }

        return items;
    }

    private CoreLinuxReindexReport ReadReindexReport(UniFfiReader reader)
    {
        return new CoreLinuxReindexReport(
            ReadOptionalInt64(reader),
            reader.ReadInt64(),
            reader.ReadInt64(),
            reader.ReadInt64(),
            reader.ReadInt64(),
            reader.ReadInt64(),
            reader.ReadInt64(),
            reader.ReadInt64(),
            ReadStrings(reader));
    }

    private CoreLinuxScanSession? ReadOptionalScanSession(UniFfiReader reader)
    {
        return reader.ReadByte() switch
        {
            0 => null,
            1 => ReadScanSession(reader),
            _ => throw BindingConfigError("AreaMatrix Core returned an invalid scan session optional tag.")
        };
    }

    private CoreLinuxScanSession ReadScanSession(UniFfiReader reader)
    {
        return new CoreLinuxScanSession(
            reader.ReadInt64(),
            ReadScanSessionKind(reader),
            ReadScanSessionStatus(reader),
            ReadOptionalString(reader),
            reader.ReadInt64(),
            reader.ReadInt64(),
            reader.ReadInt64(),
            reader.ReadInt64(),
            reader.ReadInt64(),
            reader.ReadInt64(),
            reader.ReadInt64(),
            reader.ReadInt64(),
            reader.ReadInt64(),
            ReadOptionalInt64(reader),
            ReadStrings(reader));
    }

    private CoreLinuxWatcherStatusSnapshot ReadWatcherStatusSnapshot(UniFfiReader reader)
    {
        return new CoreLinuxWatcherStatusSnapshot(
            reader.ReadString(),
            ReadWatcherBackend(reader),
            ReadWatcherStatus(reader),
            reader.ReadString(),
            ReadOptionalInt64(reader),
            ReadOptionalInt64(reader),
            ReadOptionalInt64(reader),
            ReadOptionalInt64(reader),
            ReadOptionalInt64(reader),
            reader.ReadInt64(),
            ReadOptionalInt64(reader),
            ReadOptionalString(reader),
            ReadWatcherHealthReasons(reader),
            ReadWatcherEventSamples(reader),
            reader.ReadInt64());
    }

    private IReadOnlyList<CoreLinuxWatcherStatusEventSample> ReadWatcherEventSamples(
        UniFfiReader reader)
    {
        int count = reader.ReadInt32();
        List<CoreLinuxWatcherStatusEventSample> events = new(count);
        for (int index = 0; index < count; index += 1)
        {
            events.Add(new CoreLinuxWatcherStatusEventSample(
                reader.ReadString(),
                ReadExternalEventKind(reader),
                reader.ReadInt64(),
                ReadOptionalInt64(reader)));
        }

        return events;
    }

    private IReadOnlyList<string> ReadWatcherHealthReasons(UniFfiReader reader)
    {
        int count = reader.ReadInt32();
        List<string> reasons = new(count);
        for (int index = 0; index < count; index += 1)
        {
            reasons.Add(ReadWatcherHealthReason(reader));
        }

        return reasons;
    }

    private static IReadOnlyList<string> ReadStrings(UniFfiReader reader)
    {
        int count = reader.ReadInt32();
        List<string> values = new(count);
        for (int index = 0; index < count; index += 1)
        {
            values.Add(reader.ReadString());
        }

        return values;
    }

    private RustBuffer LowerWatcherHealthSignal(CoreLinuxWatcherStatusHealthSignal signal)
    {
        List<byte> bytes = [];
        WriteWatcherBackend(bytes, signal.Backend);
        WriteWatcherStatus(bytes, signal.Status);
        WriteString(bytes, signal.WatchedPath);
        WriteOptionalInt64(bytes, signal.LastEventId);
        WriteOptionalInt64(bytes, signal.LastEventAt);
        WriteOptionalInt64(bytes, signal.LastSyncEventId);
        WriteOptionalInt64(bytes, signal.LastSyncAt);
        WriteOptionalInt64(bytes, signal.LastRescanAt);
        WriteInt64(bytes, signal.PendingEventCount);
        WriteOptionalInt64(bytes, signal.WatchCount);
        WriteOptionalString(bytes, signal.ErrorSummary);
        WriteWatcherHealthReasons(bytes, signal.HealthReasons);
        WriteWatcherEventSamples(bytes, signal.RecentEvents);
        WriteInt64(bytes, signal.ReportedAt);
        return RustBufferFromBytes(bytes.ToArray());
    }

    private static void WriteWatcherEventSamples(
        List<byte> bytes,
        IReadOnlyList<CoreLinuxWatcherStatusEventSample> events)
    {
        WriteInt32(bytes, events.Count);
        foreach (CoreLinuxWatcherStatusEventSample eventSample in events)
        {
            WriteString(bytes, eventSample.Path);
            WriteExternalEventKind(bytes, eventSample.Kind);
            WriteInt64(bytes, eventSample.EventId);
            WriteOptionalInt64(bytes, eventSample.OccurredAt);
        }
    }

    private static void WriteWatcherHealthReasons(List<byte> bytes, IReadOnlyList<string> reasons)
    {
        WriteInt32(bytes, reasons.Count);
        foreach (string reason in reasons)
        {
            WriteWatcherHealthReason(bytes, reason);
        }
    }

    private static string ReadExternalEventKind(UniFfiReader reader)
    {
        return reader.ReadInt32() switch
        {
            1 => "Created",
            2 => "Removed",
            3 => "Modified",
            4 => "Renamed",
            _ => throw BindingConfigError("AreaMatrix Core returned an unknown external event kind.")
        };
    }

    private static string ReadWatcherBackend(UniFfiReader reader)
    {
        return reader.ReadInt32() switch
        {
            1 => "ReadDirectoryChangesW",
            2 => "Inotify",
            3 => "Unknown",
            _ => throw BindingConfigError("AreaMatrix Core returned an unknown watcher backend.")
        };
    }

    private static string ReadWatcherStatus(UniFfiReader reader)
    {
        return reader.ReadInt32() switch
        {
            1 => "Starting",
            2 => "Running",
            3 => "Paused",
            4 => "Error",
            5 => "Unavailable",
            _ => throw BindingConfigError("AreaMatrix Core returned an unknown watcher status.")
        };
    }

    private static string ReadWatcherHealthReason(UniFfiReader reader)
    {
        return reader.ReadInt32() switch
        {
            1 => "PermissionDenied",
            2 => "PathMissing",
            3 => "BackendUnavailable",
            4 => "DatabaseLocked",
            5 => "LimitExceeded",
            6 => "NetworkMount",
            7 => "CloudSyncNoise",
            8 => "Unknown",
            _ => throw BindingConfigError("AreaMatrix Core returned an unknown watcher health reason.")
        };
    }

    private static string ReadManualRescanPreviewItemKind(UniFfiReader reader)
    {
        return reader.ReadInt32() switch
        {
            1 => "Added",
            2 => "Updated",
            3 => "Missing",
            4 => "RenamedCandidate",
            5 => "Conflict",
            6 => "Unreadable",
            7 => "Unknown",
            8 => "Skipped",
            _ => throw BindingConfigError("AreaMatrix Core returned an unknown manual rescan item kind.")
        };
    }

    private static string ReadScanSessionKind(UniFfiReader reader)
    {
        return reader.ReadInt32() switch
        {
            1 => "Adopt",
            2 => "Reindex",
            _ => throw BindingConfigError("AreaMatrix Core returned an unknown scan session kind.")
        };
    }

    private static string ReadScanSessionStatus(UniFfiReader reader)
    {
        return reader.ReadInt32() switch
        {
            1 => "Running",
            2 => "Completed",
            3 => "Paused",
            4 => "Failed",
            5 => "Interrupted",
            _ => throw BindingConfigError("AreaMatrix Core returned an unknown scan session status.")
        };
    }

    private static void WriteExternalEventKind(List<byte> bytes, string kind)
    {
        WriteEnum(bytes, kind switch
        {
            "Created" => 1,
            "Removed" => 2,
            "Modified" => 3,
            "Renamed" => 4,
            _ => throw UnsupportedWatcherValue("external event kind", kind)
        });
    }

    private static void WriteWatcherBackend(List<byte> bytes, string backend)
    {
        WriteEnum(bytes, backend switch
        {
            "ReadDirectoryChangesW" => 1,
            "Inotify" => 2,
            "Unknown" => 3,
            _ => throw UnsupportedWatcherValue("watcher backend", backend)
        });
    }

    private static void WriteWatcherStatus(List<byte> bytes, string status)
    {
        WriteEnum(bytes, status switch
        {
            "Starting" => 1,
            "Running" => 2,
            "Paused" => 3,
            "Error" => 4,
            "Unavailable" => 5,
            _ => throw UnsupportedWatcherValue("watcher status", status)
        });
    }

    private static void WriteWatcherHealthReason(List<byte> bytes, string reason)
    {
        WriteEnum(bytes, reason switch
        {
            "PermissionDenied" => 1,
            "PathMissing" => 2,
            "BackendUnavailable" => 3,
            "DatabaseLocked" => 4,
            "LimitExceeded" => 5,
            "NetworkMount" => 6,
            "CloudSyncNoise" => 7,
            "Unknown" => 8,
            _ => throw UnsupportedWatcherValue("watcher health reason", reason)
        });
    }

    private static LinuxWatcherStatusCoreException UnsupportedWatcherValue(string label, string value)
    {
        return new LinuxWatcherStatusCoreException(
            LinuxRepositoryErrorKind.Config,
            $"Unsupported {label} `{value}`.");
    }
}
