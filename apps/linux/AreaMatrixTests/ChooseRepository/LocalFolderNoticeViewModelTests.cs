using AreaMatrix.Linux.Features.Onboarding;

namespace AreaMatrix.Linux.Tests.ChooseRepository;

public static class LocalFolderNoticeViewModelTests
{
    public static async Task RunAllAsync()
    {
        await LoadRouteChecksFolderThroughCoreBridge();
        await RiskConfirmationRoutesToAdoptConfirmWithoutInitializing();
        await LocalEmptyFolderRoutesToInitConfirmWithoutCheckbox();
        await ExternalDriveShowsDisconnectWarning();
        await SyncFolderShowsProviderWarningWithoutCloudCapabilityCalls();
        await NotWritableFolderBlocksContinueWithSafeMessage();
        await ChooseAnotherFolderAndOpenFolderAreUserVisibleActions();
    }

    private static async Task LoadRouteChecksFolderThroughCoreBridge()
    {
        const string path = "//server/share/AreaMatrix";
        FakeLinuxRepositoryCoreBridge bridge = new(LinuxRepositoryValidationSamples.NetworkShare(path));
        LocalFolderNoticeViewModel model = new(bridge);

        await model.LoadRouteAsync(new LinuxRepositoryRoute(
            LinuxRepositoryRouteKind.LocalFolderNotice,
            path,
            null));

        TestAssert.SequenceEqual([path], bridge.ValidatedPaths, nameof(bridge.ValidatedPaths));
        TestAssert.Equal($"Folder: {path}", model.FolderText, nameof(model.FolderText));
        TestAssert.Equal("Type: Network mount", model.TypeText, nameof(model.TypeText));
        TestAssert.Equal("Writable: Yes", model.WritableText, nameof(model.WritableText));
        TestAssert.True(model.ShouldShowRiskConfirmation, nameof(model.ShouldShowRiskConfirmation));
        TestAssert.False(model.CanContinue, nameof(model.CanContinue));
        TestAssert.Contains("delay or reorder file events", model.RiskText, nameof(model.RiskText));
    }

    private static async Task RiskConfirmationRoutesToAdoptConfirmWithoutInitializing()
    {
        const string path = "//server/share/AreaMatrix";
        FakeLinuxRepositoryCoreBridge bridge = new(LinuxRepositoryValidationSamples.NetworkShare(path));
        LocalFolderNoticeViewModel model = new(bridge);

        await model.LoadRouteAsync(new LinuxRepositoryRoute(
            LinuxRepositoryRouteKind.LocalFolderNotice,
            path,
            null));
        model.IsRiskNoticeConfirmed = true;
        bool completed = await model.ContinueAsync();

        TestAssert.True(completed, nameof(completed));
        TestAssert.Equal(LinuxRepositoryRouteKind.RepositoryAdoptConfirm, model.Route.Kind, "route");
        TestAssert.Empty(bridge.InitializedPaths, nameof(bridge.InitializedPaths));
        TestAssert.Empty(bridge.AdoptedPaths, nameof(bridge.AdoptedPaths));
    }

    private static async Task LocalEmptyFolderRoutesToInitConfirmWithoutCheckbox()
    {
        const string path = "/home/me/AreaMatrix";
        FakeLinuxRepositoryCoreBridge bridge = new(LinuxRepositoryValidationSamples.EmptyDirectory(path));
        LocalFolderNoticeViewModel model = new(bridge);

        await model.LoadRouteAsync(new LinuxRepositoryRoute(
            LinuxRepositoryRouteKind.LocalFolderNotice,
            path,
            null));
        bool completed = await model.ContinueAsync();

        TestAssert.False(model.ShouldShowRiskConfirmation, nameof(model.ShouldShowRiskConfirmation));
        TestAssert.True(model.CanContinue, nameof(model.CanContinue));
        TestAssert.True(completed, nameof(completed));
        TestAssert.Equal(LinuxRepositoryRouteKind.RepositoryInitConfirm, model.Route.Kind, "route");
        TestAssert.Equal("This is the recommended setup for Linux.", model.StatusText, "status");
    }

