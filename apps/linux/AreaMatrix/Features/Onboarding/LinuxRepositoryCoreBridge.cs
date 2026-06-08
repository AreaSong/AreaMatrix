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

public interface IAreaMatrixLinuxCoreClient
{
    Task<CoreRepoPathValidation> ValidateRepoPathAsync(
        string repoPath,
        CancellationToken cancellationToken = default);

    Task InitRepoAsync(
        string repoPath,
        CoreRepoInitOptions options,
        CancellationToken cancellationToken = default);
}

public sealed class LinuxRepositoryCoreBridge : ILinuxRepositoryCoreBridge
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
            ParsePlatformPathKind(PlatformPathKind),
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
