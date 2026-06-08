using AreaMatrix.Features.Onboarding;

namespace AreaMatrixTests.ChooseRepository;

public static class ChooseRepositoryViewModelTests
{
    public static async Task RunAllAsync()
    {
        await ExistingRepositoryRoutesToMainWindowAfterValidationAndConfigLoad();
        await EmptyDirectoryRoutesToInitConfirmationWithoutInitializing();
        await NonEmptyDirectoryRoutesToAdoptConfirmationWithoutWritingMetadata();
        await OneDriveDirectoryRoutesToNoticeBeforeOpenInitOrAdopt();
        await AcknowledgedOneDriveRepositoryCanContinueToOriginalRoute();
        await InvalidAndPermissionStatesDisableContinueWithPageSpecMessages();
        await ManualPathEditClearsPreviousValidationBeforeRechecking();
    }

    private static async Task ExistingRepositoryRoutesToMainWindowAfterValidationAndConfigLoad()
    {
        FakeWindowsRepositoryCoreBridge bridge = new(WindowsRepositoryValidationSamples.Initialized(@"C:\Repos\AreaMatrix"));
        ChooseRepositoryViewModel model = new(bridge);

        await model.CheckRepositoryPathAsync(@"C:\Repos\AreaMatrix");
        await model.ContinueAsync();

        TestAssert.SequenceEqual([@"C:\Repos\AreaMatrix"], bridge.ValidatedPaths, nameof(bridge.ValidatedPaths));
        TestAssert.SequenceEqual([@"C:\Repos\AreaMatrix"], bridge.LoadedConfigPaths, nameof(bridge.LoadedConfigPaths));
        TestAssert.Empty(bridge.InitializedPaths, nameof(bridge.InitializedPaths));
        TestAssert.Empty(bridge.AdoptedPaths, nameof(bridge.AdoptedPaths));
        TestAssert.Equal(WindowsRepositoryRouteKind.MainWindow, model.Route.Kind, nameof(model.Route.Kind));
        TestAssert.Equal(@"C:\Repos\AreaMatrix", model.Route.Config?.RepoPath, "config repo path");
        TestAssert.Null(model.Error, nameof(model.Error));
    }

    private static async Task EmptyDirectoryRoutesToInitConfirmationWithoutInitializing()
    {
        FakeWindowsRepositoryCoreBridge bridge = new(WindowsRepositoryValidationSamples.EmptyDirectory(@"C:\Repos\Empty"));
        ChooseRepositoryViewModel model = new(bridge);

        await model.CheckRepositoryPathAsync(@"C:\Repos\Empty");
        await model.ContinueAsync();

        TestAssert.SequenceEqual([@"C:\Repos\Empty"], bridge.ValidatedPaths, nameof(bridge.ValidatedPaths));
        TestAssert.Empty(bridge.LoadedConfigPaths, nameof(bridge.LoadedConfigPaths));
        TestAssert.Empty(bridge.InitializedPaths, nameof(bridge.InitializedPaths));
        TestAssert.Empty(bridge.AdoptedPaths, nameof(bridge.AdoptedPaths));
        TestAssert.Equal(WindowsRepositoryRouteKind.RepositoryInitConfirm, model.Route.Kind, nameof(model.Route.Kind));
        TestAssert.Equal(
            WindowsRepositoryInitMode.CreateEmpty,
            model.LatestValidation?.RecommendedMode,
            "recommended mode");
    }

    private static async Task NonEmptyDirectoryRoutesToAdoptConfirmationWithoutWritingMetadata()
    {
        FakeWindowsRepositoryCoreBridge bridge = new(WindowsRepositoryValidationSamples.NonEmptyDirectory(@"C:\Repos\Existing"));
        ChooseRepositoryViewModel model = new(bridge);

        await model.CheckRepositoryPathAsync(@"C:\Repos\Existing");
        await model.ContinueAsync();

        TestAssert.SequenceEqual([@"C:\Repos\Existing"], bridge.ValidatedPaths, nameof(bridge.ValidatedPaths));
        TestAssert.Empty(bridge.LoadedConfigPaths, nameof(bridge.LoadedConfigPaths));
        TestAssert.Empty(bridge.InitializedPaths, nameof(bridge.InitializedPaths));
        TestAssert.Empty(bridge.AdoptedPaths, nameof(bridge.AdoptedPaths));
        TestAssert.Equal(WindowsRepositoryRouteKind.RepositoryAdoptConfirm, model.Route.Kind, nameof(model.Route.Kind));
        TestAssert.Equal(
            WindowsRepositoryInitMode.AdoptExisting,
            model.LatestValidation?.RecommendedMode,
            "recommended mode");
    }

