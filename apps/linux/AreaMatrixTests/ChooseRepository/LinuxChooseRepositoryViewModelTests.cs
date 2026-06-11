using AreaMatrix.Linux.Features.Onboarding;

namespace AreaMatrix.Linux.Tests.ChooseRepository;

public static class LinuxChooseRepositoryViewModelTests
{
    public static async Task RunAllAsync()
    {
        await ExistingRepositoryRoutesToMainWindowAfterValidation();
        await BrowseUsesSystemFolderPickerAndValidatesSelectedPath();
        await BrowseReportsSystemFolderPickerFailures();
        await EmptyDirectoryRoutesToInitConfirmationWithoutInitializing();
        await NonEmptyDirectoryRoutesToAdoptConfirmationWithoutWritingMetadata();
        await NetworkPathRoutesToLocalFolderNoticeBeforeOpenInitOrAdopt();
        await InvalidAndPermissionStatesDisableContinueWithSafeMessages();
        await ManualPathEditClearsPreviousValidationBeforeRechecking();
        await BridgeMapsCoreValidationToLinuxState();
    }

    private static async Task ExistingRepositoryRoutesToMainWindowAfterValidation()
    {
        const string path = "/home/me/AreaMatrix";
        FakeLinuxRepositoryCoreBridge bridge = new(LinuxRepositoryValidationSamples.Initialized(path));
        LinuxChooseRepositoryViewModel model = new(bridge);

        await model.CheckRepositoryPathAsync(path);
        await model.ContinueAsync();

        TestAssert.SequenceEqual([path], bridge.ValidatedPaths, nameof(bridge.ValidatedPaths));
        TestAssert.Empty(bridge.InitializedPaths, nameof(bridge.InitializedPaths));
        TestAssert.Empty(bridge.AdoptedPaths, nameof(bridge.AdoptedPaths));
        TestAssert.Equal(LinuxRepositoryRouteKind.MainWindow, model.Route.Kind, nameof(model.Route.Kind));
        TestAssert.Null(model.Error, nameof(model.Error));
        TestAssert.Equal("Existing AreaMatrix repository", model.StatusText, nameof(model.StatusText));
    }

    private static async Task BrowseUsesSystemFolderPickerAndValidatesSelectedPath()
    {
        const string path = "/home/me/AreaMatrix";
        FakeLinuxFolderPickerCommandRunner runner = new(
            ["zenity"],
            new Dictionary<string, LinuxFolderPickerCommandResult>
            {
                ["zenity"] = new(0, $"{path}\n", string.Empty)
            });
        LinuxSystemFolderPickerAdapter picker = new(
            runner,
            [new LinuxFolderPickerCommand("zenity", ["--file-selection", "--directory"])]);
        FakeLinuxRepositoryCoreBridge bridge = new(LinuxRepositoryValidationSamples.Initialized(path));
        LinuxChooseRepositoryView view = new(new LinuxChooseRepositoryViewModel(bridge), picker);

        await view.BrowseAsync();

        TestAssert.SequenceEqual(["zenity"], runner.RunCommands, "picker commands");
        TestAssert.SequenceEqual([path], bridge.ValidatedPaths, nameof(bridge.ValidatedPaths));
        TestAssert.Equal("Existing AreaMatrix repository", view.ViewModel.StatusText, "status");
    }

    private static async Task BrowseReportsSystemFolderPickerFailures()
    {
        FakeLinuxFolderPickerCommandRunner runner = new(
            [],
            new Dictionary<string, LinuxFolderPickerCommandResult>());
        LinuxSystemFolderPickerAdapter picker = new(
            runner,
            [new LinuxFolderPickerCommand("zenity", ["--file-selection", "--directory"])]);
        FakeLinuxRepositoryCoreBridge bridge = new(
            LinuxRepositoryValidationSamples.Initialized("/home/me/AreaMatrix"));
        LinuxChooseRepositoryView view = new(new LinuxChooseRepositoryViewModel(bridge), picker);

        await view.BrowseAsync();

        TestAssert.Empty(bridge.ValidatedPaths, nameof(bridge.ValidatedPaths));
        TestAssert.Equal(LinuxRepositoryErrorKind.Unavailable, view.ViewModel.Error?.Kind, "picker error kind");
        TestAssert.Contains("No supported Linux folder picker", view.ViewModel.StatusText, "picker error text");
    }

