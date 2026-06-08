namespace AreaMatrix.Linux.Features.Onboarding;

public enum LinuxRepositoryInitMode
{
    CreateEmpty,
    AdoptExisting
}

public enum LinuxRepositoryPathIssue
{
    MissingPath,
    NotDirectory,
    NotReadable,
    NotWritable,
    NonEmptyDirectory,
    AlreadyInitialized,
    InsideAreaMatrix,
    ICloudPath,
    OneDrivePath,
    WindowsReservedName,
    WindowsCaseInsensitive,
    UnfinishedScanSession
}

public enum LinuxPlatformPathKind
{
    Local,
    ExternalDrive,
    ICloudDrive,
    OneDrive,
    NetworkShare,
    Unknown
}

public enum LinuxRepositoryRouteKind
{
    None,
    ChooseRepository,
    MainWindow,
    LocalFolderNotice,
    RepositoryInitConfirm,
    RepositoryAdoptConfirm
}

public enum LinuxRepositoryErrorKind
{
    Db,
    Config,
    InvalidPath,
    SelectedFile,
    PermissionDenied,
    InvalidRepository,
    RepoNotInitialized,
    FileNotFound,
    DiskUnavailable,
    ICloudPlaceholder,
    Unavailable
}

public enum LinuxPlatformId
{
    Macos,
    Ios,
    Windows,
    Linux,
    Unknown
}

public enum LinuxPlatformCapabilityStatus
{
    Available,
    Limited,
    NotAvailable,
    Unknown
}

public sealed record LinuxRepositoryValidation(
    string RepoPath,
    bool Exists,
    bool IsDirectory,
    bool IsReadable,
    bool IsWritable,
    bool IsEmpty,
    bool IsInitialized,
    bool IsInsideAreaMatrix,
    bool IsICloudPath,
    bool IsOneDrivePath,
    LinuxPlatformPathKind PlatformPathKind,
    bool IsCaseSensitivePath,
    bool HasUnfinishedScanSession,
    LinuxRepositoryInitMode? RecommendedMode,
    IReadOnlyList<LinuxRepositoryPathIssue> Issues)
{
    public bool HasIssue(LinuxRepositoryPathIssue issue)
    {
        return Issues.Contains(issue);
    }
}

public sealed record LinuxPlatformCapabilitySupport(
    LinuxPlatformCapabilityStatus Status,
    bool UiEnabled,
    bool RequiresPermission,
    string? Reason);

public sealed record LinuxPlatformCapabilities(
    LinuxPlatformId Platform,
    string AppVersion,
    LinuxPlatformCapabilitySupport Watcher,
    LinuxPlatformCapabilitySupport Trash,
    LinuxPlatformCapabilitySupport ShareExtension,
    LinuxPlatformCapabilitySupport CloudPlaceholder,
    LinuxPlatformCapabilitySupport SecurityBookmark);

public sealed record LinuxRepositoryRoute(
    LinuxRepositoryRouteKind Kind,
    string RepoPath,
    LinuxRepositoryValidation? Validation)
{
    public static LinuxRepositoryRoute None { get; } = new(
        LinuxRepositoryRouteKind.None,
        string.Empty,
        null);
}

public sealed record LinuxRepositoryError(
    LinuxRepositoryErrorKind Kind,
    string Message,
    string? Path = null);

public sealed class LinuxRepositoryCoreException : Exception
{
    public LinuxRepositoryCoreException(
        LinuxRepositoryErrorKind kind,
        string message,
        string? path = null)
        : base(message)
    {
        Kind = kind;
        Path = path;
    }

    public LinuxRepositoryErrorKind Kind { get; }

    public string? Path { get; }
}
