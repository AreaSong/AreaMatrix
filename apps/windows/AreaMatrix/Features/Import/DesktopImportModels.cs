using AreaMatrix.Features.Library;
using AreaMatrix.Features.Onboarding;

namespace AreaMatrix.Features.Import;

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
    Unreadable
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
    DesktopImportPreviewStatus Status)
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
                DesktopImportPreviewStatus.Unreadable => "Unreadable",
                _ => "Ready"
            };
        }
    }
}

public sealed record DesktopImportMovePreflight(
    bool CanMove,
    IReadOnlyList<string> Reasons)
{
    public static DesktopImportMovePreflight NotEvaluated { get; } = new(false, []);

    public string StatusText
    {
        get
        {
            if (CanMove)
            {
                return "Move preflight passed: sources are readable, source locations allow removal, repository is writable, and staging is available.";
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
    DesktopFileEntry Entry,
    DesktopImportSourceRemovalStatus SourceRemovalStatus,
    string? SourceRemovalFailure)
{
    public string SummaryText
    {
        get
        {
            return SourceRemovalStatus == DesktopImportSourceRemovalStatus.Retained
                ? "Imported, original retained"
                : "Imported";
        }
    }

    public string DetailText
    {
        get
        {
            return SourceRemovalStatus switch
            {
                DesktopImportSourceRemovalStatus.Removed => "Original removed after repository import completed.",
                DesktopImportSourceRemovalStatus.Retained =>
                    SourceRemovalFailure ?? "The original file was retained after import.",
                _ => "Original file was not removed."
            };
        }
    }
}

public sealed record DesktopImportError(
    DesktopImportErrorKind Kind,
    string Message,
    string? Path = null)
{
    public WindowsRepositoryError ToRepositoryError()
    {
        return new WindowsRepositoryError(RepositoryErrorKind, Message, Path);
    }

    public static DesktopImportError FromException(Exception exception)
    {
        if (exception is DesktopImportCoreException importException)
        {
            return importException.ToImportError();
        }

        if (exception is WindowsRepositoryCoreException coreException)
        {
            return new DesktopImportError(
                KindFromRepositoryError(coreException.Kind),
                MessageFromRepositoryError(coreException),
                coreException.Path);
        }

        return new DesktopImportError(DesktopImportErrorKind.Unavailable, exception.Message);
    }

    private WindowsRepositoryErrorKind RepositoryErrorKind
    {
        get
        {
            return Kind switch
            {
                DesktopImportErrorKind.InvalidPath => WindowsRepositoryErrorKind.InvalidPath,
                DesktopImportErrorKind.PermissionDenied => WindowsRepositoryErrorKind.PermissionDenied,
                DesktopImportErrorKind.DuplicateFile => WindowsRepositoryErrorKind.DuplicateFile,
                DesktopImportErrorKind.Conflict => WindowsRepositoryErrorKind.Conflict,
                DesktopImportErrorKind.Db => WindowsRepositoryErrorKind.Db,
                DesktopImportErrorKind.Config => WindowsRepositoryErrorKind.Config,
                _ => WindowsRepositoryErrorKind.Unavailable
            };
        }
    }

    private static DesktopImportErrorKind KindFromRepositoryError(WindowsRepositoryErrorKind kind)
    {
        return kind switch
        {
            WindowsRepositoryErrorKind.Db => DesktopImportErrorKind.Db,
            WindowsRepositoryErrorKind.InvalidPath => DesktopImportErrorKind.InvalidPath,
            WindowsRepositoryErrorKind.PermissionDenied => DesktopImportErrorKind.PermissionDenied,
            WindowsRepositoryErrorKind.DuplicateFile => DesktopImportErrorKind.DuplicateFile,
            WindowsRepositoryErrorKind.Conflict => DesktopImportErrorKind.Conflict,
            WindowsRepositoryErrorKind.Config => DesktopImportErrorKind.Config,
            _ => DesktopImportErrorKind.Unavailable
        };
    }

    private static string MessageFromRepositoryError(WindowsRepositoryCoreException exception)
    {
        return exception.Kind switch
        {
            WindowsRepositoryErrorKind.Db => "Repository database is locked or unavailable.",
            WindowsRepositoryErrorKind.InvalidPath => "The selected import path is invalid.",
            WindowsRepositoryErrorKind.PermissionDenied => "AreaMatrix cannot read or write one of the selected paths.",
            WindowsRepositoryErrorKind.FileNotFound => "The selected source file is no longer available.",
            WindowsRepositoryErrorKind.DuplicateFile => "Duplicate content already exists in the repository.",
            WindowsRepositoryErrorKind.Conflict => "Resolve the import conflict before continuing.",
            WindowsRepositoryErrorKind.Config => "Repository configuration cannot be opened.",
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
