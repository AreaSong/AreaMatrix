namespace AreaMatrix.Linux.Features.Onboarding;

public interface ILinuxRepositoryCoreBridge
{
    Task<LinuxRepositoryValidation> ValidateRepoPathAsync(
        string repoPath,
        CancellationToken cancellationToken = default);

    Task InitializeEmptyRepositoryAsync(
        string repoPath,
        CancellationToken cancellationToken = default);

    Task AdoptExistingRepositoryAsync(
        string repoPath,
        CancellationToken cancellationToken = default);
}

public interface ILinuxPlatformCapabilitiesCoreBridge
{
    Task<LinuxPlatformCapabilities> GetPlatformCapabilitiesAsync(
        LinuxPlatformId platform,
        string appVersion,
        CancellationToken cancellationToken = default);
}

public interface IAreaMatrixLinuxCoreClient
{
    Task<CoreRepoPathValidation> ValidateRepoPathAsync(
        string repoPath,
        CancellationToken cancellationToken = default);

    Task InitRepoAsync(
        string repoPath,
        CoreRepoInitOptions options,
        CancellationToken cancellationToken = default);

    Task<CorePlatformCapabilities> GetPlatformCapabilitiesAsync(
        string platform,
        string appVersion,
        CancellationToken cancellationToken = default);
}

public sealed class LinuxRepositoryCoreBridge :
    ILinuxRepositoryCoreBridge,
    ILinuxPlatformCapabilitiesCoreBridge
{
    private readonly IAreaMatrixLinuxCoreClient coreClient;

    public LinuxRepositoryCoreBridge(IAreaMatrixLinuxCoreClient coreClient)
    {
        this.coreClient = coreClient;
    }

    public async Task<LinuxRepositoryValidation> ValidateRepoPathAsync(
        string repoPath,
        CancellationToken cancellationToken = default)
    {
        CoreRepoPathValidation validation = await coreClient
            .ValidateRepoPathAsync(repoPath, cancellationToken)
            .ConfigureAwait(false);

        return validation.ToLinuxValidation();
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

    public async Task<LinuxPlatformCapabilities> GetPlatformCapabilitiesAsync(
        LinuxPlatformId platform,
        string appVersion,
        CancellationToken cancellationToken = default)
    {
        CorePlatformCapabilities capabilities = await coreClient
            .GetPlatformCapabilitiesAsync(platform.ToCorePlatformId(), appVersion, cancellationToken)
            .ConfigureAwait(false);

        return capabilities.ToLinuxCapabilities();
    }
}

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
    public LinuxRepositoryValidation ToLinuxValidation()
    {
        LinuxPlatformPathKind platformPathKind = LinuxPlatformPathClassifier.Classify(
            RepoPath,
            ParsePlatformPathKind(PlatformPathKind));
        return new LinuxRepositoryValidation(
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
            platformPathKind,
            IsCaseSensitivePath,
            HasUnfinishedScanSession,
            ParseInitMode(RecommendedMode),
            Issues.Select(ParseIssue).ToArray());
    }

    private static LinuxRepositoryInitMode? ParseInitMode(string? value)
    {
        return value switch
        {
            "CreateEmpty" => LinuxRepositoryInitMode.CreateEmpty,
            "AdoptExisting" => LinuxRepositoryInitMode.AdoptExisting,
            _ => null
        };
    }

    private static LinuxPlatformPathKind ParsePlatformPathKind(string value)
    {
        return value switch
        {
            "Local" => LinuxPlatformPathKind.Local,
            "ExternalDrive" => LinuxPlatformPathKind.ExternalDrive,
            "ICloudDrive" => LinuxPlatformPathKind.ICloudDrive,
            "OneDrive" => LinuxPlatformPathKind.OneDrive,
            "NetworkShare" => LinuxPlatformPathKind.NetworkShare,
            _ => LinuxPlatformPathKind.Unknown
        };
    }

    private static LinuxRepositoryPathIssue ParseIssue(string value)
    {
        return value switch
        {
            "MissingPath" => LinuxRepositoryPathIssue.MissingPath,
            "NotDirectory" => LinuxRepositoryPathIssue.NotDirectory,
            "NotReadable" => LinuxRepositoryPathIssue.NotReadable,
            "NotWritable" => LinuxRepositoryPathIssue.NotWritable,
            "NonEmptyDirectory" => LinuxRepositoryPathIssue.NonEmptyDirectory,
            "AlreadyInitialized" => LinuxRepositoryPathIssue.AlreadyInitialized,
            "InsideAreaMatrix" => LinuxRepositoryPathIssue.InsideAreaMatrix,
            "ICloudPath" => LinuxRepositoryPathIssue.ICloudPath,
            "OneDrivePath" => LinuxRepositoryPathIssue.OneDrivePath,
            "WindowsReservedName" => LinuxRepositoryPathIssue.WindowsReservedName,
            "WindowsCaseInsensitive" => LinuxRepositoryPathIssue.WindowsCaseInsensitive,
            "UnfinishedScanSession" => LinuxRepositoryPathIssue.UnfinishedScanSession,
            _ => throw new LinuxRepositoryCoreException(
                LinuxRepositoryErrorKind.Config,
                $"Unknown repository path issue `{value}`.")
        };
    }
}