    private static async Task EmptyDirectoryRoutesToInitConfirmationWithoutInitializing()
    {
        const string path = "/home/me/Empty";
        FakeLinuxRepositoryCoreBridge bridge = new(LinuxRepositoryValidationSamples.EmptyDirectory(path));
        LinuxChooseRepositoryViewModel model = new(bridge);

        await model.CheckRepositoryPathAsync(path);
        await model.ContinueAsync();

        TestAssert.SequenceEqual([path], bridge.ValidatedPaths, nameof(bridge.ValidatedPaths));
        TestAssert.Empty(bridge.InitializedPaths, nameof(bridge.InitializedPaths));
        TestAssert.Empty(bridge.AdoptedPaths, nameof(bridge.AdoptedPaths));
        TestAssert.Equal(LinuxRepositoryRouteKind.RepositoryInitConfirm, model.Route.Kind, nameof(model.Route.Kind));
        TestAssert.Equal(LinuxRepositoryInitMode.CreateEmpty, model.LatestValidation?.RecommendedMode, "mode");
        TestAssert.Equal("Empty folder", model.StatusText, nameof(model.StatusText));
    }

    private static async Task NonEmptyDirectoryRoutesToAdoptConfirmationWithoutWritingMetadata()
    {
        const string path = "/home/me/Existing";
        FakeLinuxRepositoryCoreBridge bridge = new(LinuxRepositoryValidationSamples.NonEmptyDirectory(path));
        LinuxChooseRepositoryViewModel model = new(bridge);

        await model.CheckRepositoryPathAsync(path);
        await model.ContinueAsync();

        TestAssert.SequenceEqual([path], bridge.ValidatedPaths, nameof(bridge.ValidatedPaths));
        TestAssert.Empty(bridge.InitializedPaths, nameof(bridge.InitializedPaths));
        TestAssert.Empty(bridge.AdoptedPaths, nameof(bridge.AdoptedPaths));
        TestAssert.Equal(LinuxRepositoryRouteKind.RepositoryAdoptConfirm, model.Route.Kind, nameof(model.Route.Kind));
        TestAssert.Equal(LinuxRepositoryInitMode.AdoptExisting, model.LatestValidation?.RecommendedMode, "mode");
        TestAssert.Equal("Non-empty folder", model.StatusText, nameof(model.StatusText));
    }

    private static async Task NetworkPathRoutesToLocalFolderNoticeBeforeOpenInitOrAdopt()
    {
        const string path = "//server/share/AreaMatrix";
        FakeLinuxRepositoryCoreBridge bridge = new(LinuxRepositoryValidationSamples.NetworkShare(path));
        LinuxChooseRepositoryViewModel model = new(bridge);

        await model.CheckRepositoryPathAsync(path);
        await model.ContinueAsync();

        TestAssert.Equal(LinuxRepositoryRouteKind.LocalFolderNotice, model.Route.Kind, nameof(model.Route.Kind));
        TestAssert.Equal("Network or removable path detected", model.StatusText, nameof(model.StatusText));
        TestAssert.Contains("local folder notice", model.RiskText, nameof(model.RiskText));
        TestAssert.Empty(bridge.InitializedPaths, nameof(bridge.InitializedPaths));
        TestAssert.Empty(bridge.AdoptedPaths, nameof(bridge.AdoptedPaths));
    }

    private static async Task InvalidAndPermissionStatesDisableContinueWithSafeMessages()
    {
        FakeLinuxRepositoryCoreBridge missingBridge = new(LinuxRepositoryValidationSamples.Missing("/home/me/Missing"));
        LinuxChooseRepositoryViewModel missingModel = new(missingBridge);
        await missingModel.CheckRepositoryPathAsync("/home/me/Missing");

        TestAssert.False(missingModel.CanContinue, nameof(missingModel.CanContinue));
        TestAssert.Equal(LinuxRepositoryErrorKind.InvalidPath, missingModel.Error?.Kind, "missing kind");
        TestAssert.Equal("Folder not found", missingModel.StatusText, nameof(missingModel.StatusText));

        FakeLinuxRepositoryCoreBridge fileBridge = new(LinuxRepositoryValidationSamples.SelectedFile("/home/me/file.txt"));
        LinuxChooseRepositoryViewModel fileModel = new(fileBridge);
        await fileModel.CheckRepositoryPathAsync("/home/me/file.txt");

        TestAssert.False(fileModel.CanContinue, nameof(fileModel.CanContinue));
        TestAssert.Equal(LinuxRepositoryErrorKind.SelectedFile, fileModel.Error?.Kind, "file kind");
        TestAssert.Equal("Select a folder, not a file.", fileModel.StatusText, nameof(fileModel.StatusText));

        FakeLinuxRepositoryCoreBridge readonlyBridge = new(LinuxRepositoryValidationSamples.NotWritable("/home/me/readonly"));
        LinuxChooseRepositoryViewModel readonlyModel = new(readonlyBridge);
        await readonlyModel.CheckRepositoryPathAsync("/home/me/readonly");

        TestAssert.False(readonlyModel.CanContinue, nameof(readonlyModel.CanContinue));
        TestAssert.Equal(LinuxRepositoryErrorKind.PermissionDenied, readonlyModel.Error?.Kind, "readonly kind");
        TestAssert.NotContains("sudo", readonlyModel.StatusText, nameof(readonlyModel.StatusText));
        TestAssert.NotContains("chmod", readonlyModel.StatusText, nameof(readonlyModel.StatusText));
    }

