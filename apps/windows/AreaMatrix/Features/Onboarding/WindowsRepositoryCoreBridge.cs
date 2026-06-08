using System;
using System.Collections.Generic;
using System.Linq;
using System.Threading;
using System.Threading.Tasks;

namespace AreaMatrix.Features.Onboarding;

public interface IWindowsRepositoryCoreBridge
{
    Task<WindowsRepositoryValidation> ValidateRepoPathAsync(
        string repoPath,
        CancellationToken cancellationToken = default);

    Task<WindowsCloudStorageState> DetectCloudStorageStateAsync(
        string repoPath,
        CancellationToken cancellationToken = default);

    Task<WindowsCloudStorageState> AcknowledgeOneDriveRiskNoticeAsync(
        string repoPath,
        CancellationToken cancellationToken = default);

    Task<WindowsRepositoryConfig> LoadConfigAsync(
        string repoPath,
        CancellationToken cancellationToken = default);

    Task InitializeEmptyRepositoryAsync(
        string repoPath,
        CancellationToken cancellationToken = default);

    Task AdoptExistingRepositoryAsync(
        string repoPath,
        CancellationToken cancellationToken = default);
}

public interface IAreaMatrixWindowsCoreClient
{
    Task<CoreRepoPathValidation> ValidateRepoPathAsync(
        string repoPath,
        CancellationToken cancellationToken = default);

    Task<CoreCloudStorageState> DetectCloudStorageStateAsync(
        string repoPath,
        CancellationToken cancellationToken = default);

    Task<CoreCloudStorageState> AcknowledgeOneDriveRiskNoticeAsync(
        string repoPath,
        CancellationToken cancellationToken = default);

    Task<CoreRepoConfig> LoadConfigAsync(
        string repoPath,
        CancellationToken cancellationToken = default);

    Task InitRepoAsync(
        string repoPath,
        CoreRepoInitOptions options,
        CancellationToken cancellationToken = default);
}

public sealed class WindowsRepositoryCoreBridge : IWindowsRepositoryCoreBridge
{
    private readonly IAreaMatrixWindowsCoreClient coreClient;

    public WindowsRepositoryCoreBridge(IAreaMatrixWindowsCoreClient coreClient)
    {
        this.coreClient = coreClient;
    }

    public async Task<WindowsRepositoryValidation> ValidateRepoPathAsync(
        string repoPath,
        CancellationToken cancellationToken = default)
    {
        CoreRepoPathValidation validation = await coreClient
            .ValidateRepoPathAsync(repoPath, cancellationToken)
            .ConfigureAwait(false);

        return validation.ToWindowsValidation();
    }

    public async Task<WindowsRepositoryConfig> LoadConfigAsync(
        string repoPath,
        CancellationToken cancellationToken = default)
    {
        CoreRepoConfig config = await coreClient
            .LoadConfigAsync(repoPath, cancellationToken)
            .ConfigureAwait(false);

        return new WindowsRepositoryConfig(
            config.RepoPath,
            config.DefaultMode,
            config.Locale);
    }

    public async Task<WindowsCloudStorageState> DetectCloudStorageStateAsync(
        string repoPath,
        CancellationToken cancellationToken = default)
    {
        CoreCloudStorageState state = await coreClient
            .DetectCloudStorageStateAsync(repoPath, cancellationToken)
            .ConfigureAwait(false);

        return state.ToWindowsCloudStorageState();
    }

    public async Task<WindowsCloudStorageState> AcknowledgeOneDriveRiskNoticeAsync(
        string repoPath,
        CancellationToken cancellationToken = default)
    {
        CoreCloudStorageState state = await coreClient
            .AcknowledgeOneDriveRiskNoticeAsync(repoPath, cancellationToken)
            .ConfigureAwait(false);

        return state.ToWindowsCloudStorageState();
    }

    public Task InitializeEmptyRepositoryAsync(
        string repoPath,
        CancellationToken cancellationToken = default)
    {
        return coreClient.InitRepoAsync(
            repoPath,
            CoreRepoInitOptions.CreateEmptyGeneratedOnly,
            cancellationToken);
    }

    public Task AdoptExistingRepositoryAsync(
        string repoPath,
        CancellationToken cancellationToken = default)
    {
        return coreClient.InitRepoAsync(
            repoPath,
            CoreRepoInitOptions.AdoptExistingGeneratedOnly,
            cancellationToken);
    }
}

public enum WindowsRepositoryInitMode
{
    CreateEmpty,
    AdoptExisting
}

public enum WindowsRepositoryPathIssue
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

public enum WindowsPlatformPathKind
{
    Local,
    ICloudDrive,
    OneDrive,
    NetworkShare,
    Unknown
}

public enum WindowsRepositoryRouteKind
{
    None,
    MainWindow,
    OneDriveNotice,
    WatcherStatus,
    ImportFlow,
    RepositoryInitConfirm,
    RepositoryAdoptConfirm
}

