using System;
using System.Collections.Generic;
using System.Globalization;
using System.IO;
using System.Linq;
using AreaMatrix.Features.Library;
using AreaMatrix.Features.Onboarding;

namespace AreaMatrix.Features.Conflicts;

public enum SyncConflictEntryStatus
{
    NeedsReview,
    Resolved
}

public enum SyncConflictEntryType
{
    SameNameDifferentContent,
    ConcurrentModification,
    MetadataMismatch,
    MissingVersion,
    Unknown
}

public enum SyncConflictEntrySeverity
{
    Low,
    Medium,
    High
}

public enum SyncConflictEntryFileRole
{
    Existing,
    Incoming,
    ConflictCopy,
    Missing,
    Unknown
}

public enum SyncConflictResolutionStrategy
{
    KeepBoth,
    UseExisting,
    UseIncoming
}

public enum SyncConflictEntryErrorKind
{
    Db,
    Io,
    Conflict,
    Config,
    PermissionDenied,
    Unavailable
}

public sealed record SyncConflictEntryAffectedFile(
    string Path,
    long? FileId,
    SyncConflictEntryFileRole Role,
    long? SizeBytes,
    long? ModifiedAt,
    string? HashSha256,
    string? SourcePlatform);

public sealed record SyncConflictEntryConflict(
    string ConflictId,
    SyncConflictEntryType ConflictType,
    SyncConflictEntrySeverity Severity,
    SyncConflictEntryStatus Status,
    string PrimaryPath,
    IReadOnlyList<SyncConflictEntryAffectedFile> AffectedFiles,
    long VersionCount,
    string? SourceProvider,
    long? DetectedAt,
    string? Summary)
{
    public string? NormalizedConflictId => string.IsNullOrWhiteSpace(ConflictId) ? null : ConflictId.Trim();

    public string DisplayName
    {
        get
        {
            string name = Path.GetFileName(PrimaryPath);
            return string.IsNullOrWhiteSpace(name) ? PrimaryPath : name;
        }
    }

    public string TypeText => ConflictType switch
    {
        SyncConflictEntryType.SameNameDifferentContent => "Same name, different content",
        SyncConflictEntryType.ConcurrentModification => "Concurrent modification",
        SyncConflictEntryType.MetadataMismatch => "Metadata mismatch",
        SyncConflictEntryType.MissingVersion => "Missing version",
        _ => "Unknown"
    };

    public string SourceText => string.IsNullOrWhiteSpace(SourceProvider) ? "Unknown source" : SourceProvider;

    public string DetectedText => DetectedAt is > 0 and long value
        ? DateTimeOffset.FromUnixTimeSeconds(value).ToLocalTime().ToString("g", CultureInfo.CurrentCulture)
        : "Unknown";

    public string SummaryText => string.IsNullOrWhiteSpace(Summary)
        ? "Conflict details need review."
        : Summary;

    public string StatusBadge => ConflictType switch
    {
        SyncConflictEntryType.MissingVersion => "Missing version",
        SyncConflictEntryType.Unknown => "Unknown source",
        _ => "Conflict"
    };

    public bool Matches(DesktopFileEntry file)
    {
        return PrimaryPath == file.Path
            || AffectedFiles.Any(affected => affected.Path == file.Path || affected.FileId == file.Id);
    }
}

public sealed record SyncConflictEntryReviewRoute(
    string RepoPath,
    string ConflictId,
    string PrimaryPath);

public sealed record SyncConflictVersionImpact(
    string Path,
    long? FileId,
    SyncConflictEntryFileRole Role,
    bool WillKeep,
    bool WillBeCanonical,
    bool WillRemainUserVisible,
    bool WillMoveToTrash,
    string? RecoveryTarget,
    string? Reason);

public sealed record SyncConflictReplacePlan(
    string OldPath,
    string NewPath,
    string? OldHashSha256,
    string? NewHashSha256,
    long? AffectedFileId,
    string? BackupTarget,
    string DatabaseUpdate,
    string ChangeLogAction,
    string RecoveryNote)
{
    public string AffectedRecordText => AffectedFileId?.ToString(CultureInfo.InvariantCulture) ?? "Unknown";

    public string OldHashText => string.IsNullOrWhiteSpace(OldHashSha256) ? "Unknown" : OldHashSha256;

    public string NewHashText => string.IsNullOrWhiteSpace(NewHashSha256) ? "Unknown" : NewHashSha256;

    public string BackupTargetText => string.IsNullOrWhiteSpace(BackupTarget)
        ? "Trash / Recycle Bin or Core safety backup required"
        : BackupTarget;

    public bool HasCoreSafetyBackup
    {
        get
        {
            if (string.IsNullOrWhiteSpace(BackupTarget))
            {
                return false;
            }

            string backupTarget = BackupTarget.Trim();
            return !backupTarget.Contains("unavailable", StringComparison.OrdinalIgnoreCase)
                && !backupTarget.Contains("trash", StringComparison.OrdinalIgnoreCase)
                && !backupTarget.Contains("recycle bin", StringComparison.OrdinalIgnoreCase);
        }
    }
}