    private static async Task ManualPathEditClearsPreviousValidationBeforeRechecking()
    {
        FakeLinuxRepositoryCoreBridge bridge = new(LinuxRepositoryValidationSamples.Initialized("/home/me/AreaMatrix"));
        LinuxChooseRepositoryViewModel model = new(bridge);

        await model.CheckRepositoryPathAsync("/home/me/AreaMatrix");
        model.RepositoryPath = "/home/me/Other";

        TestAssert.Null(model.LatestValidation, nameof(model.LatestValidation));
        TestAssert.Equal(LinuxRepositoryRouteKind.None, model.Route.Kind, nameof(model.Route.Kind));
        TestAssert.False(model.CanContinue, nameof(model.CanContinue));
    }

    private static async Task BridgeMapsCoreValidationToLinuxState()
    {
        CoreRepoPathValidation coreValidation = new(
            "/mnt/share/AreaMatrix",
            Exists: true,
            IsDirectory: true,
            IsReadable: true,
            IsWritable: true,
            IsEmpty: false,
            IsInitialized: false,
            IsInsideAreaMatrix: false,
            IsICloudPath: false,
            IsOneDrivePath: false,
            "NetworkShare",
            IsCaseSensitivePath: false,
            HasUnfinishedScanSession: false,
            "AdoptExisting",
            ["WindowsCaseInsensitive", "NonEmptyDirectory"]);
        LinuxRepositoryValidation validation = coreValidation.ToLinuxValidation();

        TestAssert.Equal(LinuxPlatformPathKind.NetworkShare, validation.PlatformPathKind, "path kind");
        TestAssert.Equal(LinuxRepositoryInitMode.AdoptExisting, validation.RecommendedMode, "mode");
        TestAssert.True(validation.HasIssue(LinuxRepositoryPathIssue.NonEmptyDirectory), "non-empty issue");

        FakeLinuxCoreClient client = new(coreValidation);
        LinuxRepositoryCoreBridge bridge = new(client);
        LinuxRepositoryValidation bridged = await bridge.ValidateRepoPathAsync("/mnt/share/AreaMatrix");

        TestAssert.Equal(LinuxPlatformPathKind.NetworkShare, bridged.PlatformPathKind, "bridged path kind");
        TestAssert.SequenceEqual(["/mnt/share/AreaMatrix"], client.ValidatedPaths, "client validated");

        CoreRepoPathValidation externalCoreValidation = coreValidation with
        {
            RepoPath = "/run/media/me/AreaMatrix",
            PlatformPathKind = "Local",
            IsCaseSensitivePath = true
        };
        LinuxRepositoryValidation externalValidation = externalCoreValidation.ToLinuxValidation();

        TestAssert.Equal(
            LinuxPlatformPathKind.ExternalDrive,
            externalValidation.PlatformPathKind,
            "linux removable mount path kind");
    }

    private sealed class FakeLinuxCoreClient : IAreaMatrixLinuxCoreClient
    {
        private readonly CoreRepoPathValidation validation;

        public FakeLinuxCoreClient(CoreRepoPathValidation validation)
        {
            this.validation = validation;
        }

        public List<string> ValidatedPaths { get; } = [];

        public Task<string> GetVersionAsync(CancellationToken cancellationToken = default)
        {
            cancellationToken.ThrowIfCancellationRequested();
            return Task.FromResult("test-core");
        }

        public Task<CoreRepoPathValidation> ValidateRepoPathAsync(
            string repoPath,
            CancellationToken cancellationToken = default)
        {
            ValidatedPaths.Add(repoPath);
            return Task.FromResult(validation);
        }

        public Task InitRepoAsync(
            string repoPath,
            CoreRepoInitOptions options,
            CancellationToken cancellationToken = default)
        {
            throw new InvalidOperationException("choose-repo tests must not initialize repositories");
        }

        public Task<CoreRepoConfig> LoadConfigAsync(
            string repoPath,
            CancellationToken cancellationToken = default)
        {
            throw new InvalidOperationException("choose-repo tests must not load repository config");
        }

        public Task UpdateConfigAsync(
            string repoPath,
            CoreRepoConfig newConfig,
            CancellationToken cancellationToken = default)
        {
            throw new InvalidOperationException("choose-repo tests must not update repository config");
        }

        public Task<CorePlatformCapabilities> GetPlatformCapabilitiesAsync(
            string platform,
            string appVersion,
            CancellationToken cancellationToken = default)
        {
            throw new InvalidOperationException("choose-repo tests must not read platform capabilities");
        }
    }
}
