using AreaMatrix.Linux.Features.Onboarding;

namespace AreaMatrix.Linux.Tests.ChooseRepository;

internal sealed class FakeLinuxRepositoryCoreBridge :
    ILinuxRepositoryCoreBridge,
    ILinuxPlatformCapabilitiesCoreBridge
{
    private readonly Queue<LinuxRepositoryValidation> validations;
    private readonly LinuxRepositoryValidation fallbackValidation;
    private readonly LinuxPlatformCapabilities capabilities;
    private readonly LinuxRepositoryCoreException? initializeError;

    public FakeLinuxRepositoryCoreBridge(
        LinuxRepositoryValidation validation,
        LinuxPlatformCapabilities? capabilities = null,
        LinuxRepositoryCoreException? initializeError = null)
        : this([validation], capabilities, initializeError)
    {
    }

    public FakeLinuxRepositoryCoreBridge(
        IEnumerable<LinuxRepositoryValidation> validations,
        LinuxPlatformCapabilities? capabilities = null,
        LinuxRepositoryCoreException? initializeError = null)
    {
        IReadOnlyList<LinuxRepositoryValidation> validationList = validations.ToArray();
        if (validationList.Count == 0)
        {
            throw new ArgumentException("At least one Linux repository validation is required.", nameof(validations));
        }

        this.validations = new Queue<LinuxRepositoryValidation>(validationList);
        fallbackValidation = validationList[^1];
        this.capabilities = capabilities ?? LinuxPlatformCapabilitySamples.LinuxDefault();
        this.initializeError = initializeError;
    }

    public List<string> ValidatedPaths { get; } = [];

    public List<string> InitializedPaths { get; } = [];

    public List<string> AdoptedPaths { get; } = [];

    public List<(LinuxPlatformId Platform, string AppVersion)> PlatformCapabilityRequests { get; } = [];

    public Task<LinuxRepositoryValidation> ValidateRepoPathAsync(
        string repoPath,
        CancellationToken cancellationToken = default)
    {
        cancellationToken.ThrowIfCancellationRequested();
        ValidatedPaths.Add(repoPath);
        LinuxRepositoryValidation validation = validations.Count > 0
            ? validations.Dequeue()
            : fallbackValidation;
        return Task.FromResult(validation);
    }

    public Task InitializeEmptyRepositoryAsync(
        string repoPath,
        CancellationToken cancellationToken = default)
    {
        cancellationToken.ThrowIfCancellationRequested();
        InitializedPaths.Add(repoPath);
        if (initializeError is not null)
        {
            throw initializeError;
        }

        return Task.CompletedTask;
    }

    public Task AdoptExistingRepositoryAsync(
        string repoPath,
        CancellationToken cancellationToken = default)
    {
        cancellationToken.ThrowIfCancellationRequested();
        AdoptedPaths.Add(repoPath);
        return Task.CompletedTask;
    }

    public Task<LinuxPlatformCapabilities> GetPlatformCapabilitiesAsync(
        LinuxPlatformId platform,
        string appVersion,
        CancellationToken cancellationToken = default)
    {
        cancellationToken.ThrowIfCancellationRequested();
        PlatformCapabilityRequests.Add((platform, appVersion));
        return Task.FromResult(capabilities);
    }
}

internal sealed class FakeLinuxFolderPickerAdapter : ILinuxFolderPickerAdapter
{
    private readonly string? selectedPath;

    public FakeLinuxFolderPickerAdapter(string? selectedPath)
    {
        this.selectedPath = selectedPath;
    }

    public Task<string?> PickFolderAsync(CancellationToken cancellationToken = default)
    {
        cancellationToken.ThrowIfCancellationRequested();
        return Task.FromResult(selectedPath);
    }
}

internal sealed class FakeLinuxFolderPickerCommandRunner : ILinuxFolderPickerCommandRunner
{
    private readonly HashSet<string> availableCommands;
    private readonly Dictionary<string, LinuxFolderPickerCommandResult> results;

    public FakeLinuxFolderPickerCommandRunner(
        IEnumerable<string> availableCommands,
        IReadOnlyDictionary<string, LinuxFolderPickerCommandResult>? results = null)
    {
        this.availableCommands = availableCommands.ToHashSet(StringComparer.Ordinal);
        this.results = results?.ToDictionary(
            item => item.Key,
            item => item.Value,
            StringComparer.Ordinal) ?? [];
    }

    public List<string> RunCommands { get; } = [];

    public bool CanRun(string executable)
    {
        return availableCommands.Contains(executable);
    }

    public Task<LinuxFolderPickerCommandResult> RunAsync(
        string executable,
        IReadOnlyList<string> arguments,
        CancellationToken cancellationToken)
    {
        cancellationToken.ThrowIfCancellationRequested();
        RunCommands.Add(executable);
        return Task.FromResult(results.TryGetValue(executable, out LinuxFolderPickerCommandResult? result)
            ? result
            : new LinuxFolderPickerCommandResult(1, string.Empty, string.Empty));
    }
}

internal static class LinuxRepositoryValidationSamples
{
    public static LinuxRepositoryValidation Initialized(string path)
    {
        return New(
            path,
            isEmpty: false,
            isInitialized: true,
            recommendedMode: null,
            issues: [LinuxRepositoryPathIssue.AlreadyInitialized]);
    }

