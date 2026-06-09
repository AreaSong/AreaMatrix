using System.Globalization;
using System.IO;
using AreaMatrix.Linux.Features.Onboarding;

namespace AreaMatrix.Linux.Features.Recovery;

public sealed record MissingFileRecoveryRoute(
    string RepoPath,
    long FileId);

public enum MissingFileReason
{
    PathMissing,
    PermissionDenied,
    CloudPlaceholder,
    ExternalVolumeDisconnected,
    Unknown
}

public enum MissingFileRecoveryStatus
{
    Missing,
    Present,
    Relinked,
    HashMismatch,
    RecordRemoved,
    Blocked
}

public enum MissingFileRecoveryErrorKind
{
    Db,
    FileNotFound,
    PermissionDenied,
    Config,
    Unavailable
}

public sealed record MissingFileRecoveryState(
    long FileId,
    string RelativePath,
    string? LastKnownPath,
    long? LastSeenAt,
    MissingFileReason Reason,
    string? ExpectedHashSha256,
    bool CanLocate,
    bool CanTryAgain,
    bool CanRemoveRecord,
    bool RemoveRecordRequiresConfirmation,
    bool CanRunRescan,
    string? RescanDisabledReason)
{
    public string FileText => string.IsNullOrWhiteSpace(RelativePath)
        ? "No last known path is available."
        : RelativePath;

    public string DisplayName
    {
        get
        {
            string name = Path.GetFileName(RelativePath);
            return string.IsNullOrWhiteSpace(name) ? FileText : name;
        }
    }

    public string LastKnownLocationText => string.IsNullOrWhiteSpace(LastKnownPath)
        ? "No last known path is available."
        : LastKnownPath;

    public string LastSeenText => LastSeenAt is > 0 and long timestamp
        ? DateTimeOffset.FromUnixTimeSeconds(timestamp).ToLocalTime().ToString("g", CultureInfo.CurrentCulture)
        : "Unknown";

    public string ReasonText => Reason switch
    {
        MissingFileReason.PathMissing => "Path missing",
        MissingFileReason.PermissionDenied => "Permission denied",
        MissingFileReason.CloudPlaceholder => "Cloud placeholder",
        MissingFileReason.ExternalVolumeDisconnected => "External volume disconnected",
        _ => "Unknown"
    };
}

public sealed record MissingFileRelinkRequest(
    long FileId,
    string NewPath,
    bool Confirmed);

public sealed record MissingFileRemoveRecordRequest(
    long FileId,
    bool Confirmed);

public sealed record MissingFileRecoveryReport(
    long FileId,
    MissingFileRecoveryStatus Status,
    string? PreviousPath,
    string? CurrentPath,
    bool HashMatched,
    bool RecordRemoved,
    bool FileDeleted,
    string? ChangeLogAction,
    string? Message)
{
    public string DisplayMessage
    {
        get
        {
            if (!string.IsNullOrWhiteSpace(Message))
            {
                return Message;
            }

            return Status switch
            {
                MissingFileRecoveryStatus.Relinked => "File relinked.",
                MissingFileRecoveryStatus.HashMismatch => "Selected file does not match the missing record.",
                MissingFileRecoveryStatus.RecordRemoved => "AreaMatrix record removed. No user file was deleted.",
                MissingFileRecoveryStatus.Present => "File is available again.",
                MissingFileRecoveryStatus.Blocked => "Recovery is blocked.",
                _ => "File is still missing."
            };
        }
    }
}

public sealed record MissingFileRecoveryError(
    MissingFileRecoveryErrorKind Kind,
    string Message,
    string SuggestedAction)
{
    public static MissingFileRecoveryError FromException(Exception exception)
    {
        return exception switch
        {
            MissingFileRecoveryCoreException coreException => FromKind(coreException.Kind, coreException.Message),
            LinuxRepositoryCoreException coreException => FromLinuxCore(coreException),
            _ => FromKind(MissingFileRecoveryErrorKind.Unavailable, exception.Message)
        };
    }

    private static MissingFileRecoveryError FromLinuxCore(LinuxRepositoryCoreException exception)
    {
        MissingFileRecoveryErrorKind kind = exception.Kind switch
        {
            LinuxRepositoryErrorKind.Db => MissingFileRecoveryErrorKind.Db,
            LinuxRepositoryErrorKind.FileNotFound => MissingFileRecoveryErrorKind.FileNotFound,
            LinuxRepositoryErrorKind.PermissionDenied => MissingFileRecoveryErrorKind.PermissionDenied,
            LinuxRepositoryErrorKind.Config => MissingFileRecoveryErrorKind.Config,
            _ => MissingFileRecoveryErrorKind.Unavailable
        };
        return FromKind(kind, exception.Message);
    }

    private static MissingFileRecoveryError FromKind(MissingFileRecoveryErrorKind kind, string message)
    {
        return kind switch
        {
            MissingFileRecoveryErrorKind.Db => new(
                kind,
                "Repository metadata could not be updated.",
                "Try again after the repository database is available."),
            MissingFileRecoveryErrorKind.FileNotFound => new(
                kind,
                "This missing file record is no longer available.",
                "Return to the file list and refresh."),
            MissingFileRecoveryErrorKind.PermissionDenied => new(
                kind,
                "AreaMatrix does not have permission to complete this recovery action.",
                "Check file and repository permissions, then try again."),
            _ => new(
                kind,
                string.IsNullOrWhiteSpace(message) ? "Missing file recovery is unavailable." : message,
                "Try again.")
        };
    }
}

public sealed record CoreMissingFileState(
    long FileId,
    string RelativePath,
    string? LastKnownPath,
    long? LastSeenAt,
    string Reason,
    string? ExpectedHashSha256,
    bool CanLocate,
    bool CanTryAgain,
    bool CanRemoveRecord,
    bool RemoveRecordRequiresConfirmation,
    bool CanRunRescan,
    string? RescanDisabledReason);

public sealed record CoreMissingFileRelinkRequest(
    long FileId,
    string NewPath,
    bool Confirmed);

public sealed record CoreMissingFileRemoveRecordRequest(
    long FileId,
    bool Confirmed);

public sealed record CoreMissingFileRecoveryReport(
    long FileId,
    string Status,
    string? PreviousPath,
    string? CurrentPath,
    bool HashMatched,
    bool RecordRemoved,
    bool FileDeleted,
    string? ChangeLogAction,
    string? Message);
