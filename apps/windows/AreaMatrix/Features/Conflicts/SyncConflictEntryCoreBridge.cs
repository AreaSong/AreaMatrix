using System;
using System.Collections.Generic;
using System.Linq;
using System.Threading;
using System.Threading.Tasks;

namespace AreaMatrix.Features.Conflicts;

public interface ISyncConflictEntryCoreBridge
{
    Task<IReadOnlyList<SyncConflictEntryConflict>> DetectSyncConflictsAsync(
        string repoPath,
        CancellationToken cancellationToken = default);

    Task<SyncConflictResolutionPreviewReport> PreviewSyncConflictResolutionAsync(
        string repoPath,
        string conflictId,
        SyncConflictResolutionStrategy resolution,
        CancellationToken cancellationToken = default);

    Task<SyncConflictResolveReport> ResolveSyncConflictAsync(
        string repoPath,
        string conflictId,
        SyncConflictResolutionRequest resolution,
        CancellationToken cancellationToken = default);
}

public interface IAreaMatrixSyncConflictDetectCoreClient
{
    Task<IReadOnlyList<CoreSyncConflictEntry>> DetectSyncConflictsAsync(
        string repoPath,
        CancellationToken cancellationToken = default);
}

public interface IAreaMatrixSyncConflictResolveCoreClient
{
    Task<CoreSyncConflictResolutionPreviewReport> PreviewSyncConflictResolutionAsync(
        string repoPath,
        string conflictId,
        string resolution,
        CancellationToken cancellationToken = default);

    Task<CoreSyncConflictResolveReport> ResolveSyncConflictAsync(
        string repoPath,
        string conflictId,
        CoreSyncConflictResolutionRequest resolution,
        CancellationToken cancellationToken = default);
}

public interface IAreaMatrixSyncConflictCoreClient :
    IAreaMatrixSyncConflictDetectCoreClient,
    IAreaMatrixSyncConflictResolveCoreClient
{
}

public sealed class SyncConflictEntryCoreBridge : ISyncConflictEntryCoreBridge
{
    private readonly IAreaMatrixSyncConflictDetectCoreClient detectClient;
    private readonly IAreaMatrixSyncConflictResolveCoreClient resolveClient;

    public SyncConflictEntryCoreBridge(
        IAreaMatrixSyncConflictDetectCoreClient detectClient,
        IAreaMatrixSyncConflictResolveCoreClient resolveClient)
    {
        this.detectClient = detectClient;
        this.resolveClient = resolveClient;
    }

    public SyncConflictEntryCoreBridge(IAreaMatrixSyncConflictCoreClient coreClient)
        : this(coreClient, coreClient)
    {
    }

    public async Task<IReadOnlyList<SyncConflictEntryConflict>> DetectSyncConflictsAsync(
        string repoPath,
        CancellationToken cancellationToken = default)
    {
        IReadOnlyList<CoreSyncConflictEntry> conflicts = await detectClient
            .DetectSyncConflictsAsync(repoPath, cancellationToken)
            .ConfigureAwait(false);
        return conflicts.Select(conflict => conflict.ToEntryConflict()).ToArray();
    }

    public async Task<SyncConflictResolutionPreviewReport> PreviewSyncConflictResolutionAsync(
        string repoPath,
        string conflictId,
        SyncConflictResolutionStrategy resolution,
        CancellationToken cancellationToken = default)
    {
        CoreSyncConflictResolutionPreviewReport preview = await resolveClient
            .PreviewSyncConflictResolutionAsync(repoPath, conflictId, resolution.ToCoreValue(), cancellationToken)
            .ConfigureAwait(false);
        return preview.ToPreviewReport();
    }

    public async Task<SyncConflictResolveReport> ResolveSyncConflictAsync(
        string repoPath,
        string conflictId,
        SyncConflictResolutionRequest resolution,
        CancellationToken cancellationToken = default)
    {
        CoreSyncConflictResolveReport report = await resolveClient
            .ResolveSyncConflictAsync(repoPath, conflictId, resolution.ToCoreRequest(), cancellationToken)
            .ConfigureAwait(false);
        return report.ToResolveReport();
    }
}

public sealed record CoreSyncConflictAffectedFile(
    string Path,
    long? FileId,
    string Role,
    long? SizeBytes,
    long? ModifiedAt,
    string? HashSha256,
    string? SourcePlatform);