    public static LinuxRepositoryValidation EmptyDirectory(string path)
    {
        return New(path, isEmpty: true, recommendedMode: LinuxRepositoryInitMode.CreateEmpty);
    }

    public static LinuxRepositoryValidation NonEmptyDirectory(string path)
    {
        return New(
            path,
            isEmpty: false,
            recommendedMode: LinuxRepositoryInitMode.AdoptExisting,
            issues: [LinuxRepositoryPathIssue.NonEmptyDirectory]);
    }

    public static LinuxRepositoryValidation NetworkShare(string path)
    {
        return New(
            path,
            isEmpty: false,
            platformPathKind: LinuxPlatformPathKind.NetworkShare,
            isCaseSensitivePath: false,
            recommendedMode: LinuxRepositoryInitMode.AdoptExisting,
            issues:
            [
                LinuxRepositoryPathIssue.WindowsCaseInsensitive,
                LinuxRepositoryPathIssue.NonEmptyDirectory
            ]);
    }

    public static LinuxRepositoryValidation ExternalDrive(string path)
    {
        return New(
            path,
            isEmpty: false,
            platformPathKind: LinuxPlatformPathKind.ExternalDrive,
            recommendedMode: LinuxRepositoryInitMode.AdoptExisting,
            issues: [LinuxRepositoryPathIssue.NonEmptyDirectory]);
    }

    public static LinuxRepositoryValidation Missing(string path)
    {
        return New(
            path,
            exists: false,
            isDirectory: false,
            isReadable: false,
            isWritable: false,
            isEmpty: false,
            recommendedMode: null,
            issues: [LinuxRepositoryPathIssue.MissingPath]);
    }

    public static LinuxRepositoryValidation SelectedFile(string path)
    {
        return New(
            path,
            isDirectory: false,
            isReadable: false,
            isWritable: false,
            isEmpty: false,
            recommendedMode: null,
            issues: [LinuxRepositoryPathIssue.NotDirectory]);
    }

    public static LinuxRepositoryValidation NotWritable(string path)
    {
        return New(
            path,
            isWritable: false,
            isEmpty: false,
            recommendedMode: null,
            issues:
            [
                LinuxRepositoryPathIssue.NotWritable,
                LinuxRepositoryPathIssue.NonEmptyDirectory
            ]);
    }

    public static LinuxRepositoryValidation ICloudPath(string path)
    {
        return New(
            path,
            isEmpty: true,
            isICloudPath: true,
            platformPathKind: LinuxPlatformPathKind.ICloudDrive,
            recommendedMode: LinuxRepositoryInitMode.CreateEmpty,
            issues: [LinuxRepositoryPathIssue.ICloudPath]);
    }

    private static LinuxRepositoryValidation New(
        string path,
        bool exists = true,
        bool isDirectory = true,
        bool isReadable = true,
        bool isWritable = true,
        bool isEmpty = true,
        bool isInitialized = false,
        bool isICloudPath = false,
        bool isOneDrivePath = false,
        LinuxPlatformPathKind platformPathKind = LinuxPlatformPathKind.Local,
        bool isCaseSensitivePath = true,
        LinuxRepositoryInitMode? recommendedMode = LinuxRepositoryInitMode.CreateEmpty,
        IReadOnlyList<LinuxRepositoryPathIssue>? issues = null)
    {
        return new LinuxRepositoryValidation(
            path,
            exists,
            isDirectory,
            isReadable,
            isWritable,
            isEmpty,
            isInitialized,
            IsInsideAreaMatrix: false,
            isICloudPath,
            isOneDrivePath,
            platformPathKind,
            isCaseSensitivePath,
            HasUnfinishedScanSession: false,
            recommendedMode,
            issues ?? []);
    }
}

internal static class LinuxPlatformCapabilitySamples
{
    public static LinuxPlatformCapabilities LinuxDefault()
    {
        return new LinuxPlatformCapabilities(
            LinuxPlatformId.Linux,
            "0.1.0",
            Available(),
            Limited("freedesktop Trash support depends on the desktop and mount"),
            NotAvailable("share extension import is not available on Linux"),
            NotAvailable("Linux sync folders do not expose a standard placeholder contract"),
            NotAvailable("Linux uses POSIX permissions instead of security-scoped bookmarks"));
    }

    public static LinuxPlatformCapabilities WatcherLimited(string reason)
    {
        LinuxPlatformCapabilities defaults = LinuxDefault();
        return defaults with
        {
            Watcher = new LinuxPlatformCapabilitySupport(
                LinuxPlatformCapabilityStatus.Limited,
                UiEnabled: false,
                RequiresPermission: false,
                reason)
        };
    }

    private static LinuxPlatformCapabilitySupport Available()
    {
        return new LinuxPlatformCapabilitySupport(
            LinuxPlatformCapabilityStatus.Available,
            UiEnabled: true,
            RequiresPermission: false,
            Reason: null);
    }

    private static LinuxPlatformCapabilitySupport Limited(string reason)
    {
        return new LinuxPlatformCapabilitySupport(
            LinuxPlatformCapabilityStatus.Limited,
            UiEnabled: true,
            RequiresPermission: false,
            reason);
    }

    private static LinuxPlatformCapabilitySupport NotAvailable(string reason)
    {
        return new LinuxPlatformCapabilitySupport(
            LinuxPlatformCapabilityStatus.NotAvailable,
            UiEnabled: false,
            RequiresPermission: false,
            reason);
    }
}