public enum WindowsRepositoryErrorKind
{
    Db,
    InvalidPath,
    SelectedFile,
    PermissionDenied,
    InvalidRepository,
    FileNotFound,
    DiskUnavailable,
    OneDrivePathDetected,
    Config,
    DuplicateFile,
    Conflict,
    Unavailable
}

public sealed record WindowsRepositoryValidation(
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
    WindowsPlatformPathKind PlatformPathKind,
    bool IsCaseSensitivePath,
    bool HasUnfinishedScanSession,
    WindowsRepositoryInitMode? RecommendedMode,
    IReadOnlyList<WindowsRepositoryPathIssue> Issues)
{
    public bool HasIssue(WindowsRepositoryPathIssue issue)
    {
        return Issues.Contains(issue);
    }
}

public sealed record WindowsRepositoryConfig(
    string RepoPath,
    string DefaultMode,
    string Locale);

public sealed record CoreRepoPathValidation(
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
    string PlatformPathKind,
    bool IsCaseSensitivePath,
    bool HasUnfinishedScanSession,
    string? RecommendedMode,
    IReadOnlyList<string> Issues)
{
    public WindowsRepositoryValidation ToWindowsValidation()
    {
        return new WindowsRepositoryValidation(
            RepoPath,
            Exists,
            IsDirectory,
            IsReadable,
            IsWritable,
            IsEmpty,
            IsInitialized,
            IsInsideAreaMatrix,
            IsICloudPath,
            IsOneDrivePath,
            ParsePlatformPathKind(PlatformPathKind),
            IsCaseSensitivePath,
            HasUnfinishedScanSession,
            ParseInitMode(RecommendedMode),
            Issues.Select(ParseIssue).ToArray());
    }

    private static WindowsRepositoryInitMode? ParseInitMode(string? value)
    {
        return value switch
        {
            "CreateEmpty" => WindowsRepositoryInitMode.CreateEmpty,
            "AdoptExisting" => WindowsRepositoryInitMode.AdoptExisting,
            _ => null
        };
    }

    private static WindowsPlatformPathKind ParsePlatformPathKind(string value)
    {
        return value switch
        {
            "Local" => WindowsPlatformPathKind.Local,
            "ICloudDrive" => WindowsPlatformPathKind.ICloudDrive,
            "OneDrive" => WindowsPlatformPathKind.OneDrive,
            "NetworkShare" => WindowsPlatformPathKind.NetworkShare,
            _ => WindowsPlatformPathKind.Unknown
        };
    }

    private static WindowsRepositoryPathIssue ParseIssue(string value)
    {
        return value switch
        {
            "MissingPath" => WindowsRepositoryPathIssue.MissingPath,
            "NotDirectory" => WindowsRepositoryPathIssue.NotDirectory,
            "NotReadable" => WindowsRepositoryPathIssue.NotReadable,
            "NotWritable" => WindowsRepositoryPathIssue.NotWritable,
            "NonEmptyDirectory" => WindowsRepositoryPathIssue.NonEmptyDirectory,
            "AlreadyInitialized" => WindowsRepositoryPathIssue.AlreadyInitialized,
            "InsideAreaMatrix" => WindowsRepositoryPathIssue.InsideAreaMatrix,
            "ICloudPath" => WindowsRepositoryPathIssue.ICloudPath,
            "OneDrivePath" => WindowsRepositoryPathIssue.OneDrivePath,
            "WindowsReservedName" => WindowsRepositoryPathIssue.WindowsReservedName,
            "WindowsCaseInsensitive" => WindowsRepositoryPathIssue.WindowsCaseInsensitive,
            "UnfinishedScanSession" => WindowsRepositoryPathIssue.UnfinishedScanSession,
            _ => throw new WindowsRepositoryCoreException(
                WindowsRepositoryErrorKind.Config,
                $"Unknown repository path issue `{value}`.")
        };
    }
}