public sealed record CoreSyncConflictEntry(
    string ConflictId,
    string ConflictType,
    string Severity,
    string Status,
    string PrimaryPath,
    IReadOnlyList<CoreSyncConflictAffectedFile> AffectedFiles,
    long VersionCount,
    string? SourceProvider,
    long? DetectedAt,
    string? Summary);

public sealed record CoreSyncConflictVersionImpact(
    string Path,
    long? FileId,
    string Role,
    bool WillKeep,
    bool WillBeCanonical,
    bool WillRemainUserVisible,
    bool WillMoveToTrash,
    string? RecoveryTarget,
    string? Reason);

public sealed record CoreSyncConflictReplacePlan(
    string OldPath,
    string NewPath,
    string? OldHashSha256,
    string? NewHashSha256,
    long? AffectedFileId,
    string? BackupTarget,
    string DatabaseUpdate,
    string ChangeLogAction,
    string RecoveryNote);

public sealed record CoreSyncConflictResolutionPreviewReport(
    string ConflictId,
    string Resolution,
    string DefaultResolution,
    string StatusAfter,
    IReadOnlyList<CoreSyncConflictVersionImpact> VersionImpacts,
    IReadOnlyList<string> KeptPaths,
    IReadOnlyList<string> RetainedPaths,
    IReadOnlyList<string> PlannedTrashPaths,
    IReadOnlyList<long> AffectedFileIds,
    string? CanonicalPath,
    string ChangeLogAction,
    bool Destructive,
    bool RequiresReplaceConfirmation,
    bool TrashRequired,
    bool TrashAvailable,
    bool CanApply,
    string? BlockedReason,
    string? PreviewToken,
    CoreSyncConflictReplacePlan? ReplacePlan);

public sealed record CoreSyncConflictResolutionRequest(
    string Strategy,
    string PreviewToken,
    bool ReplaceConfirmed,
    string? ReplaceConfirmationId);

public sealed record CoreSyncConflictResolveReport(
    string ConflictId,
    string Resolution,
    string Status,
    IReadOnlyList<string> KeptPaths,
    IReadOnlyList<string> RetainedPaths,
    IReadOnlyList<string> TrashedPaths,
    IReadOnlyList<long> AffectedFileIds,
    string ChangeLogAction,
    string? UndoToken,
    long? ResolvedAt);

internal static class SyncConflictEntryCoreMapping
{
    public static SyncConflictEntryConflict ToEntryConflict(this CoreSyncConflictEntry conflict)
    {
        return new SyncConflictEntryConflict(
            conflict.ConflictId,
            ParseType(conflict.ConflictType),
            ParseSeverity(conflict.Severity),
            ParseStatus(conflict.Status),
            conflict.PrimaryPath,
            conflict.AffectedFiles.Select(ToAffectedFile).ToArray(),
            conflict.VersionCount,
            conflict.SourceProvider,
            conflict.DetectedAt,
            conflict.Summary);
    }

    private static SyncConflictEntryAffectedFile ToAffectedFile(CoreSyncConflictAffectedFile affectedFile)
    {
        return new SyncConflictEntryAffectedFile(
            affectedFile.Path,
            affectedFile.FileId,
            ParseRole(affectedFile.Role),
            affectedFile.SizeBytes,
            affectedFile.ModifiedAt,
            affectedFile.HashSha256,
            affectedFile.SourcePlatform);
    }

    public static SyncConflictResolutionPreviewReport ToPreviewReport(
        this CoreSyncConflictResolutionPreviewReport preview)
    {
        return new SyncConflictResolutionPreviewReport(
            preview.ConflictId,
            ParseResolution(preview.Resolution),
            ParseResolution(preview.DefaultResolution),
            ParseStatus(preview.StatusAfter),
            preview.VersionImpacts.Select(ToVersionImpact).ToArray(),
            preview.KeptPaths,
            preview.RetainedPaths,
            preview.PlannedTrashPaths,
            preview.AffectedFileIds,
            preview.CanonicalPath,
            preview.ChangeLogAction,
            preview.Destructive,
            preview.RequiresReplaceConfirmation,
            preview.TrashRequired,
            preview.TrashAvailable,
            preview.CanApply,
            preview.BlockedReason,
            preview.PreviewToken,
            preview.ReplacePlan?.ToReplacePlan());
    }

    public static SyncConflictResolveReport ToResolveReport(this CoreSyncConflictResolveReport report)
    {
        return new SyncConflictResolveReport(
            report.ConflictId,
            ParseResolution(report.Resolution),
            ParseStatus(report.Status),
            report.KeptPaths,
            report.RetainedPaths,
            report.TrashedPaths,
            report.AffectedFileIds,
            report.ChangeLogAction,
            report.UndoToken,
            report.ResolvedAt);
    }

