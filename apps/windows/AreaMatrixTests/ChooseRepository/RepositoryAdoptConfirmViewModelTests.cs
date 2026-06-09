using AreaMatrix.Features.Onboarding;

namespace AreaMatrixTests.ChooseRepository;

public static class RepositoryAdoptConfirmViewModelTests
{
    public static async Task RunAllAsync()
    {
        await OpeningRouteRefreshesValidationWithoutAdopting();
        await ConfirmationIsRequiredBeforeAdopt();
        await AdoptRepositoryInitializesReloadsConfigAndRoutesToMainWindow();
        await AdoptRepositoryFailureStaysOnConfirmation();
        await EmptyOrUnwritableValidationBlocksAdoptAction();
        await OneDriveAdoptShowsRiskWithoutControllingSync();
    }

    private static async Task OpeningRouteRefreshesValidationWithoutAdopting()
    {
        const string path = @"C:\Repos\Existing";
        RepositoryInitConfirmCoreBridge bridge = new(
            [WindowsRepositoryValidationSamples.NonEmptyDirectory(path)]);
        RepositoryAdoptConfirmViewModel model = new(bridge);

        await model.OpenRouteAsync(Route(path));

        TestAssert.SequenceEqual([path], bridge.ValidatedPaths, "validated paths");
        TestAssert.Empty(bridge.AdoptedPaths, nameof(bridge.AdoptedPaths));
        TestAssert.Empty(bridge.LoadedConfigPaths, nameof(bridge.LoadedConfigPaths));
        TestAssert.False(model.CanAdoptRepository, nameof(model.CanAdoptRepository));
        TestAssert.Contains("will not move, delete, rename, or overwrite", model.SafetyText, "safety text");
        TestAssert.Contains(".areamatrix", model.MetadataAddText, nameof(model.MetadataAddText));
    }

    private static async Task ConfirmationIsRequiredBeforeAdopt()
    {
        const string path = @"C:\Repos\Existing";
        RepositoryInitConfirmCoreBridge bridge = new(
            [WindowsRepositoryValidationSamples.NonEmptyDirectory(path)]);
        RepositoryAdoptConfirmViewModel model = new(bridge);

        await model.OpenRouteAsync(Route(path));
        await model.AdoptRepositoryAsync();

        TestAssert.Empty(bridge.AdoptedPaths, nameof(bridge.AdoptedPaths));
        TestAssert.Contains("Confirm that AreaMatrix will add metadata", model.DisabledReason, "disabled reason");

        model.IsMetadataAcknowledged = true;

        TestAssert.True(model.CanAdoptRepository, nameof(model.CanAdoptRepository));
    }

    private static async Task AdoptRepositoryInitializesReloadsConfigAndRoutesToMainWindow()
    {
        const string path = @"C:\Repos\Existing";
        RepositoryInitConfirmCoreBridge bridge = new(
            [
                WindowsRepositoryValidationSamples.NonEmptyDirectory(path),
                WindowsRepositoryValidationSamples.Initialized(path)
            ]);
        RepositoryAdoptConfirmViewModel model = new(bridge);

        await model.OpenRouteAsync(Route(path));
        model.IsMetadataAcknowledged = true;
        await model.AdoptRepositoryAsync();

        TestAssert.SequenceEqual([path, path], bridge.ValidatedPaths, "validated paths");
        TestAssert.SequenceEqual([path], bridge.AdoptedPaths, nameof(bridge.AdoptedPaths));
        TestAssert.Empty(bridge.InitializedPaths, nameof(bridge.InitializedPaths));
        TestAssert.SequenceEqual([path], bridge.LoadedConfigPaths, nameof(bridge.LoadedConfigPaths));
        TestAssert.Equal(WindowsRepositoryRouteKind.MainWindow, model.CompletedRoute.Kind, "completed route");
        TestAssert.Equal(path, model.CompletedRoute.Config?.RepoPath, "config repo path");
        TestAssert.True(model.CompletedRoute.Validation?.IsInitialized == true, "initialized validation");
        TestAssert.Null(model.Error, nameof(model.Error));
    }

    private static async Task AdoptRepositoryFailureStaysOnConfirmation()
    {
        const string path = @"C:\Repos\Existing";
        RepositoryAdoptConfirmCoreBridge bridge = new(
            [WindowsRepositoryValidationSamples.NonEmptyDirectory(path)],
            adoptError: new WindowsRepositoryCoreException(
                WindowsRepositoryErrorKind.PermissionDenied,
                "permission denied",
                path));
        RepositoryAdoptConfirmViewModel model = new(bridge);

        await model.OpenRouteAsync(Route(path));
        model.IsMetadataAcknowledged = true;
        await model.AdoptRepositoryAsync();

        TestAssert.SequenceEqual([path], bridge.AdoptedPaths, nameof(bridge.AdoptedPaths));
        TestAssert.Empty(bridge.LoadedConfigPaths, nameof(bridge.LoadedConfigPaths));
        TestAssert.Equal(WindowsRepositoryRouteKind.None, model.CompletedRoute.Kind, "completed route");
        TestAssert.Equal(WindowsRepositoryErrorKind.PermissionDenied, model.Error?.Kind, "error kind");
        TestAssert.Equal("Choose another folder.", model.StatusText, nameof(model.StatusText));
    }

