using AreaMatrix.Features.Onboarding;

namespace AreaMatrixTests.ChooseRepository;

public static class RepositoryInitConfirmViewModelTests
{
    public static async Task RunAllAsync()
    {
        await OpeningRouteRefreshesValidationWithoutWritingMetadata();
        await CreateRepositoryInitializesReloadsConfigAndRoutesToMainWindow();
        await CreateRepositoryFailureStaysOnConfirmation();
        await NonEmptyOrUnwritableValidationBlocksCreateAction();
        await OneDriveEmptyFolderShowsRiskWithoutControllingSync();
    }

    private static async Task OpeningRouteRefreshesValidationWithoutWritingMetadata()
    {
        const string path = @"C:\Repos\Empty";
        RepositoryInitConfirmCoreBridge bridge = new(
            [WindowsRepositoryValidationSamples.EmptyDirectory(path)]);
        RepositoryInitConfirmViewModel model = new(bridge);

        await model.OpenRouteAsync(Route(path));

        TestAssert.SequenceEqual([path], bridge.ValidatedPaths, "validated paths");
        TestAssert.Empty(bridge.InitializedPaths, nameof(bridge.InitializedPaths));
        TestAssert.Empty(bridge.LoadedConfigPaths, nameof(bridge.LoadedConfigPaths));
        TestAssert.True(model.CanCreateRepository, nameof(model.CanCreateRepository));
        TestAssert.Contains(".areamatrix", model.SafetyText, nameof(model.SafetyText));
        TestAssert.Contains("No existing files", model.NoOverwriteText, nameof(model.NoOverwriteText));
    }

    private static async Task CreateRepositoryInitializesReloadsConfigAndRoutesToMainWindow()
    {
        const string path = @"C:\Repos\Empty";
        RepositoryInitConfirmCoreBridge bridge = new(
            [
                WindowsRepositoryValidationSamples.EmptyDirectory(path),
                WindowsRepositoryValidationSamples.Initialized(path)
            ]);
        RepositoryInitConfirmViewModel model = new(bridge);

        await model.OpenRouteAsync(Route(path));
        await model.CreateRepositoryAsync();

        TestAssert.SequenceEqual([path, path], bridge.ValidatedPaths, "validated paths");
        TestAssert.SequenceEqual([path], bridge.InitializedPaths, nameof(bridge.InitializedPaths));
        TestAssert.SequenceEqual([path], bridge.LoadedConfigPaths, nameof(bridge.LoadedConfigPaths));
        TestAssert.Equal(WindowsRepositoryRouteKind.MainWindow, model.CompletedRoute.Kind, "completed route");
        TestAssert.Equal(path, model.CompletedRoute.Config?.RepoPath, "config repo path");
        TestAssert.True(model.CompletedRoute.Validation?.IsInitialized == true, "initialized validation");
        TestAssert.Null(model.Error, nameof(model.Error));
    }

    private static async Task CreateRepositoryFailureStaysOnConfirmation()
    {
        const string path = @"C:\Repos\Readonly";
        RepositoryInitConfirmCoreBridge bridge = new(
            [WindowsRepositoryValidationSamples.EmptyDirectory(path)],
            initializeError: new WindowsRepositoryCoreException(
                WindowsRepositoryErrorKind.PermissionDenied,
                "permission denied",
                path));
        RepositoryInitConfirmViewModel model = new(bridge);

        await model.OpenRouteAsync(Route(path));
        await model.CreateRepositoryAsync();

        TestAssert.SequenceEqual([path], bridge.InitializedPaths, nameof(bridge.InitializedPaths));
        TestAssert.Empty(bridge.LoadedConfigPaths, nameof(bridge.LoadedConfigPaths));
        TestAssert.Equal(WindowsRepositoryRouteKind.None, model.CompletedRoute.Kind, "completed route");
        TestAssert.Equal(WindowsRepositoryErrorKind.PermissionDenied, model.Error?.Kind, "error kind");
        TestAssert.Equal("Choose another folder.", model.StatusText, nameof(model.StatusText));
    }

