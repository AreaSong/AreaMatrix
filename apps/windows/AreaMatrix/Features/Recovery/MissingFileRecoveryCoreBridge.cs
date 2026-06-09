using System;
using System.Threading;
using System.Threading.Tasks;

namespace AreaMatrix.Features.Recovery;

public interface IMissingFileRecoveryCoreBridge
{
    Task<MissingFileRecoveryState> GetMissingFileStateAsync(
        string repoPath,
        long fileId,
        CancellationToken cancellationToken = default);

    Task<MissingFileRecoveryReport> RelinkMissingFileAsync(
        string repoPath,
        MissingFileRelinkRequest request,
        CancellationToken cancellationToken = default);

    Task<MissingFileRecoveryReport> RemoveMissingFileRecordAsync(
        string repoPath,
        MissingFileRemoveRecordRequest request,
        CancellationToken cancellationToken = default);
}

public interface IAreaMatrixMissingFileRecoveryCoreClient
{
    Task<CoreMissingFileState> GetMissingFileStateAsync(
        string repoPath,
        long fileId,
        CancellationToken cancellationToken = default);

    Task<CoreMissingFileRecoveryReport> RelinkMissingFileAsync(
        string repoPath,
        CoreMissingFileRelinkRequest request,
        CancellationToken cancellationToken = default);

    Task<CoreMissingFileRecoveryReport> RemoveMissingFileRecordAsync(
        string repoPath,
        CoreMissingFileRemoveRecordRequest request,
        CancellationToken cancellationToken = default);
}

public sealed class MissingFileRecoveryCoreBridge : IMissingFileRecoveryCoreBridge
{
    private readonly IAreaMatrixMissingFileRecoveryCoreClient coreClient;

    public MissingFileRecoveryCoreBridge(IAreaMatrixMissingFileRecoveryCoreClient coreClient)
    {
        this.coreClient = coreClient;
    }

    public async Task<MissingFileRecoveryState> GetMissingFileStateAsync(
        string repoPath,
        long fileId,
        CancellationToken cancellationToken = default)
    {
        CoreMissingFileState state = await coreClient
            .GetMissingFileStateAsync(repoPath, fileId, cancellationToken)
            .ConfigureAwait(false);
        return state.ToRecoveryState();
    }

    public async Task<MissingFileRecoveryReport> RelinkMissingFileAsync(
        string repoPath,
        MissingFileRelinkRequest request,
        CancellationToken cancellationToken = default)
    {
        CoreMissingFileRecoveryReport report = await coreClient
            .RelinkMissingFileAsync(
                repoPath,
                new CoreMissingFileRelinkRequest(request.FileId, request.NewPath, request.Confirmed),
                cancellationToken)
            .ConfigureAwait(false);
        return report.ToRecoveryReport();
    }

    public async Task<MissingFileRecoveryReport> RemoveMissingFileRecordAsync(
        string repoPath,
        MissingFileRemoveRecordRequest request,
        CancellationToken cancellationToken = default)
    {
        CoreMissingFileRecoveryReport report = await coreClient
            .RemoveMissingFileRecordAsync(
                repoPath,
                new CoreMissingFileRemoveRecordRequest(request.FileId, request.Confirmed),
                cancellationToken)
            .ConfigureAwait(false);
        return report.ToRecoveryReport();
    }
}

internal static class MissingFileRecoveryCoreMapping
{
    public static MissingFileRecoveryState ToRecoveryState(this CoreMissingFileState state)
    {
        return new MissingFileRecoveryState(
            state.FileId,
            state.RelativePath,
            state.LastKnownPath,
            state.LastSeenAt,
            ParseReason(state.Reason),
            state.ExpectedHashSha256,
            state.CanLocate,
            state.CanTryAgain,
            state.CanRemoveRecord,
            state.RemoveRecordRequiresConfirmation,
            state.CanRunRescan,
            state.RescanDisabledReason);
    }

    public static MissingFileRecoveryReport ToRecoveryReport(this CoreMissingFileRecoveryReport report)
    {
        return new MissingFileRecoveryReport(
            report.FileId,
            ParseStatus(report.Status),
            report.PreviousPath,
            report.CurrentPath,
            report.HashMatched,
            report.RecordRemoved,
            report.FileDeleted,
            report.ChangeLogAction,
            report.Message);
    }

    private static MissingFileReason ParseReason(string value)
    {
        return value switch
        {
            "PathMissing" => MissingFileReason.PathMissing,
            "PermissionDenied" => MissingFileReason.PermissionDenied,
            "CloudPlaceholder" => MissingFileReason.CloudPlaceholder,
            "ExternalVolumeDisconnected" => MissingFileReason.ExternalVolumeDisconnected,
            "Unknown" => MissingFileReason.Unknown,
            _ => throw ConfigError($"Unsupported missing-file reason `{value}`.")
        };
    }

    private static MissingFileRecoveryStatus ParseStatus(string value)
    {
        return value switch
        {
            "Missing" => MissingFileRecoveryStatus.Missing,
            "Present" => MissingFileRecoveryStatus.Present,
            "Relinked" => MissingFileRecoveryStatus.Relinked,
            "HashMismatch" => MissingFileRecoveryStatus.HashMismatch,
            "RecordRemoved" => MissingFileRecoveryStatus.RecordRemoved,
            "Blocked" => MissingFileRecoveryStatus.Blocked,
            _ => throw ConfigError($"Unsupported missing-file recovery status `{value}`.")
        };
    }

    private static MissingFileRecoveryCoreException ConfigError(string message)
    {
        return new MissingFileRecoveryCoreException(MissingFileRecoveryErrorKind.Config, message);
    }
}

public sealed class MissingFileRecoveryCoreException : Exception
{
    public MissingFileRecoveryCoreException(MissingFileRecoveryErrorKind kind, string message)
        : base(message)
    {
        Kind = kind;
    }

    public MissingFileRecoveryErrorKind Kind { get; }
}
