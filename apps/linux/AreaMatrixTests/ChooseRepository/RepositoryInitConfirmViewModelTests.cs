using AreaMatrix.Linux.Features.Onboarding;

namespace AreaMatrix.Linux.Tests.ChooseRepository;

public static class RepositoryInitConfirmViewModelTests
{
    public static async Task RunAllAsync()
    {
        await OpeningRouteRefreshesValidationWithoutWritingMetadata();
        await CreateRepositoryInitializesRevalidatesAndRoutesToMainWindow();
        await CreateRepositoryFailureStaysOnConfirmation();
        await NonEmptyOrUnwritableValidationBlocksCreateAction();
        await LinuxNetworkMountShowsRiskWithoutPermissionAdvice();
    }

    private static async Task OpeningRouteRefreshesValidationWithoutWritingMetadata()
    {
        const string path = "/home/me/Empty";
        FakeLinuxRepositoryCoreBridge bridge = new(LinuxRepositoryValidationSamples.EmptyDirectory(path));
        RepositoryInitConfirmViewModel model = new(bridge);

        await model.OpenRouteAsync(Route(path));

        TestAssert.SequenceEqual([path], bridge.ValidatedPaths, nameof(bridge.ValidatedPaths));
        TestAssert.Empty(bridge.InitializedPaths, nameof(bridge.InitializedPaths));
        TestAssert.Empty(bridge.AdoptedPaths, nameof(bridge.AdoptedPaths));
        TestAssert.True(model.CanCreateRepository, nameof(model.CanCreateRepository));
        TestAssert.Contains(".areamatrix", model.SafetyText, nameof(model.SafetyText));
        TestAssert.Contains("No existing files", model.NoOverwriteText, nameof(model.NoOverwriteText));
    }

    private static async Task CreateRepositoryInitializesRevalidatesAndRoutesToMainWindow()
    {
        const string path = "/home/me/Empty";
        FakeLinuxRepositoryCoreBridge bridge = new(
            [
                LinuxRepositoryValidationSamples.EmptyDirectory(path),
                LinuxRepositoryValidationSamples.Initialized(path)
            ]);
        RepositoryInitConfirmViewModel model = new(bridge);

        await model.OpenRouteAsync(Route(path));
        await model.CreateRepositoryAsync();

        TestAssert.SequenceEqual([path, path], bridge.ValidatedPaths, nameof(bridge.ValidatedPaths));
        TestAssert.SequenceEqual([path], bridge.InitializedPaths, nameof(bridge.InitializedPaths));
        TestAssert.Empty(bridge.AdoptedPaths, nameof(bridge.AdoptedPaths));
        TestAssert.Equal(LinuxRepositoryRouteKind.MainWindow, model.CompletedRoute.Kind, "completed route");
        TestAssert.True(model.CompletedRoute.Validation?.IsInitialized == true, "initialized validation");
        TestAssert.Null(model.Error, nameof(model.Error));
    }

    private static async Task CreateRepositoryFailureStaysOnConfirmation()
    {
        const string path = "/home/me/readonly";
        FakeLinuxRepositoryCoreBridge bridge = new(
            [LinuxRepositoryValidationSamples.EmptyDirectory(path)],
            initializeError: new LinuxRepositoryCoreException(
                LinuxRepositoryErrorKind.PermissionDenied,
                "permission denied",
                path));
        RepositoryInitConfirmViewModel model = new(bridge);

        await model.OpenRouteAsync(Route(path));
        await model.CreateRepositoryAsync();

        TestAssert.SequenceEqual([path], bridge.InitializedPaths, nameof(bridge.InitializedPaths));
        TestAssert.Equal(LinuxRepositoryRouteKind.None, model.CompletedRoute.Kind, "completed route");
        TestAssert.Equal(LinuxRepositoryErrorKind.PermissionDenied, model.Error?.Kind, "error kind");
        TestAssert.Equal("Choose another folder.", model.StatusText, nameof(model.StatusText));
        TestAssert.NotContains("sudo", model.StatusText, nameof(model.StatusText));
        TestAssert.NotContains("chmod", model.StatusText, nameof(model.StatusText));
    }

    private static async Task NonEmptyOrUnwritableValidationBlocksCreateAction()
    {
        const string nonEmptyPath = "/home/me/Existing";
        FakeLinuxRepositoryCoreBridge nonEmptyBridge = new(
            LinuxRepositoryValidationSamples.NonEmptyDirectory(nonEmptyPath));
        RepositoryInitConfirmViewModel nonEmptyModel = new(nonEmptyBridge);

        await nonEmptyModel.OpenRouteAsync(Route(nonEmptyPath));
        await nonEmptyModel.CreateRepositoryAsync();

        TestAssert.False(nonEmptyModel.CanCreateRepository, "non-empty can create");
        TestAssert.Empty(nonEmptyBridge.InitializedPaths, "non-empty initialized paths");
        TestAssert.Equal(
            "This folder is not eligible for empty repository creation.",
            nonEmptyModel.DisabledReason,
            "non-empty disabled reason");

        const string readonlyPath = "/home/me/readonly";
        FakeLinuxRepositoryCoreBridge readonlyBridge = new(
            LinuxRepositoryValidationSamples.NotWritable(readonlyPath));
        RepositoryInitConfirmViewModel readonlyModel = new(readonlyBridge);

        await readonlyModel.OpenRouteAsync(Route(readonlyPath));
        await readonlyModel.CreateRepositoryAsync();

        TestAssert.False(readonlyModel.CanCreateRepository, "readonly can create");
        TestAssert.Empty(readonlyBridge.InitializedPaths, "readonly initialized paths");
        TestAssert.Equal(LinuxRepositoryErrorKind.PermissionDenied, readonlyModel.Error?.Kind, "readonly error");
    }

    private static async Task LinuxNetworkMountShowsRiskWithoutPermissionAdvice()
    {
        const string path = "//server/share/Empty";
        FakeLinuxRepositoryCoreBridge bridge = new(new LinuxRepositoryValidation(
            path,
            Exists: true,
            IsDirectory: true,
            IsReadable: true,
            IsWritable: true,
            IsEmpty: true,
            IsInitialized: false,
            IsInsideAreaMatrix: false,
            IsICloudPath: false,
            IsOneDrivePath: false,
            LinuxPlatformPathKind.NetworkShare,
            IsCaseSensitivePath: false,
            HasUnfinishedScanSession: false,
            LinuxRepositoryInitMode.CreateEmpty,
            []));
        RepositoryInitConfirmViewModel model = new(bridge);

        await model.OpenRouteAsync(Route(path));

        TestAssert.True(model.CanCreateRepository, nameof(model.CanCreateRepository));
        TestAssert.Equal("Type: Network mount", model.PathTypeText, nameof(model.PathTypeText));
        TestAssert.Contains("Network mounts can become unavailable", model.RiskText, nameof(model.RiskText));
        TestAssert.Contains("Case-insensitive path detected", model.RiskText, "case risk");
        TestAssert.NotContains("sudo", model.RiskText, nameof(model.RiskText));
        TestAssert.NotContains("chmod", model.RiskText, nameof(model.RiskText));
    }

    private static LinuxRepositoryRoute Route(string path)
    {
        return new LinuxRepositoryRoute(
            LinuxRepositoryRouteKind.RepositoryInitConfirm,
            path,
            LinuxRepositoryValidationSamples.EmptyDirectory(path));
    }
}
