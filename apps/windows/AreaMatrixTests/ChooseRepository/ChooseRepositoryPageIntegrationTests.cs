using AreaMatrix.Features.Onboarding;

namespace AreaMatrixTests.ChooseRepository;

public static class ChooseRepositoryPageIntegrationTests
{
    public static async Task RunAllAsync()
    {
        await OneDriveEmptyDirectoryRoutesToNoticeBeforeInit();
        await ConfirmedOneDriveEmptyDirectoryReturnsToInitConfirmation();
        await OneDriveNonEmptyDirectoryRoutesToNoticeBeforeAdopt();
        await NotWritableDirectoryBlocksContinueBeforeRouting();
        RecentRepositoryStatusReasonsMatchPageSpec();
    }

    private static async Task OneDriveEmptyDirectoryRoutesToNoticeBeforeInit()
    {
        FakeWindowsRepositoryCoreBridge bridge = new(
            WindowsRepositoryValidationSamples.OneDriveEmptyDirectory(@"C:\Users\me\OneDrive\Empty"));
        ChooseRepositoryViewModel model = new(bridge);

        await model.CheckRepositoryPathAsync(@"C:\Users\me\OneDrive\Empty");
        await model.ContinueAsync();

        TestAssert.SequenceEqual([@"C:\Users\me\OneDrive\Empty"], bridge.ValidatedPaths, "validated paths");
        TestAssert.SequenceEqual([@"C:\Users\me\OneDrive\Empty"], bridge.CloudStatePaths, "cloud state paths");
        TestAssert.Empty(bridge.InitializedPaths, nameof(bridge.InitializedPaths));
        TestAssert.Equal(WindowsRepositoryRouteKind.OneDriveNotice, model.Route.Kind, nameof(model.Route.Kind));
        TestAssert.Equal(
            WindowsRepositoryInitMode.CreateEmpty,
            model.Route.Validation?.RecommendedMode,
            "original route mode");
    }

    private static async Task ConfirmedOneDriveEmptyDirectoryReturnsToInitConfirmation()
    {
        const string path = @"C:\Users\me\OneDrive\Empty";
        FakeWindowsRepositoryCoreBridge bridge = new(WindowsRepositoryValidationSamples.OneDriveEmptyDirectory(path));
        ChooseRepositoryViewModel model = new(bridge);

        await model.CheckRepositoryPathAsync(path);
        await model.ContinueAsync();
        await model.ContinueAfterOneDriveNoticeAsync(model.Route.CloudStorageState);

        TestAssert.Empty(bridge.AcknowledgedPaths, nameof(bridge.AcknowledgedPaths));
        TestAssert.Empty(bridge.InitializedPaths, nameof(bridge.InitializedPaths));
        TestAssert.Equal(WindowsRepositoryRouteKind.RepositoryInitConfirm, model.Route.Kind, nameof(model.Route.Kind));
        TestAssert.Equal(
            WindowsRepositoryInitMode.CreateEmpty,
            model.Route.Validation?.RecommendedMode,
            "original route mode");
    }

    private static async Task OneDriveNonEmptyDirectoryRoutesToNoticeBeforeAdopt()
    {
        FakeWindowsRepositoryCoreBridge bridge = new(
            WindowsRepositoryValidationSamples.OneDriveNonEmptyDirectory(@"C:\Users\me\OneDrive\Existing"));
        ChooseRepositoryViewModel model = new(bridge);

        await model.CheckRepositoryPathAsync(@"C:\Users\me\OneDrive\Existing");
        await model.ContinueAsync();

        TestAssert.Empty(bridge.AdoptedPaths, nameof(bridge.AdoptedPaths));
        TestAssert.Equal(WindowsRepositoryRouteKind.OneDriveNotice, model.Route.Kind, nameof(model.Route.Kind));
        TestAssert.Equal(
            WindowsRepositoryInitMode.AdoptExisting,
            model.Route.Validation?.RecommendedMode,
            "original route mode");
    }

    private static async Task NotWritableDirectoryBlocksContinueBeforeRouting()
    {
        FakeWindowsRepositoryCoreBridge bridge = new(
            WindowsRepositoryValidationSamples.NotWritable(@"C:\Repos\Readonly"));
        ChooseRepositoryViewModel model = new(bridge);

        await model.CheckRepositoryPathAsync(@"C:\Repos\Readonly");
        await model.ContinueAsync();

        TestAssert.False(model.CanContinue, nameof(model.CanContinue));
        TestAssert.Equal(WindowsRepositoryRouteKind.None, model.Route.Kind, nameof(model.Route.Kind));
        TestAssert.Equal(WindowsRepositoryErrorKind.PermissionDenied, model.Error?.Kind, "error kind");
        TestAssert.Empty(bridge.LoadedConfigPaths, nameof(bridge.LoadedConfigPaths));
        TestAssert.Empty(bridge.InitializedPaths, nameof(bridge.InitializedPaths));
        TestAssert.Empty(bridge.AdoptedPaths, nameof(bridge.AdoptedPaths));
    }

    private static void RecentRepositoryStatusReasonsMatchPageSpec()
    {
        TestAssert.Equal(
            "Missing",
            Recent(WindowsRecentRepositoryStatus.Missing).StatusReason,
            "missing recent status");
        TestAssert.Equal(
            "Permission denied",
            Recent(WindowsRecentRepositoryStatus.PermissionDenied).StatusReason,
            "permission recent status");
        TestAssert.Equal(
            "Drive disconnected",
            Recent(WindowsRecentRepositoryStatus.DriveDisconnected).StatusReason,
            "drive recent status");
    }

    private static WindowsRecentRepository Recent(WindowsRecentRepositoryStatus status)
    {
        return new WindowsRecentRepository(
            "AreaMatrix",
            @"C:\Repos\AreaMatrix",
            "Opened today",
            status);
    }
}
