using AreaMatrix.Linux.Features.Library;
using AreaMatrix.Linux.Features.Onboarding;

namespace AreaMatrix.Linux.Features.Import;

public enum DesktopImportMode
{
    Copy,
    Move
}

public enum DesktopImportDestination
{
    AutoClassify,
    SelectedDirectory,
    Category
}

public enum DesktopImportDuplicateStrategy
{
    Skip,
    KeepBoth,
    Ask
}

public enum DesktopImportSourceRemovalStatus
{
    NotRequested,
    Removed,
    Retained
}

public enum DesktopImportPreviewStatus
{
    Ready,
    Duplicate,
    NameConflict,
    Unreadable,
    PermissionDenied
}

public enum DesktopImportStep
{
    Preparing,
    Staging,
    Hashing,
    WritingFiles,
    UpdatingDatabase,
    RemovingOriginals,
    Done
}

public enum DesktopImportErrorKind
{
    InvalidPath,
    PermissionDenied,
    DuplicateFile,
    Conflict,
    Db,
    Unavailable,
    Config
}

public sealed record DesktopImportSource(
    string SourcePath,
    string? SourceRootPath = null,
    string? RelativeDirectory = null)
{
    public bool IsFromFolder => !string.IsNullOrWhiteSpace(SourceRootPath);
}

public sealed record DesktopImportRequest(
    DesktopImportMode Mode,
    DesktopImportDestination Destination,
    string? TargetDirectory,
    string? OverrideCategory,
    string? OverrideFilename,
    DesktopImportDuplicateStrategy DuplicateStrategy,
    bool MoveConfirmed)
{
    public static DesktopImportRequest Default { get; } = new(
        DesktopImportMode.Copy,
        DesktopImportDestination.AutoClassify,
        null,
        null,
        null,
        DesktopImportDuplicateStrategy.Skip,
        false);
}

public sealed record DesktopImportPreviewItem(
    string SourcePath,
    string FileName,
    string TypeText,
    string SizeText,
    string SuggestedCategory,
    string SuggestedName,
    DesktopImportPreviewStatus Status,
    string? ExistingPath = null,
    string? TargetPath = null,
    string? BlockedReason = null)
{
    public bool IsImportable => Status is DesktopImportPreviewStatus.Ready or DesktopImportPreviewStatus.NameConflict;

    public string StatusText
    {
        get
        {
            return Status switch
            {
                DesktopImportPreviewStatus.Ready => "Ready",
                DesktopImportPreviewStatus.Duplicate => "Duplicate",
                DesktopImportPreviewStatus.NameConflict => "Name conflict",
                DesktopImportPreviewStatus.PermissionDenied => "Permission denied",
                DesktopImportPreviewStatus.Unreadable => "Unreadable",
                _ => "Ready"
            };
        }
    }
}

public sealed record DesktopImportMovePreflight(
    bool CanMove,
    IReadOnlyList<string> Reasons,
    string MountText)
{
    public static DesktopImportMovePreflight NotEvaluated { get; } = new(false, [], "unknown");

    public string StatusText
    {
        get
        {
            if (CanMove)
            {
                return "Move preflight passed: sources are readable, source folders allow removal, repository is writable, staging is available, and mount state is recorded.";
            }

            if (Reasons.Count == 0)
            {
                return "Prepare a preview before using Move.";
            }

            return "Move preflight failed. Use Copy instead or fix: " + string.Join("; ", Reasons);
        }
    }
}

public sealed record DesktopImportResult(
    DesktopFileEntry? Entry,
    string SourcePath,
    DesktopImportSourceRemovalStatus SourceRemovalStatus,
    string? SourceRemovalFailure,
    DesktopImportError? Failure = null)
{
    public bool IsFailure => Failure is not null;

    public bool HasImportedFile => Entry is { Id: > 0 } && !IsFailure;

    public bool CanShowOriginal => SourceRemovalStatus == DesktopImportSourceRemovalStatus.Retained
        && !string.IsNullOrWhiteSpace(SourcePath);

    public bool CanShowImportedFile => HasImportedFile;

    public bool CanRetry => IsFailure && !string.IsNullOrWhiteSpace(SourcePath);

    public string SummaryText
    {
        get
        {
            if (Failure is not null)
            {
                return "Failed";
            }

            return SourceRemovalStatus == DesktopImportSourceRemovalStatus.Retained
                ? "Imported, original retained"
                : "Imported";
        }
    }

    public string DetailText
    {
        get
        {
            if (Failure is not null)
            {
                return Failure.Message;
            }

            return SourceRemovalStatus switch
            {
                DesktopImportSourceRemovalStatus.Removed => "Original removed after repository import completed.",
                DesktopImportSourceRemovalStatus.Retained =>
                    SourceRemovalFailure ?? "The original file was retained after import.",
                _ => "Original file was not removed."
            };
        }
    }

    public static DesktopImportResult Failed(DesktopImportPreviewItem item, DesktopImportError error)
    {
        return new DesktopImportResult(
            null,
            item.SourcePath,
            DesktopImportSourceRemovalStatus.NotRequested,
            null,
            error);
    }
}