public sealed record CoreCloudStorageState(
    string RepoPath,
    string ProviderKind,
    string Risk,
    string PlaceholderState,
    string PermissionState,
    string StatusSummary,
    IReadOnlyList<string> RiskReasons,
    string RecommendedAction,
    bool RequiresNoticeAcknowledgement,
    bool NoticeAcknowledged,
    bool CanRetry,
    bool RequiresReconnect)
{
    public WindowsCloudStorageState ToWindowsCloudStorageState()
    {
        return new WindowsCloudStorageState(
            RepoPath,
            ParseProviderKind(ProviderKind),
            ParseRiskLevel(Risk),
            ParsePlaceholderState(PlaceholderState),
            ParsePermissionState(PermissionState),
            StatusSummary,
            RiskReasons,
            ParseRecommendedAction(RecommendedAction),
            RequiresNoticeAcknowledgement,
            NoticeAcknowledged,
            CanRetry,
            RequiresReconnect);
    }

    private static WindowsCloudStorageProviderKind ParseProviderKind(string value)
    {
        return value switch
        {
            "Local" => WindowsCloudStorageProviderKind.Local,
            "ICloudDrive" => WindowsCloudStorageProviderKind.ICloudDrive,
            "OneDrive" => WindowsCloudStorageProviderKind.OneDrive,
            "Unknown" => WindowsCloudStorageProviderKind.Unknown,
            _ => throw new WindowsRepositoryCoreException(
                WindowsRepositoryErrorKind.Config,
                $"Unknown cloud storage provider `{value}`.")
        };
    }

    private static WindowsCloudStorageRiskLevel ParseRiskLevel(string value)
    {
        return value switch
        {
            "NoRisk" => WindowsCloudStorageRiskLevel.NoRisk,
            "Low" => WindowsCloudStorageRiskLevel.Low,
            "Medium" => WindowsCloudStorageRiskLevel.Medium,
            "High" => WindowsCloudStorageRiskLevel.High,
            "Unknown" => WindowsCloudStorageRiskLevel.Unknown,
            _ => throw new WindowsRepositoryCoreException(
                WindowsRepositoryErrorKind.Config,
                $"Unknown cloud storage risk `{value}`.")
        };
    }

    private static WindowsCloudPlaceholderState ParsePlaceholderState(string value)
    {
        return value switch
        {
            "NotPlaceholder" => WindowsCloudPlaceholderState.NotPlaceholder,
            "Placeholder" => WindowsCloudPlaceholderState.Placeholder,
            "Unknown" => WindowsCloudPlaceholderState.Unknown,
            _ => throw new WindowsRepositoryCoreException(
                WindowsRepositoryErrorKind.Config,
                $"Unknown cloud placeholder state `{value}`.")
        };
    }

    private static WindowsCloudPermissionState ParsePermissionState(string value)
    {
        return value switch
        {
            "Accessible" => WindowsCloudPermissionState.Accessible,
            "PermissionDenied" => WindowsCloudPermissionState.PermissionDenied,
            "AccessExpired" => WindowsCloudPermissionState.AccessExpired,
            "Unknown" => WindowsCloudPermissionState.Unknown,
            _ => throw new WindowsRepositoryCoreException(
                WindowsRepositoryErrorKind.Config,
                $"Unknown cloud permission state `{value}`.")
        };
    }

    private static WindowsCloudStorageRecommendedAction ParseRecommendedAction(string value)
    {
        return value switch
        {
            "None" => WindowsCloudStorageRecommendedAction.None,
            "AcknowledgeNotice" => WindowsCloudStorageRecommendedAction.AcknowledgeNotice,
            "RetryStatusCheck" => WindowsCloudStorageRecommendedAction.RetryStatusCheck,
            "ReconnectFolder" => WindowsCloudStorageRecommendedAction.ReconnectFolder,
            "ChooseLocalFolder" => WindowsCloudStorageRecommendedAction.ChooseLocalFolder,
            _ => throw new WindowsRepositoryCoreException(
                WindowsRepositoryErrorKind.Config,
                $"Unknown cloud storage action `{value}`.")
        };
    }
}

public sealed record CoreRepoConfig(
    string RepoPath,
    string DefaultMode,
    string Locale);

public sealed record CoreRepoInitOptions(
    string Mode,
    bool CreateDefaultCategories,
    string OverviewOutput)
{
    public static CoreRepoInitOptions CreateEmptyGeneratedOnly { get; } = new(
        "CreateEmpty",
        CreateDefaultCategories: true,
        "GeneratedOnly");

    public static CoreRepoInitOptions AdoptExistingGeneratedOnly { get; } = new(
        "AdoptExisting",
        CreateDefaultCategories: false,
        "GeneratedOnly");
}

public sealed record WindowsRepositoryRoute(
    WindowsRepositoryRouteKind Kind,
    string RepoPath,
    WindowsRepositoryValidation? Validation,
    WindowsRepositoryConfig? Config,
    WindowsCloudStorageState? CloudStorageState = null)
{
    public static WindowsRepositoryRoute None { get; } = new(
        WindowsRepositoryRouteKind.None,
        string.Empty,
        null,
        null,
        null);
}

public sealed record WindowsRepositoryError(
    WindowsRepositoryErrorKind Kind,
    string Message,
    string? Path = null);

public sealed class WindowsRepositoryCoreException : Exception
{
    public WindowsRepositoryCoreException(
        WindowsRepositoryErrorKind kind,
        string message,
        string? path = null)
        : base(message)
    {
        Kind = kind;
        Path = path;
    }

    public WindowsRepositoryErrorKind Kind { get; }

    public string? Path { get; }
}
