using AreaMatrix.Linux.Features.Recovery;

namespace AreaMatrix.Linux.Core;

public sealed partial class AreaMatrixNativeCoreClient
{
    public Task<CoreMissingFileState> GetMissingFileStateAsync(
        string repoPath,
        long fileId,
        CancellationToken cancellationToken = default)
    {
        cancellationToken.ThrowIfCancellationRequested();
        CoreMissingFileState state = CallWithResult(
            (ref RustCallStatus status) => native.GetMissingFileState(LowerString(repoPath), fileId, ref status),
            ReadMissingFileState);
        return Task.FromResult(state);
    }

    public Task<CoreMissingFileRecoveryReport> RelinkMissingFileAsync(
        string repoPath,
        CoreMissingFileRelinkRequest request,
        CancellationToken cancellationToken = default)
    {
        cancellationToken.ThrowIfCancellationRequested();
        CoreMissingFileRecoveryReport report = CallWithResult(
            (ref RustCallStatus status) => native.RelinkMissingFile(
                LowerString(repoPath),
                LowerMissingFileRelinkRequest(request),
                ref status),
            ReadMissingFileRecoveryReport);
        return Task.FromResult(report);
    }

    public Task<CoreMissingFileRecoveryReport> RemoveMissingFileRecordAsync(
        string repoPath,
        CoreMissingFileRemoveRecordRequest request,
        CancellationToken cancellationToken = default)
    {
        cancellationToken.ThrowIfCancellationRequested();
        CoreMissingFileRecoveryReport report = CallWithResult(
            (ref RustCallStatus status) => native.RemoveMissingFileRecord(
                LowerString(repoPath),
                LowerMissingFileRemoveRecordRequest(request),
                ref status),
            ReadMissingFileRecoveryReport);
        return Task.FromResult(report);
    }

    private static CoreMissingFileState ReadMissingFileState(UniFfiReader reader)
    {
        return new CoreMissingFileState(
            reader.ReadInt64(),
            reader.ReadString(),
            ReadOptionalString(reader),
            ReadOptionalInt64(reader),
            ReadMissingFileReason(reader),
            ReadOptionalString(reader),
            reader.ReadBool(),
            reader.ReadBool(),
            reader.ReadBool(),
            reader.ReadBool(),
            reader.ReadBool(),
            ReadOptionalString(reader));
    }

    private static CoreMissingFileRecoveryReport ReadMissingFileRecoveryReport(UniFfiReader reader)
    {
        return new CoreMissingFileRecoveryReport(
            reader.ReadInt64(),
            ReadMissingFileRecoveryStatus(reader),
            ReadOptionalString(reader),
            ReadOptionalString(reader),
            reader.ReadBool(),
            reader.ReadBool(),
            reader.ReadBool(),
            ReadOptionalString(reader),
            ReadOptionalString(reader));
    }

    private RustBuffer LowerMissingFileRelinkRequest(CoreMissingFileRelinkRequest request)
    {
        List<byte> bytes = [];
        WriteInt64(bytes, request.FileId);
        WriteString(bytes, request.NewPath);
        WriteBool(bytes, request.Confirmed);
        return RustBufferFromBytes(bytes.ToArray());
    }

    private RustBuffer LowerMissingFileRemoveRecordRequest(CoreMissingFileRemoveRecordRequest request)
    {
        List<byte> bytes = [];
        WriteInt64(bytes, request.FileId);
        WriteBool(bytes, request.Confirmed);
        return RustBufferFromBytes(bytes.ToArray());
    }

    private static string ReadMissingFileReason(UniFfiReader reader)
    {
        return reader.ReadInt32() switch
        {
            1 => "PathMissing",
            2 => "PermissionDenied",
            3 => "CloudPlaceholder",
            4 => "ExternalVolumeDisconnected",
            5 => "Unknown",
            _ => throw BindingConfigError("AreaMatrix Core returned an unknown missing-file reason.")
        };
    }

    private static string ReadMissingFileRecoveryStatus(UniFfiReader reader)
    {
        return reader.ReadInt32() switch
        {
            1 => "Missing",
            2 => "Present",
            3 => "Relinked",
            4 => "HashMismatch",
            5 => "RecordRemoved",
            6 => "Blocked",
            _ => throw BindingConfigError("AreaMatrix Core returned an unknown missing-file recovery status.")
        };
    }
}