    private static async Task NonEmptyOrUnwritableValidationBlocksCreateAction()
    {
        const string nonEmptyPath = @"C:\Repos\Existing";
        RepositoryInitConfirmCoreBridge nonEmptyBridge = new(
            [WindowsRepositoryValidationSamples.NonEmptyDirectory(nonEmptyPath)]);
        RepositoryInitConfirmViewModel nonEmptyModel = new(nonEmptyBridge);

        await nonEmptyModel.OpenRouteAsync(Route(nonEmptyPath));
        await nonEmptyModel.CreateRepositoryAsync();

        TestAssert.False(nonEmptyModel.CanCreateRepository, "non-empty can create");
        TestAssert.Empty(nonEmptyBridge.InitializedPaths, "non-empty initialized paths");
        TestAssert.Equal(
            "This folder is not eligible for empty repository creation.",
            nonEmptyModel.DisabledReason,
            "non-empty disabled reason");

        const string readonlyPath = @"C:\Repos\Readonly";
        RepositoryInitConfirmCoreBridge readonlyBridge = new(
            [WindowsRepositoryValidationSamples.NotWritable(readonlyPath)]);
        RepositoryInitConfirmViewModel readonlyModel = new(readonlyBridge);

        await readonlyModel.OpenRouteAsync(Route(readonlyPath));
        await readonlyModel.CreateRepositoryAsync();

        TestAssert.False(readonlyModel.CanCreateRepository, "readonly can create");
        TestAssert.Empty(readonlyBridge.InitializedPaths, "readonly initialized paths");
        TestAssert.Equal(WindowsRepositoryErrorKind.PermissionDenied, readonlyModel.Error?.Kind, "readonly error");
    }

    private static async Task OneDriveEmptyFolderShowsRiskWithoutControllingSync()
    {
        const string path = @"C:\Users\me\OneDrive\Empty";
        RepositoryInitConfirmCoreBridge bridge = new(
            [WindowsRepositoryValidationSamples.OneDriveEmptyDirectory(path)]);
        RepositoryInitConfirmViewModel model = new(bridge);

        await model.OpenRouteAsync(Route(path));

        TestAssert.True(model.CanCreateRepository, nameof(model.CanCreateRepository));
        TestAssert.Equal("Type: OneDrive", model.PathTypeText, nameof(model.PathTypeText));
        TestAssert.Contains("OneDrive sync is controlled outside AreaMatrix", model.RiskText, "risk text");
        TestAssert.Empty(bridge.CloudStatePaths, nameof(bridge.CloudStatePaths));
    }

    private static WindowsRepositoryRoute Route(string path)
    {
        return new WindowsRepositoryRoute(
            WindowsRepositoryRouteKind.RepositoryInitConfirm,
            path,
            WindowsRepositoryValidationSamples.EmptyDirectory(path),
            null);
    }
}

internal sealed class RepositoryInitConfirmCoreBridge : IWindowsRepositoryCoreBridge
{
    private readonly Queue<WindowsRepositoryValidation> validations;
    private readonly WindowsRepositoryCoreException? initializeError;

    public RepositoryInitConfirmCoreBridge(
        IEnumerable<WindowsRepositoryValidation> validations,
        WindowsRepositoryCoreException? initializeError = null)
    {
        this.validations = new Queue<WindowsRepositoryValidation>(validations);
        this.initializeError = initializeError;
    }

    public List<string> ValidatedPaths { get; } = [];

    public List<string> CloudStatePaths { get; } = [];

    public List<string> AcknowledgedPaths { get; } = [];

    public List<string> LoadedConfigPaths { get; } = [];

    public List<string> InitializedPaths { get; } = [];

    public List<string> AdoptedPaths { get; } = [];

    public Task<WindowsRepositoryValidation> ValidateRepoPathAsync(
        string repoPath,
        CancellationToken cancellationToken = default)
    {
        ValidatedPaths.Add(repoPath);
        WindowsRepositoryValidation validation = validations.Count > 0
            ? validations.Dequeue()
            : WindowsRepositoryValidationSamples.EmptyDirectory(repoPath);
        return Task.FromResult(validation);
    }

    public Task<WindowsCloudStorageState> DetectCloudStorageStateAsync(
        string repoPath,
        CancellationToken cancellationToken = default)
    {
        CloudStatePaths.Add(repoPath);
        return Task.FromResult(WindowsCloudStorageStateSamples.Local(repoPath));
    }

    public Task<WindowsCloudStorageState> AcknowledgeOneDriveRiskNoticeAsync(
        string repoPath,
        CancellationToken cancellationToken = default)
    {
        AcknowledgedPaths.Add(repoPath);
        return Task.FromResult(WindowsCloudStorageStateSamples.AcknowledgedOneDrive(repoPath));
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
        AdoptedPaths.Add(repoPath);
        return Task.CompletedTask;
    }
}