    private static async Task EmptyOrUnwritableValidationBlocksAdoptAction()
    {
        const string emptyPath = @"C:\Repos\Empty";
        RepositoryInitConfirmCoreBridge emptyBridge = new(
            [WindowsRepositoryValidationSamples.EmptyDirectory(emptyPath)]);
        RepositoryAdoptConfirmViewModel emptyModel = new(emptyBridge);

        await emptyModel.OpenRouteAsync(Route(emptyPath));
        emptyModel.IsMetadataAcknowledged = true;
        await emptyModel.AdoptRepositoryAsync();

        TestAssert.False(emptyModel.CanAdoptRepository, "empty can adopt");
        TestAssert.Empty(emptyBridge.AdoptedPaths, "empty adopted paths");
        TestAssert.Equal(
            "This folder is empty. Use the create repository confirmation instead.",
            emptyModel.DisabledReason,
            "empty disabled reason");

        const string readonlyPath = @"C:\Repos\Readonly";
        RepositoryInitConfirmCoreBridge readonlyBridge = new(
            [WindowsRepositoryValidationSamples.NotWritable(readonlyPath)]);
        RepositoryAdoptConfirmViewModel readonlyModel = new(readonlyBridge);

        await readonlyModel.OpenRouteAsync(Route(readonlyPath));
        readonlyModel.IsMetadataAcknowledged = true;
        await readonlyModel.AdoptRepositoryAsync();

        TestAssert.False(readonlyModel.CanAdoptRepository, "readonly can adopt");
        TestAssert.Empty(readonlyBridge.AdoptedPaths, "readonly adopted paths");
        TestAssert.Equal(WindowsRepositoryErrorKind.PermissionDenied, readonlyModel.Error?.Kind, "readonly error");
    }

    private static async Task OneDriveAdoptShowsRiskWithoutControllingSync()
    {
        const string path = @"C:\Users\me\OneDrive\Existing";
        RepositoryInitConfirmCoreBridge bridge = new(
            [WindowsRepositoryValidationSamples.OneDriveNonEmptyDirectory(path)]);
        RepositoryAdoptConfirmViewModel model = new(bridge);

        await model.OpenRouteAsync(Route(path));

        TestAssert.True(model.RequiresSyncRiskAcknowledgement, nameof(model.RequiresSyncRiskAcknowledgement));
        TestAssert.False(model.CanAdoptRepository, nameof(model.CanAdoptRepository));
        TestAssert.Equal("Location type: OneDrive", model.LocationTypeText, nameof(model.LocationTypeText));
        TestAssert.Contains("OneDrive sync is controlled outside AreaMatrix", model.RiskText, "risk text");
        TestAssert.Empty(bridge.CloudStatePaths, nameof(bridge.CloudStatePaths));

        model.IsMetadataAcknowledged = true;
        TestAssert.False(model.CanAdoptRepository, "metadata-only acknowledgement");

        model.IsSyncRiskAcknowledged = true;
        TestAssert.True(model.CanAdoptRepository, "all acknowledgements");
    }

    private static WindowsRepositoryRoute Route(string path)
    {
        return new WindowsRepositoryRoute(
            WindowsRepositoryRouteKind.RepositoryAdoptConfirm,
            path,
            WindowsRepositoryValidationSamples.NonEmptyDirectory(path),
            null);
    }
}

internal sealed class RepositoryAdoptConfirmCoreBridge : IWindowsRepositoryCoreBridge
{
    private readonly Queue<WindowsRepositoryValidation> validations;
    private readonly WindowsRepositoryCoreException? adoptError;

    public RepositoryAdoptConfirmCoreBridge(
        IEnumerable<WindowsRepositoryValidation> validations,
        WindowsRepositoryCoreException? adoptError = null)
    {
        this.validations = new Queue<WindowsRepositoryValidation>(validations);
        this.adoptError = adoptError;
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
            : WindowsRepositoryValidationSamples.NonEmptyDirectory(repoPath);
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
        return Task.CompletedTask;
    }

    public Task AdoptExistingRepositoryAsync(
        string repoPath,
        CancellationToken cancellationToken = default)
    {
        AdoptedPaths.Add(repoPath);
        if (adoptError is not null)
        {
            throw adoptError;
        }

        return Task.CompletedTask;
    }
}