    public static CoreSyncConflictResolutionRequest ToCoreRequest(this SyncConflictResolutionRequest request)
    {
        return new CoreSyncConflictResolutionRequest(
            request.Strategy.ToCoreValue(),
            request.PreviewToken,
            request.ReplaceConfirmed,
            request.ReplaceConfirmationId);
    }

    public static string ToCoreValue(this SyncConflictResolutionStrategy resolution)
    {
        return resolution switch
        {
            SyncConflictResolutionStrategy.KeepBoth => "KeepBoth",
            SyncConflictResolutionStrategy.UseExisting => "UseExisting",
            SyncConflictResolutionStrategy.UseIncoming => "UseIncoming",
            _ => throw ConfigError($"Unsupported sync conflict resolution `{resolution}`.")
        };
    }

    private static SyncConflictVersionImpact ToVersionImpact(CoreSyncConflictVersionImpact impact)
    {
        return new SyncConflictVersionImpact(
            impact.Path,
            impact.FileId,
            ParseRole(impact.Role),
            impact.WillKeep,
            impact.WillBeCanonical,
            impact.WillRemainUserVisible,
            impact.WillMoveToTrash,
            impact.RecoveryTarget,
            impact.Reason);
    }

    private static SyncConflictReplacePlan ToReplacePlan(this CoreSyncConflictReplacePlan plan)
    {
        return new SyncConflictReplacePlan(
            plan.OldPath,
            plan.NewPath,
            plan.OldHashSha256,
            plan.NewHashSha256,
            plan.AffectedFileId,
            plan.BackupTarget,
            plan.DatabaseUpdate,
            plan.ChangeLogAction,
            plan.RecoveryNote);
    }

    private static SyncConflictEntryStatus ParseStatus(string value)
    {
        return value switch
        {
            "NeedsReview" => SyncConflictEntryStatus.NeedsReview,
            "Resolved" => SyncConflictEntryStatus.Resolved,
            _ => throw ConfigError($"Unsupported sync conflict status `{value}`.")
        };
    }

    private static SyncConflictResolutionStrategy ParseResolution(string value)
    {
        return value switch
        {
            "KeepBoth" => SyncConflictResolutionStrategy.KeepBoth,
            "UseExisting" => SyncConflictResolutionStrategy.UseExisting,
            "UseIncoming" => SyncConflictResolutionStrategy.UseIncoming,
            _ => throw ConfigError($"Unsupported sync conflict resolution `{value}`.")
        };
    }

    private static SyncConflictEntryType ParseType(string value)
    {
        return value switch
        {
            "SameNameDifferentContent" => SyncConflictEntryType.SameNameDifferentContent,
            "ConcurrentModification" => SyncConflictEntryType.ConcurrentModification,
            "MetadataMismatch" => SyncConflictEntryType.MetadataMismatch,
            "MissingVersion" => SyncConflictEntryType.MissingVersion,
            "Unknown" => SyncConflictEntryType.Unknown,
            _ => throw ConfigError($"Unsupported sync conflict type `{value}`.")
        };
    }

    private static SyncConflictEntrySeverity ParseSeverity(string value)
    {
        return value switch
        {
            "Low" => SyncConflictEntrySeverity.Low,
            "Medium" => SyncConflictEntrySeverity.Medium,
            "High" => SyncConflictEntrySeverity.High,
            _ => throw ConfigError($"Unsupported sync conflict severity `{value}`.")
        };
    }

    private static SyncConflictEntryFileRole ParseRole(string value)
    {
        return value switch
        {
            "Existing" => SyncConflictEntryFileRole.Existing,
            "Incoming" => SyncConflictEntryFileRole.Incoming,
            "ConflictCopy" => SyncConflictEntryFileRole.ConflictCopy,
            "Missing" => SyncConflictEntryFileRole.Missing,
            "Unknown" => SyncConflictEntryFileRole.Unknown,
            _ => throw ConfigError($"Unsupported sync conflict file role `{value}`.")
        };
    }

    private static SyncConflictEntryCoreException ConfigError(string message)
    {
        return new SyncConflictEntryCoreException(SyncConflictEntryErrorKind.Config, message);
    }
}

public sealed class SyncConflictEntryCoreException : Exception
{
    public SyncConflictEntryCoreException(SyncConflictEntryErrorKind kind, string message)
        : base(message)
    {
        Kind = kind;
    }

    public SyncConflictEntryErrorKind Kind { get; }
}
