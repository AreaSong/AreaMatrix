using System.Collections.Generic;
using System.Threading;
using System.Threading.Tasks;
using AreaMatrix.Features.Library;
using AreaMatrix.Features.Onboarding;

namespace AreaMatrix.Core;

public sealed partial class AreaMatrixNativeCoreClient
{
    public Task<CoreWatcherStatusSnapshot> RecordWatcherHealthAsync(
        string repoPath,
        CoreWatcherStatusHealthSignal signal,
        CancellationToken cancellationToken = default)
    {
        cancellationToken.ThrowIfCancellationRequested();
        CoreWatcherStatusSnapshot snapshot = CallWithResult(
            (ref RustCallStatus status) => native.RecordWatcherHealth(
                LowerString(repoPath),
                LowerWatcherHealthSignal(signal),
                ref status),
            ReadWatcherStatusSnapshot);
        return Task.FromResult(snapshot);
    }

    private CoreWatcherStatusSnapshot ReadWatcherStatusSnapshot(UniFfiReader reader)
    {
        return new CoreWatcherStatusSnapshot(
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

    private IReadOnlyList<CoreWatcherStatusEventSample> ReadWatcherEventSamples(UniFfiReader reader)
    {
        int count = reader.ReadInt32();
        List<CoreWatcherStatusEventSample> events = new(count);
        for (int index = 0; index < count; index += 1)
        {
            events.Add(new CoreWatcherStatusEventSample(
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

    private RustBuffer LowerWatcherHealthSignal(CoreWatcherStatusHealthSignal signal)
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
        IReadOnlyList<CoreWatcherStatusEventSample> events)
    {
        WriteInt32(bytes, events.Count);
        foreach (CoreWatcherStatusEventSample eventSample in events)
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

    private static WatcherStatusCoreException UnsupportedWatcherValue(string label, string value)
    {
        return new WatcherStatusCoreException(
            WindowsRepositoryErrorKind.Config,
            $"Unsupported {label} `{value}`.");
    }
}
