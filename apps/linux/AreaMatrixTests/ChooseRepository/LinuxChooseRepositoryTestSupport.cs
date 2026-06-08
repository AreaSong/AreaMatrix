using AreaMatrix.Linux.Features.Onboarding;

namespace AreaMatrix.Linux.Tests.ChooseRepository;

internal sealed class FakeLinuxRepositoryCoreBridge : ILinuxRepositoryCoreBridge
{
    private readonly LinuxRepositoryValidation validation;

    public FakeLinuxRepositoryCoreBridge(LinuxRepositoryValidation validation)
    {
        this.validation = validation;
    }

    public List<string> ValidatedPaths { get; } = [];

    public List<string> InitializedPaths { get; } = [];

    public List<string> AdoptedPaths { get; } = [];

    public Task<LinuxRepositoryValidation> ValidateRepoPathAsync(
        string repoPath,
        CancellationToken cancellationToken = default)
    {
        cancellationToken.ThrowIfCancellationRequested();
        ValidatedPaths.Add(repoPath);
        return Task.FromResult(validation);
    }

    public Task InitializeEmptyRepositoryAsync(
        string repoPath,
        CancellationToken cancellationToken = default)
    {
        cancellationToken.ThrowIfCancellationRequested();
        InitializedPaths.Add(repoPath);
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