    private static async Task OneDriveDirectoryRoutesToNoticeBeforeOpenInitOrAdopt()
    {
        FakeWindowsRepositoryCoreBridge bridge = new(WindowsRepositoryValidationSamples.OneDriveDirectory(
            @"C:\Users\me\OneDrive\AreaMatrix"));
        ChooseRepositoryViewModel model = new(bridge);

        await model.CheckRepositoryPathAsync(@"C:\Users\me\OneDrive\AreaMatrix");
        await model.ContinueAsync();

        TestAssert.SequenceEqual([@"C:\Users\me\OneDrive\AreaMatrix"], bridge.ValidatedPaths, nameof(bridge.ValidatedPaths));
        TestAssert.SequenceEqual([@"C:\Users\me\OneDrive\AreaMatrix"], bridge.CloudStatePaths, nameof(bridge.CloudStatePaths));
        TestAssert.Empty(bridge.LoadedConfigPaths, nameof(bridge.LoadedConfigPaths));
        TestAssert.Empty(bridge.InitializedPaths, nameof(bridge.InitializedPaths));
        TestAssert.Empty(bridge.AdoptedPaths, nameof(bridge.AdoptedPaths));
        TestAssert.Equal(WindowsRepositoryRouteKind.OneDriveNotice, model.Route.Kind, nameof(model.Route.Kind));
        TestAssert.Null(model.Route.Config, nameof(model.Route.Config));
        TestAssert.Equal(
            WindowsCloudStorageRecommendedAction.AcknowledgeNotice,
            model.LatestCloudStorageState?.RecommendedAction,
            "cloud recommended action");
        TestAssert.Contains(
            "OneDrive path detected",
            model.StatusText,
            nameof(model.StatusText));
    }

    private static async Task AcknowledgedOneDriveRepositoryCanContinueToOriginalRoute()
    {
        FakeWindowsRepositoryCoreBridge bridge = new(
            WindowsRepositoryValidationSamples.OneDriveDirectory(@"C:\Users\me\OneDrive\AreaMatrix"),
            WindowsCloudStorageStateSamples.AcknowledgedOneDrive(@"C:\Users\me\OneDrive\AreaMatrix"));
        ChooseRepositoryViewModel model = new(bridge);

        await model.CheckRepositoryPathAsync(@"C:\Users\me\OneDrive\AreaMatrix");
        await model.ContinueAsync();

        TestAssert.SequenceEqual([@"C:\Users\me\OneDrive\AreaMatrix"], bridge.ValidatedPaths, nameof(bridge.ValidatedPaths));
        TestAssert.SequenceEqual([@"C:\Users\me\OneDrive\AreaMatrix"], bridge.CloudStatePaths, nameof(bridge.CloudStatePaths));
        TestAssert.SequenceEqual([@"C:\Users\me\OneDrive\AreaMatrix"], bridge.LoadedConfigPaths, nameof(bridge.LoadedConfigPaths));
        TestAssert.Equal(WindowsRepositoryRouteKind.MainWindow, model.Route.Kind, nameof(model.Route.Kind));
        TestAssert.Equal(@"C:\Users\me\OneDrive\AreaMatrix", model.Route.Config?.RepoPath, "config repo path");
        TestAssert.Equal(
            WindowsCloudStorageRecommendedAction.None,
            model.Route.CloudStorageState?.RecommendedAction,
            "route cloud recommended action");
    }

