using AreaMatrix.Linux.Features.Onboarding;

namespace AreaMatrix.Linux.Tests.ChooseRepository;

public static class RepositoryAdoptConfirmViewModelTests
{
    public static async Task RunAllAsync()
    {
        await OpeningRouteRefreshesValidationWithoutAdopting();
        await ConfirmationIsRequiredBeforeAdopt();
        await AdoptRepositoryInitializesRevalidatesAndRoutesToMainWindow();
        await AdoptRepositoryFailureStaysOnConfirmation();
        await EmptyOrUnwritableValidationBlocksAdoptAction();
        await NetworkMountAdoptShowsRiskWithoutPermissionAdvice();
    }

    private static async Task OpeningRouteRefreshesValidationWithoutAdopting()
    {
        const string path = "/home/me/Existing";
        FakeLinuxRepositoryCoreBridge bridge = new(LinuxRepositoryValidationSamples.NonEmptyDirectory(path));
        RepositoryAdoptConfirmViewModel model = new(bridge);

        await model.OpenRouteAsync(Route(path));

        TestAssert.SequenceEqual([path], bridge.ValidatedPaths, nameof(bridge.ValidatedPaths));
        TestAssert.Empty(bridge.AdoptedPaths, nameof(bridge.AdoptedPaths));
        TestAssert.Empty(bridge.InitializedPaths, nameof(bridge.InitializedPaths));
        TestAssert.False(model.CanAdoptRepository, nameof(model.CanAdoptRepository));
        TestAssert.Contains("will not move, delete, rename, or overwrite", model.SafetyText, "safety text");
        TestAssert.Contains(".areamatrix", model.MetadataAddText, nameof(model.MetadataAddText));
    }

    private static async Task ConfirmationIsRequiredBeforeAdopt()
    {
        const string path = "/home/me/Existing";
        FakeLinuxRepositoryCoreBridge bridge = new(LinuxRepositoryValidationSamples.NonEmptyDirectory(path));
        RepositoryAdoptConfirmViewModel model = new(bridge);

        await model.OpenRouteAsync(Route(path));
        await model.AdoptRepositoryAsync();

        TestAssert.Empty(bridge.AdoptedPaths, nameof(bridge.AdoptedPaths));
        TestAssert.Contains("Confirm that AreaMatrix will add metadata", model.DisabledReason, "disabled reason");

        model.IsMetadataAcknowledged = true;

        TestAssert.True(model.CanAdoptRepository, nameof(model.CanAdoptRepository));
    }

    private static async Task AdoptRepositoryInitializesRevalidatesAndRoutesToMainWindow()
    {
        const string path = "/home/me/Existing";
        FakeLinuxRepositoryCoreBridge bridge = new(
            [
                LinuxRepositoryValidationSamples.NonEmptyDirectory(path),
                LinuxRepositoryValidationSamples.Initialized(path)
            ]);
        RepositoryAdoptConfirmViewModel model = new(bridge);

        await model.OpenRouteAsync(Route(path));
        model.IsMetadataAcknowledged = true;
        await model.AdoptRepositoryAsync();

        TestAssert.SequenceEqual([path, path], bridge.ValidatedPaths, nameof(bridge.ValidatedPaths));
        TestAssert.SequenceEqual([path], bridge.AdoptedPaths, nameof(bridge.AdoptedPaths));
        TestAssert.Empty(bridge.InitializedPaths, nameof(bridge.InitializedPaths));
        TestAssert.Equal(LinuxRepositoryRouteKind.MainWindow, model.CompletedRoute.Kind, "completed route");
        TestAssert.True(model.CompletedRoute.Validation?.IsInitialized == true, "initialized validation");
        TestAssert.Null(model.Error, nameof(model.Error));
    }