internal static class LinuxPlatformPathClassifier
{
    public static LinuxPlatformPathKind Classify(
        string repoPath,
        LinuxPlatformPathKind corePathKind)
    {
        if (corePathKind != LinuxPlatformPathKind.Local)
        {
            return corePathKind;
        }

        return LooksLikeRemovableMount(repoPath)
            ? LinuxPlatformPathKind.ExternalDrive
            : corePathKind;
    }

    private static bool LooksLikeRemovableMount(string repoPath)
    {
        string normalized = repoPath.Trim().Replace('\\', '/');
        return normalized.StartsWith("/media/", StringComparison.Ordinal)
            || normalized.StartsWith("/run/media/", StringComparison.Ordinal);
    }
}

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

public sealed record CorePlatformCapabilitySupport(
    string Status,
    bool UiEnabled,
    bool RequiresPermission,
    string? Reason)
{
    public LinuxPlatformCapabilitySupport ToLinuxSupport()
    {
        return new LinuxPlatformCapabilitySupport(
            ParseCapabilityStatus(Status),
            UiEnabled,
            RequiresPermission,
            Reason);
    }

    private static LinuxPlatformCapabilityStatus ParseCapabilityStatus(string value)
    {
        return value switch
        {
            "Available" => LinuxPlatformCapabilityStatus.Available,
            "Limited" => LinuxPlatformCapabilityStatus.Limited,
            "NotAvailable" => LinuxPlatformCapabilityStatus.NotAvailable,
            "Unknown" => LinuxPlatformCapabilityStatus.Unknown,
            _ => throw new LinuxRepositoryCoreException(
                LinuxRepositoryErrorKind.Config,
                $"Unknown platform capability status `{value}`.")
        };
    }
}

public sealed record CorePlatformCapabilities(
    string Platform,
    string AppVersion,
    CorePlatformCapabilitySupport Watcher,
    CorePlatformCapabilitySupport Trash,
    CorePlatformCapabilitySupport ShareExtension,
    CorePlatformCapabilitySupport CloudPlaceholder,
    CorePlatformCapabilitySupport SecurityBookmark)
{
    public LinuxPlatformCapabilities ToLinuxCapabilities()
    {
        return new LinuxPlatformCapabilities(
            ParsePlatformId(Platform),
            AppVersion,
            Watcher.ToLinuxSupport(),
            Trash.ToLinuxSupport(),
            ShareExtension.ToLinuxSupport(),
            CloudPlaceholder.ToLinuxSupport(),
            SecurityBookmark.ToLinuxSupport());
    }

    private static LinuxPlatformId ParsePlatformId(string value)
    {
        return value switch
        {
            "Macos" => LinuxPlatformId.Macos,
            "Ios" => LinuxPlatformId.Ios,
            "Windows" => LinuxPlatformId.Windows,
            "Linux" => LinuxPlatformId.Linux,
            "Unknown" => LinuxPlatformId.Unknown,
            _ => throw new LinuxRepositoryCoreException(
                LinuxRepositoryErrorKind.Config,
                $"Unknown platform id `{value}`.")
        };
    }
}

internal static class LinuxPlatformCapabilityMapping
{
    public static string ToCorePlatformId(this LinuxPlatformId platform)
    {
        return platform switch
        {
            LinuxPlatformId.Macos => "Macos",
            LinuxPlatformId.Ios => "Ios",
            LinuxPlatformId.Windows => "Windows",
            LinuxPlatformId.Linux => "Linux",
            LinuxPlatformId.Unknown => "Unknown",
            _ => throw new LinuxRepositoryCoreException(
                LinuxRepositoryErrorKind.Config,
                $"Unsupported Linux platform id `{platform}`.")
        };
    }
}