    private static async Task InvalidAndPermissionStatesDisableContinueWithPageSpecMessages()
    {
        FakeWindowsRepositoryCoreBridge missingBridge = new(WindowsRepositoryValidationSamples.Missing(@"C:\Missing"));
        ChooseRepositoryViewModel missingModel = new(missingBridge);
        await missingModel.CheckRepositoryPathAsync(@"C:\Missing");

        TestAssert.False(missingModel.CanContinue, nameof(missingModel.CanContinue));
        TestAssert.Equal(WindowsRepositoryErrorKind.InvalidPath, missingModel.Error?.Kind, "missing error kind");
        TestAssert.Equal("Folder not found", missingModel.StatusText, nameof(missingModel.StatusText));

        FakeWindowsRepositoryCoreBridge fileBridge = new(WindowsRepositoryValidationSamples.SelectedFile(@"C:\Repo\file.txt"));
        ChooseRepositoryViewModel fileModel = new(fileBridge);
        await fileModel.CheckRepositoryPathAsync(@"C:\Repo\file.txt");

        TestAssert.False(fileModel.CanContinue, nameof(fileModel.CanContinue));
        TestAssert.Equal(WindowsRepositoryErrorKind.SelectedFile, fileModel.Error?.Kind, "selected file error kind");
        TestAssert.Equal("Select a folder, not a file.", fileModel.StatusText, nameof(fileModel.StatusText));
    }

    private static async Task ManualPathEditClearsPreviousValidationBeforeRechecking()
    {
        FakeWindowsRepositoryCoreBridge bridge = new(WindowsRepositoryValidationSamples.Initialized(@"C:\Repos\AreaMatrix"));
        ChooseRepositoryViewModel model = new(bridge);

        await model.CheckRepositoryPathAsync(@"C:\Repos\AreaMatrix");
        model.RepositoryPath = @"C:\Repos\Other";

        TestAssert.Null(model.LatestValidation, nameof(model.LatestValidation));
        TestAssert.Null(model.LatestCloudStorageState, nameof(model.LatestCloudStorageState));
        TestAssert.Null(model.LatestConfig, nameof(model.LatestConfig));
        TestAssert.Equal(WindowsRepositoryRouteKind.None, model.Route.Kind, nameof(model.Route.Kind));
        TestAssert.False(model.CanContinue, nameof(model.CanContinue));
    }
}

internal sealed class FakeWindowsRepositoryCoreBridge : IWindowsRepositoryCoreBridge
{
    private readonly WindowsRepositoryValidation validation;
    private readonly WindowsCloudStorageState cloudStorageState;

    public FakeWindowsRepositoryCoreBridge(
        WindowsRepositoryValidation validation,
        WindowsCloudStorageState? cloudStorageState = null)
    {
        this.validation = validation;
        this.cloudStorageState = cloudStorageState
            ?? WindowsCloudStorageStateSamples.FromValidation(validation);
    }

    public List<string> ValidatedPaths { get; } = [];

    public List<string> CloudStatePaths { get; } = [];

    public List<string> LoadedConfigPaths { get; } = [];

    public List<string> InitializedPaths { get; } = [];

    public List<string> AdoptedPaths { get; } = [];

    public Task<WindowsRepositoryValidation> ValidateRepoPathAsync(
        string repoPath,
        CancellationToken cancellationToken = default)
    {
        ValidatedPaths.Add(repoPath);
        return Task.FromResult(validation);
    }

    public Task<WindowsCloudStorageState> DetectCloudStorageStateAsync(
        string repoPath,
        CancellationToken cancellationToken = default)
    {
        CloudStatePaths.Add(repoPath);
        return Task.FromResult(cloudStorageState);
    }

    public Task<WindowsRepositoryConfig> LoadConfigAsync(
        string repoPath,
        CancellationToken cancellationToken = default)
    {
        LoadedConfigPaths.Add(repoPath);
        return Task.FromResult(new WindowsRepositoryConfig(repoPath, "copy", "en-US"));
    }

    public Task InitializeEmptyRepositoryAsync(
        string repoPath,
        CancellationToken cancellationToken = default)
    {
        InitializedPaths.Add(repoPath);
        return Task.CompletedTask;
    }