    private static async Task AdoptRepositoryFailureStaysOnConfirmation()
    {
        const string path = "/home/me/readonly";
        FakeLinuxRepositoryCoreBridge bridge = new(
            [LinuxRepositoryValidationSamples.NonEmptyDirectory(path)],
            adoptError: new LinuxRepositoryCoreException(
                LinuxRepositoryErrorKind.PermissionDenied,
                "permission denied",
                path));
        RepositoryAdoptConfirmViewModel model = new(bridge);

        await model.OpenRouteAsync(Route(path));
        model.IsMetadataAcknowledged = true;
        await model.AdoptRepositoryAsync();

        TestAssert.SequenceEqual([path], bridge.AdoptedPaths, nameof(bridge.AdoptedPaths));
        TestAssert.Equal(LinuxRepositoryRouteKind.None, model.CompletedRoute.Kind, "completed route");
        TestAssert.Equal(LinuxRepositoryErrorKind.PermissionDenied, model.Error?.Kind, "error kind");
        TestAssert.Equal("Choose another folder.", model.StatusText, nameof(model.StatusText));
        TestAssert.NotContains("sudo", model.StatusText, nameof(model.StatusText));
        TestAssert.NotContains("chmod", model.StatusText, nameof(model.StatusText));
    }

    private static async Task EmptyOrUnwritableValidationBlocksAdoptAction()
    {
        const string emptyPath = "/home/me/Empty";
        FakeLinuxRepositoryCoreBridge emptyBridge = new(LinuxRepositoryValidationSamples.EmptyDirectory(emptyPath));
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

        const string readonlyPath = "/home/me/readonly";
        FakeLinuxRepositoryCoreBridge readonlyBridge = new(
            LinuxRepositoryValidationSamples.NotWritable(readonlyPath));
        RepositoryAdoptConfirmViewModel readonlyModel = new(readonlyBridge);

        await readonlyModel.OpenRouteAsync(Route(readonlyPath));
        readonlyModel.IsMetadataAcknowledged = true;
        await readonlyModel.AdoptRepositoryAsync();

        TestAssert.False(readonlyModel.CanAdoptRepository, "readonly can adopt");
        TestAssert.Empty(readonlyBridge.AdoptedPaths, "readonly adopted paths");
        TestAssert.Equal(LinuxRepositoryErrorKind.PermissionDenied, readonlyModel.Error?.Kind, "readonly error");
    }

    private static async Task NetworkMountAdoptShowsRiskWithoutPermissionAdvice()
    {
        const string path = "//server/share/Existing";
        FakeLinuxRepositoryCoreBridge bridge = new(LinuxRepositoryValidationSamples.NetworkShare(path));
        RepositoryAdoptConfirmViewModel model = new(bridge);

        await model.OpenRouteAsync(Route(path));

        TestAssert.True(
            model.RequiresLocationRiskAcknowledgement,
            nameof(model.RequiresLocationRiskAcknowledgement));
        TestAssert.False(model.CanAdoptRepository, nameof(model.CanAdoptRepository));
        TestAssert.Equal("Location type: Network mount", model.LocationTypeText, nameof(model.LocationTypeText));
        TestAssert.Contains("Network mounts can become unavailable", model.RiskText, nameof(model.RiskText));
        TestAssert.Contains("Case-insensitive path detected", model.RiskText, "case risk");
        TestAssert.Empty(bridge.PlatformCapabilityRequests, nameof(bridge.PlatformCapabilityRequests));
        TestAssert.NotContains("sudo", model.RiskText, nameof(model.RiskText));
        TestAssert.NotContains("chmod", model.RiskText, nameof(model.RiskText));

        model.IsMetadataAcknowledged = true;
        TestAssert.False(model.CanAdoptRepository, "metadata-only acknowledgement");

        model.IsLocationRiskAcknowledged = true;
        TestAssert.True(model.CanAdoptRepository, "all acknowledgements");
    }

    private static LinuxRepositoryRoute Route(string path)
    {
        return new LinuxRepositoryRoute(
            LinuxRepositoryRouteKind.RepositoryAdoptConfirm,
            path,
            LinuxRepositoryValidationSamples.NonEmptyDirectory(path));
    }
}
