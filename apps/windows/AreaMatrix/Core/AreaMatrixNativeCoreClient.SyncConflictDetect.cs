using System.Collections.Generic;
using System.Threading;
using System.Threading.Tasks;
using AreaMatrix.Features.Conflicts;

namespace AreaMatrix.Core;

public sealed partial class AreaMatrixNativeCoreClient
{
    public Task<IReadOnlyList<CoreSyncConflictEntry>> DetectSyncConflictsAsync(
        string repoPath,
        CancellationToken cancellationToken = default)
    {
        cancellationToken.ThrowIfCancellationRequested();
        IReadOnlyList<CoreSyncConflictEntry> conflicts = CallWithResult(
            (ref RustCallStatus status) => native.DetectSyncConflicts(LowerString(repoPath), ref status),
            ReadSyncConflicts);
        return Task.FromResult(conflicts);
    }

    private static IReadOnlyList<CoreSyncConflictEntry> ReadSyncConflicts(UniFfiReader reader)
    {
        int count = reader.ReadInt32();
        List<CoreSyncConflictEntry> conflicts = new(count);
        for (int index = 0; index < count; index += 1)
        {
            conflicts.Add(ReadSyncConflict(reader));
        }

        return conflicts;
    }

    private static CoreSyncConflictEntry ReadSyncConflict(UniFfiReader reader)
    {
        return new CoreSyncConflictEntry(
            reader.ReadString(),
            ReadSyncConflictType(reader),
            ReadSyncConflictSeverity(reader),
            ReadSyncConflictStatus(reader),
            reader.ReadString(),
            ReadSyncConflictAffectedFiles(reader),
            reader.ReadInt64(),
            ReadOptionalString(reader),
            ReadOptionalInt64(reader),
            ReadOptionalString(reader));
    }

    private static IReadOnlyList<CoreSyncConflictAffectedFile> ReadSyncConflictAffectedFiles(
        UniFfiReader reader)
    {
        int count = reader.ReadInt32();
        List<CoreSyncConflictAffectedFile> files = new(count);
        for (int index = 0; index < count; index += 1)
        {
            files.Add(ReadSyncConflictAffectedFile(reader));
        }

        return files;
    }

    private static CoreSyncConflictAffectedFile ReadSyncConflictAffectedFile(UniFfiReader reader)
    {
        return new CoreSyncConflictAffectedFile(
            reader.ReadString(),
            ReadOptionalInt64(reader),
            ReadSyncConflictFileRole(reader),
            ReadOptionalInt64(reader),
            ReadOptionalInt64(reader),
            ReadOptionalString(reader),
            ReadOptionalString(reader));
    }

    private static string ReadSyncConflictStatus(UniFfiReader reader)
    {
        return reader.ReadInt32() switch
        {
            1 => "NeedsReview",
            2 => "Resolved",
            _ => throw BindingConfigError("AreaMatrix Core returned an unknown sync conflict status.")
        };
    }

    private static string ReadSyncConflictType(UniFfiReader reader)
    {
        return reader.ReadInt32() switch
        {
            1 => "SameNameDifferentContent",
            2 => "ConcurrentModification",
            3 => "MetadataMismatch",
            4 => "MissingVersion",
            5 => "Unknown",
            _ => throw BindingConfigError("AreaMatrix Core returned an unknown sync conflict type.")
        };
    }

    private static string ReadSyncConflictSeverity(UniFfiReader reader)
    {
        return reader.ReadInt32() switch
        {
            1 => "Low",
            2 => "Medium",
            3 => "High",
            _ => throw BindingConfigError("AreaMatrix Core returned an unknown sync conflict severity.")
        };
    }

    private static string ReadSyncConflictFileRole(UniFfiReader reader)
    {
        return reader.ReadInt32() switch
        {
            1 => "Existing",
            2 => "Incoming",
            3 => "ConflictCopy",
            4 => "Missing",
            5 => "Unknown",
            _ => throw BindingConfigError("AreaMatrix Core returned an unknown sync conflict file role.")
        };
    }
}