    public Task AdoptExistingRepositoryAsync(
        string repoPath,
        CancellationToken cancellationToken = default)
    {
        AdoptedPaths.Add(repoPath);
        return Task.CompletedTask;
    }
}

internal static class WindowsCloudStorageStateSamples
{
    public static WindowsCloudStorageState FromValidation(WindowsRepositoryValidation validation)
    {
        return validation.IsOneDrivePath || validation.PlatformPathKind == WindowsPlatformPathKind.OneDrive
            ? UnacknowledgedOneDrive(validation.RepoPath)
            : Local(validation.RepoPath);
    }

    public static WindowsCloudStorageState Local(string path)
    {
        return new WindowsCloudStorageState(
            path,
            WindowsCloudStorageProviderKind.Local,
            WindowsCloudStorageRiskLevel.NoRisk,
            WindowsCloudPlaceholderState.NotPlaceholder,
            WindowsCloudPermissionState.Accessible,
            "Local folder",
            [],
            WindowsCloudStorageRecommendedAction.None,
            RequiresNoticeAcknowledgement: false,
            NoticeAcknowledged: false,
            CanRetry: false,
            RequiresReconnect: false);
    }

    public static WindowsCloudStorageState UnacknowledgedOneDrive(string path)
    {
        return new WindowsCloudStorageState(
            path,
            WindowsCloudStorageProviderKind.OneDrive,
            WindowsCloudStorageRiskLevel.Medium,
            WindowsCloudPlaceholderState.NotPlaceholder,
            WindowsCloudPermissionState.Accessible,
            "OneDrive path detected. Review sync risks before continuing.",
            ["OneDrive SDK is not managed by AreaMatrix.", "Conflict copies may appear later."],
            WindowsCloudStorageRecommendedAction.AcknowledgeNotice,
            RequiresNoticeAcknowledgement: true,
            NoticeAcknowledged: false,
            CanRetry: false,
            RequiresReconnect: false);
    }

    public static WindowsCloudStorageState AcknowledgedOneDrive(string path)
    {
        return new WindowsCloudStorageState(
            path,
            WindowsCloudStorageProviderKind.OneDrive,
            WindowsCloudStorageRiskLevel.Medium,
            WindowsCloudPlaceholderState.NotPlaceholder,
            WindowsCloudPermissionState.Accessible,
            "OneDrive path detected. Risk notice has already been acknowledged.",
            ["OneDrive SDK is not managed by AreaMatrix."],
            WindowsCloudStorageRecommendedAction.None,
            RequiresNoticeAcknowledgement: false,
            NoticeAcknowledged: true,
            CanRetry: false,
            RequiresReconnect: false);
    }
}

internal static class TestAssert
{
    public static void Equal<T>(T expected, T actual, string label)
    {
        if (!EqualityComparer<T>.Default.Equals(expected, actual))
        {
            throw new InvalidOperationException($"{label}: expected `{expected}`, got `{actual}`.");
        }
    }

    public static void SequenceEqual<T>(IReadOnlyList<T> expected, IReadOnlyList<T> actual, string label)
    {
        if (expected.Count != actual.Count)
        {
            throw new InvalidOperationException($"{label}: expected {expected.Count} item(s), got {actual.Count}.");
        }

        for (int index = 0; index < expected.Count; index += 1)
        {
            Equal(expected[index], actual[index], $"{label}[{index}]");
        }
    }

    public static void Empty<T>(IReadOnlyCollection<T> actual, string label)
    {
        if (actual.Count != 0)
        {
            throw new InvalidOperationException($"{label}: expected empty, got {actual.Count} item(s).");
        }
    }

    public static void False(bool actual, string label)
    {
        if (actual)
        {
            throw new InvalidOperationException($"{label}: expected false.");
        }
    }

    public static void Contains(string expectedSubstring, string actual, string label)
    {
        if (!actual.Contains(expectedSubstring, StringComparison.Ordinal))
        {
            throw new InvalidOperationException($"{label}: expected `{expectedSubstring}`.");
        }
    }

    public static void Null<T>(T? actual, string label)
    {
        if (actual is not null)
        {
            throw new InvalidOperationException($"{label}: expected null.");
        }
    }
}

