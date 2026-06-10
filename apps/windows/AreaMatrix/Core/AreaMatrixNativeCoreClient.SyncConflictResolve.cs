using System.Collections.Generic;
using System.Threading;
using System.Threading.Tasks;
using AreaMatrix.Features.Conflicts;

namespace AreaMatrix.Core;

public sealed partial class AreaMatrixNativeCoreClient
{
    public Task<CoreSyncConflictResolutionPreviewReport> PreviewSyncConflictResolutionAsync(
        string repoPath,
        string conflictId,
        string resolution,
        CancellationToken cancellationToken = default)
    {
        cancellationToken.ThrowIfCancellationRequested();
        CoreSyncConflictResolutionPreviewReport preview = CallWithResult(
            (ref RustCallStatus status) => native.PreviewSyncConflictResolution(
                LowerString(repoPath),
                LowerString(conflictId),
                LowerSyncConflictResolutionStrategy(resolution),
                ref status),
            ReadSyncConflictResolutionPreviewReport);
        return Task.FromResult(preview);
    }

    public Task<CoreSyncConflictResolveReport> ResolveSyncConflictAsync(
        string repoPath,
        string conflictId,
        CoreSyncConflictResolutionRequest resolution,
        CancellationToken cancellationToken = default)
    {
        cancellationToken.ThrowIfCancellationRequested();
        CoreSyncConflictResolveReport report = CallWithResult(
            (ref RustCallStatus status) => native.ResolveSyncConflict(
                LowerString(repoPath),
                LowerString(conflictId),
                LowerSyncConflictResolutionRequest(resolution),
                ref status),
            ReadSyncConflictResolveReport);
        return Task.FromResult(report);
    }

    private static CoreSyncConflictResolutionPreviewReport ReadSyncConflictResolutionPreviewReport(
        UniFfiReader reader)
    {
        return new CoreSyncConflictResolutionPreviewReport(
            reader.ReadString(),
            ReadSyncConflictResolutionStrategy(reader),
            ReadSyncConflictResolutionStrategy(reader),
            ReadSyncConflictStatus(reader),
            ReadSyncConflictVersionImpacts(reader),
            ReadStrings(reader),
            ReadStrings(reader),
            ReadStrings(reader),
            ReadSyncConflictInt64s(reader),
            ReadOptionalString(reader),
            reader.ReadString(),
            reader.ReadBool(),
            reader.ReadBool(),
            reader.ReadBool(),
            reader.ReadBool(),
            reader.ReadBool(),
            ReadOptionalString(reader),
            ReadOptionalString(reader),
            ReadOptionalSyncConflictReplacePlan(reader));
    }

    private static CoreSyncConflictResolveReport ReadSyncConflictResolveReport(UniFfiReader reader)
    {
        return new CoreSyncConflictResolveReport(
            reader.ReadString(),
            ReadSyncConflictResolutionStrategy(reader),
            ReadSyncConflictStatus(reader),
            ReadStrings(reader),
            ReadStrings(reader),
            ReadStrings(reader),
            ReadSyncConflictInt64s(reader),
            reader.ReadString(),
            ReadOptionalString(reader),
            ReadOptionalInt64(reader));
    }

    private static IReadOnlyList<CoreSyncConflictVersionImpact> ReadSyncConflictVersionImpacts(
        UniFfiReader reader)
    {
        int count = reader.ReadInt32();
        List<CoreSyncConflictVersionImpact> impacts = new(count);
        for (int index = 0; index < count; index += 1)
        {
            impacts.Add(new CoreSyncConflictVersionImpact(
                reader.ReadString(),
                ReadOptionalInt64(reader),
                ReadSyncConflictFileRole(reader),
                reader.ReadBool(),
                reader.ReadBool(),
                reader.ReadBool(),
                reader.ReadBool(),
                ReadOptionalString(reader),
                ReadOptionalString(reader)));
        }

        return impacts;
    }

    private static IReadOnlyList<long> ReadSyncConflictInt64s(UniFfiReader reader)
    {
        int count = reader.ReadInt32();
        List<long> values = new(count);
        for (int index = 0; index < count; index += 1)
        {
            values.Add(reader.ReadInt64());
        }

        return values;
    }

    private static CoreSyncConflictReplacePlan? ReadOptionalSyncConflictReplacePlan(UniFfiReader reader)
    {
        return reader.ReadByte() switch
        {
            0 => null,
            1 => new CoreSyncConflictReplacePlan(
                reader.ReadString(),
                reader.ReadString(),
                ReadOptionalString(reader),
                ReadOptionalString(reader),
                ReadOptionalInt64(reader),
                ReadOptionalString(reader),
                reader.ReadString(),
                reader.ReadString(),
                reader.ReadString()),
            _ => throw BindingConfigError("AreaMatrix Core returned an invalid replace plan tag.")
        };
    }

    private RustBuffer LowerSyncConflictResolutionStrategy(string resolution)
    {
        List<byte> bytes = [];
        WriteSyncConflictResolutionStrategy(bytes, resolution);
        return RustBufferFromBytes(bytes.ToArray());
    }

    private RustBuffer LowerSyncConflictResolutionRequest(CoreSyncConflictResolutionRequest request)
    {
        List<byte> bytes = [];
        WriteSyncConflictResolutionStrategy(bytes, request.Strategy);
        WriteString(bytes, request.PreviewToken);
        WriteBool(bytes, request.ReplaceConfirmed);
        WriteOptionalString(bytes, request.ReplaceConfirmationId);
        return RustBufferFromBytes(bytes.ToArray());
    }

    private static void WriteSyncConflictResolutionStrategy(List<byte> bytes, string resolution)
    {
        WriteEnum(bytes, resolution switch
        {
            "KeepBoth" => 1,
            "UseExisting" => 2,
            "UseIncoming" => 3,
            _ => throw BindingConfigError($"Unsupported sync conflict resolution `{resolution}`.")
        });
    }

    private static string ReadSyncConflictResolutionStrategy(UniFfiReader reader)
    {
        return reader.ReadInt32() switch
        {
            1 => "KeepBoth",
            2 => "UseExisting",
            3 => "UseIncoming",
            _ => throw BindingConfigError("AreaMatrix Core returned an unknown sync conflict resolution.")
        };
    }
}