public sealed record LinuxImportCloseRequest(IReadOnlyList<long> ImportedFileIds)
{
    public static LinuxImportCloseRequest None { get; } = new([]);

    public bool ShouldRefreshMainWindow => ImportedFileIds.Count > 0;
}

public sealed record DesktopImportError(
    DesktopImportErrorKind Kind,
    string Message,
    string? Path = null)
{
    public LinuxRepositoryError ToRepositoryError()
    {
        return new LinuxRepositoryError(RepositoryErrorKind, Message, Path);
    }

    public static DesktopImportError FromException(Exception exception)
    {
        if (exception is DesktopImportCoreException importException)
        {
            return importException.ToImportError();
        }

        if (exception is LinuxRepositoryCoreException coreException)
        {
            return new DesktopImportError(
                KindFromRepositoryError(coreException.Kind),
                MessageFromRepositoryError(coreException),
                coreException.Path);
        }

        return new DesktopImportError(DesktopImportErrorKind.Unavailable, exception.Message);
    }

    private LinuxRepositoryErrorKind RepositoryErrorKind
    {
        get
        {
            return Kind switch
            {
                DesktopImportErrorKind.InvalidPath => LinuxRepositoryErrorKind.InvalidPath,
                DesktopImportErrorKind.PermissionDenied => LinuxRepositoryErrorKind.PermissionDenied,
                DesktopImportErrorKind.DuplicateFile => LinuxRepositoryErrorKind.SelectedFile,
                DesktopImportErrorKind.Conflict => LinuxRepositoryErrorKind.SelectedFile,
                DesktopImportErrorKind.Db => LinuxRepositoryErrorKind.Db,
                DesktopImportErrorKind.Config => LinuxRepositoryErrorKind.Config,
                _ => LinuxRepositoryErrorKind.Unavailable
            };
        }
    }

    private static DesktopImportErrorKind KindFromRepositoryError(LinuxRepositoryErrorKind kind)
    {
        return kind switch
        {
            LinuxRepositoryErrorKind.Db => DesktopImportErrorKind.Db,
            LinuxRepositoryErrorKind.InvalidPath => DesktopImportErrorKind.InvalidPath,
            LinuxRepositoryErrorKind.PermissionDenied => DesktopImportErrorKind.PermissionDenied,
            LinuxRepositoryErrorKind.Config => DesktopImportErrorKind.Config,
            _ => DesktopImportErrorKind.Unavailable
        };
    }

    private static string MessageFromRepositoryError(LinuxRepositoryCoreException exception)
    {
        return exception.Kind switch
        {
            LinuxRepositoryErrorKind.Db => "Database is busy. Try again.",
            LinuxRepositoryErrorKind.InvalidPath => "The selected import path is invalid.",
            LinuxRepositoryErrorKind.PermissionDenied => "AreaMatrix cannot read or write one of the selected paths.",
            LinuxRepositoryErrorKind.FileNotFound => "The selected source file is no longer available.",
            LinuxRepositoryErrorKind.Config => "Repository configuration cannot be opened.",
            _ => exception.Message
        };
    }
}

public sealed class DesktopImportCoreException : Exception
{
    public DesktopImportCoreException(
        DesktopImportErrorKind kind,
        string message,
        string? path = null)
        : base(message)
    {
        Kind = kind;
        Path = path;
    }

    public DesktopImportErrorKind Kind { get; }

    public string? Path { get; }

    public DesktopImportError ToImportError()
    {
        return new DesktopImportError(Kind, Message, Path);
    }
}
