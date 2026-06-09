namespace AreaMatrix.Linux.Features.Conflicts;

public interface ISyncConflictEntryCoreBridge
{
    Task<IReadOnlyList<SyncConflictEntryConflict>> DetectSyncConflictsAsync(
        string repoPath,
        CancellationToken cancellationToken = default);
}

public interface IAreaMatrixLinuxSyncConflictDetectCoreClient
{
    Task<IReadOnlyList<CoreSyncConflictEntry>> DetectSyncConflictsAsync(
        string repoPath,
        CancellationToken cancellationToken = default);
}

public sealed class SyncConflictEntryCoreBridge : ISyncConflictEntryCoreBridge
{
    private readonly IAreaMatrixLinuxSyncConflictDetectCoreClient coreClient;

    public SyncConflictEntryCoreBridge(IAreaMatrixLinuxSyncConflictDetectCoreClient coreClient)
    {
        this.coreClient = coreClient;
    }

    public async Task<IReadOnlyList<SyncConflictEntryConflict>> DetectSyncConflictsAsync(
        string repoPath,
        CancellationToken cancellationToken = default)
    {
        IReadOnlyList<CoreSyncConflictEntry> conflicts = await coreClient
            .DetectSyncConflictsAsync(repoPath, cancellationToken)
            .ConfigureAwait(false);
        return conflicts.Select(conflict => conflict.ToEntryConflict()).ToArray();
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

    private static SyncConflictEntryStatus ParseStatus(string value)
    {
        return value switch
        {
            "NeedsReview" => SyncConflictEntryStatus.NeedsReview,
            "Resolved" => SyncConflictEntryStatus.Resolved,
            _ => throw ConfigError($"Unsupported sync conflict status `{value}`.")
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