    private static async Task ExternalDriveShowsDisconnectWarning()
    {
        const string path = "/run/media/me/AreaMatrix";
        FakeLinuxRepositoryCoreBridge bridge = new(LinuxRepositoryValidationSamples.ExternalDrive(path));
        LocalFolderNoticeViewModel model = new(bridge);

        await model.LoadRouteAsync(new LinuxRepositoryRoute(
            LinuxRepositoryRouteKind.LocalFolderNotice,
            path,
            null));

        TestAssert.Equal("Type: External drive", model.TypeText, nameof(model.TypeText));
        TestAssert.True(model.ShouldShowRiskConfirmation, nameof(model.ShouldShowRiskConfirmation));
        TestAssert.False(model.CanContinue, nameof(model.CanContinue));
        TestAssert.Contains("drive is disconnected", model.RiskText, nameof(model.RiskText));
    }

    private static async Task SyncFolderShowsProviderWarningWithoutCloudCapabilityCalls()
    {
        const string path = "/home/me/Nextcloud/AreaMatrix";
        FakeLinuxRepositoryCoreBridge bridge = new(LinuxRepositoryValidationSamples.ICloudPath(path));
        LocalFolderNoticeViewModel model = new(bridge);

        await model.LoadRouteAsync(new LinuxRepositoryRoute(
            LinuxRepositoryRouteKind.LocalFolderNotice,
            path,
            null));

        TestAssert.Equal("Type: Sync folder", model.TypeText, nameof(model.TypeText));
        TestAssert.True(model.ShouldShowRiskConfirmation, nameof(model.ShouldShowRiskConfirmation));
        TestAssert.Contains("does not manage your sync provider", model.RiskText, nameof(model.RiskText));
        TestAssert.Empty(bridge.InitializedPaths, nameof(bridge.InitializedPaths));
        TestAssert.Empty(bridge.AdoptedPaths, nameof(bridge.AdoptedPaths));
    }

    private static async Task NotWritableFolderBlocksContinueWithSafeMessage()
    {
        const string path = "/home/me/readonly";
        FakeLinuxRepositoryCoreBridge bridge = new(LinuxRepositoryValidationSamples.NotWritable(path));
        LocalFolderNoticeViewModel model = new(bridge);

        await model.LoadRouteAsync(new LinuxRepositoryRoute(
            LinuxRepositoryRouteKind.LocalFolderNotice,
            path,
            null));

        TestAssert.False(model.CanContinue, nameof(model.CanContinue));
        TestAssert.Equal("Writable: No", model.WritableText, nameof(model.WritableText));
        TestAssert.Equal(LinuxRepositoryErrorKind.PermissionDenied, model.Error?.Kind, "error kind");
        TestAssert.NotContains("sudo", model.StatusText, nameof(model.StatusText));
        TestAssert.NotContains("chmod", model.StatusText, nameof(model.StatusText));
    }

    private static async Task ChooseAnotherFolderAndOpenFolderAreUserVisibleActions()
    {
        const string path = "/home/me/AreaMatrix";
        FakeLinuxRepositoryCoreBridge bridge = new(LinuxRepositoryValidationSamples.EmptyDirectory(path));
        RecordingLinuxFolderOpener opener = new();
        LocalFolderNoticeView view = new(new LocalFolderNoticeViewModel(bridge), opener);

        await view.LoadAsync(new LinuxRepositoryRoute(
            LinuxRepositoryRouteKind.LocalFolderNotice,
            path,
            null));
        await view.OpenFolderAsync();
        view.ChooseAnotherFolder();

        TestAssert.SequenceEqual([path], opener.OpenedPaths, nameof(opener.OpenedPaths));
        TestAssert.Equal(LinuxRepositoryRouteKind.ChooseRepository, view.ViewModel.Route.Kind, "choose route");
    }

    private sealed class RecordingLinuxFolderOpener : ILinuxFolderOpener
    {
        public List<string> OpenedPaths { get; } = [];

        public Task OpenFolderAsync(
            string folderPath,
            CancellationToken cancellationToken = default)
        {
            cancellationToken.ThrowIfCancellationRequested();
            OpenedPaths.Add(folderPath);
            return Task.CompletedTask;
        }
    }
}