internal static class WindowsRepositoryValidationSamples
{
    public static WindowsRepositoryValidation Initialized(string path)
    {
        return Valid(path, isEmpty: false, isInitialized: true, recommendedMode: null);
    }

    public static WindowsRepositoryValidation EmptyDirectory(string path)
    {
        return Valid(path, isEmpty: true, isInitialized: false, recommendedMode: WindowsRepositoryInitMode.CreateEmpty);
    }

    public static WindowsRepositoryValidation NonEmptyDirectory(string path)
    {
        return Valid(
            path,
            isEmpty: false,
            isInitialized: false,
            recommendedMode: WindowsRepositoryInitMode.AdoptExisting,
            issues: [WindowsRepositoryPathIssue.NonEmptyDirectory]);
    }

    public static WindowsRepositoryValidation OneDriveDirectory(string path)
    {
        return Valid(
            path,
            isEmpty: false,
            isInitialized: true,
            recommendedMode: null,
            isOneDrivePath: true,
            platformPathKind: WindowsPlatformPathKind.OneDrive,
            issues: [WindowsRepositoryPathIssue.OneDrivePath]);
    }

    public static WindowsRepositoryValidation OneDriveEmptyDirectory(string path)
    {
        return Valid(
            path,
            isEmpty: true,
            isInitialized: false,
            isOneDrivePath: true,
            platformPathKind: WindowsPlatformPathKind.OneDrive,
            recommendedMode: WindowsRepositoryInitMode.CreateEmpty,
            issues: [WindowsRepositoryPathIssue.OneDrivePath]);
    }

    public static WindowsRepositoryValidation OneDriveNonEmptyDirectory(string path)
    {
        return Valid(
            path,
            isEmpty: false,
            isInitialized: false,
            isOneDrivePath: true,
            platformPathKind: WindowsPlatformPathKind.OneDrive,
            recommendedMode: WindowsRepositoryInitMode.AdoptExisting,
            issues: [WindowsRepositoryPathIssue.OneDrivePath, WindowsRepositoryPathIssue.NonEmptyDirectory]);
    }

    public static WindowsRepositoryValidation Missing(string path)
    {
        return Valid(
            path,
            exists: false,
            isDirectory: false,
            isReadable: false,
            isWritable: false,
            isEmpty: false,
            isInitialized: false,
            recommendedMode: null,
            issues: [WindowsRepositoryPathIssue.MissingPath]);
    }

    public static WindowsRepositoryValidation SelectedFile(string path)
    {
        return Valid(
            path,
            isDirectory: false,
            isEmpty: false,
            isInitialized: false,
            recommendedMode: null,
            issues: [WindowsRepositoryPathIssue.NotDirectory]);
    }

    public static WindowsRepositoryValidation NotWritable(string path)
    {
        return Valid(
            path,
            isWritable: false,
            isEmpty: true,
            isInitialized: false,
            recommendedMode: WindowsRepositoryInitMode.CreateEmpty,
            issues: [WindowsRepositoryPathIssue.NotWritable]);
    }

    private static WindowsRepositoryValidation Valid(
        string path,
        bool exists = true,
        bool isDirectory = true,
        bool isReadable = true,
        bool isWritable = true,
        bool isEmpty = true,
        bool isInitialized = false,
        bool isOneDrivePath = false,
        WindowsPlatformPathKind platformPathKind = WindowsPlatformPathKind.Local,
        WindowsRepositoryInitMode? recommendedMode = WindowsRepositoryInitMode.CreateEmpty,
        IReadOnlyList<WindowsRepositoryPathIssue>? issues = null)
    {
        return new WindowsRepositoryValidation(
            path,
            exists,
            isDirectory,
            isReadable,
            isWritable,
            isEmpty,
            isInitialized,
            IsInsideAreaMatrix: false,
            IsICloudPath: false,
            isOneDrivePath,
            platformPathKind,
            IsCaseSensitivePath: false,
            HasUnfinishedScanSession: false,
            recommendedMode,
            issues ?? []);
    }
}