public sealed record SyncConflictResolutionPreviewReport(
    string ConflictId,
    SyncConflictResolutionStrategy Resolution,
    SyncConflictResolutionStrategy DefaultResolution,
    SyncConflictEntryStatus StatusAfter,
    IReadOnlyList<SyncConflictVersionImpact> VersionImpacts,
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
    SyncConflictReplacePlan? ReplacePlan)
{
    public string? NormalizedPreviewToken => string.IsNullOrWhiteSpace(PreviewToken) ? null : PreviewToken.Trim();

    public bool HasRecoverableOldVersion =>
        !TrashRequired || TrashAvailable || ReplacePlan?.HasCoreSafetyBackup == true;

    public bool BlocksOnlyForReplaceConfirmation =>
        !CanApply
        && RequiresReplaceConfirmation
        && (BlockedReason?.Contains("confirmation", StringComparison.OrdinalIgnoreCase) ?? false);
}

public sealed record SyncConflictResolutionRequest(
    SyncConflictResolutionStrategy Strategy,
    string PreviewToken,
    bool ReplaceConfirmed,
    string? ReplaceConfirmationId);

public sealed record SyncConflictResolveReport(
    string ConflictId,
    SyncConflictResolutionStrategy Resolution,
    SyncConflictEntryStatus Status,
    IReadOnlyList<string> KeptPaths,
    IReadOnlyList<string> RetainedPaths,
    IReadOnlyList<string> TrashedPaths,
    IReadOnlyList<long> AffectedFileIds,
    string ChangeLogAction,
    string? UndoToken,
    long? ResolvedAt);

public sealed record SyncConflictReplaceConfirmation(
    string ConflictId,
    string PreviewToken,
    string ConfirmationId,
    SyncConflictReplacePlan ReplacePlan);

public sealed record SyncConflictEntryError(
    SyncConflictEntryErrorKind Kind,
    string Message,
    string SuggestedAction)
{
    public static SyncConflictEntryError FromException(Exception exception)
    {
        return exception switch
        {
            SyncConflictEntryCoreException coreException => FromKind(coreException.Kind, coreException.Message),
            WindowsRepositoryCoreException coreException => FromWindowsCore(coreException),
            _ => FromKind(SyncConflictEntryErrorKind.Unavailable, exception.Message)
        };
    }

    private static SyncConflictEntryError FromWindowsCore(WindowsRepositoryCoreException exception)
    {
        SyncConflictEntryErrorKind kind = exception.Kind switch
        {
            WindowsRepositoryErrorKind.Db => SyncConflictEntryErrorKind.Db,
            WindowsRepositoryErrorKind.Conflict => SyncConflictEntryErrorKind.Conflict,
            WindowsRepositoryErrorKind.PermissionDenied => SyncConflictEntryErrorKind.PermissionDenied,
            WindowsRepositoryErrorKind.DiskUnavailable => SyncConflictEntryErrorKind.Io,
            WindowsRepositoryErrorKind.Config => SyncConflictEntryErrorKind.Config,
            _ => SyncConflictEntryErrorKind.Unavailable
        };
        return FromKind(kind, exception.Message);
    }

    private static SyncConflictEntryError FromKind(SyncConflictEntryErrorKind kind, string message)
    {
        return kind switch
        {
            SyncConflictEntryErrorKind.Db => new(
                kind,
                "Could not load review items",
                "Try again after the repository database is available."),
            SyncConflictEntryErrorKind.Io => new(
                kind,
                "Could not read conflict metadata",
                "Check repository permissions and try again."),
            SyncConflictEntryErrorKind.Conflict => new(
                kind,
                "Conflict records changed before they could be loaded",
                "Try again to refresh the review list."),
            SyncConflictEntryErrorKind.PermissionDenied => new(
                kind,
                "AreaMatrix cannot read conflict metadata",
                "Review repository permissions and try again."),
            _ => new(
                kind,
                string.IsNullOrWhiteSpace(message) ? "Could not load review items" : message,
                "Try again.")
        };
    }
}
