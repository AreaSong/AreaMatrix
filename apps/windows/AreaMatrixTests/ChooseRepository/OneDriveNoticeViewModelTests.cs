using AreaMatrix.Features.Onboarding;

namespace AreaMatrixTests.ChooseRepository;

public static class OneDriveNoticeViewModelTests
{
    public static async Task RunAllAsync()
    {
        await ExistingCloudStateRendersOneDriveStatusWithoutRedetecting();
        await MissingRouteCloudStateDetectsThroughCoreBridge();
        await PermissionDeniedStateMapsToUnknownStatusAndReadableError();
        await RetryStatusCheckUsesCoreBridgeAfterInitialLoad();
        await AcknowledgementRequiresCheckboxAndPersistsThroughCoreBridge();
        await UninitializedNoticeConfirmationDoesNotCallCoreAcknowledgement();
        await ConnectedNoticeStateEnablesWatcherStatusEntryWithoutConfirmation();
    }

    private static async Task ExistingCloudStateRendersOneDriveStatusWithoutRedetecting()
    {
        WindowsRepositoryValidation validation = WindowsRepositoryValidationSamples.OneDriveDirectory(
            @"C:\Users\me\OneDrive\AreaMatrix");
        WindowsCloudStorageState state = WindowsCloudStorageStateSamples.UnacknowledgedOneDrive(validation.RepoPath);
        FakeWindowsRepositoryCoreBridge bridge = new(validation, state);
        OneDriveNoticeViewModel model = new(bridge);

        await model.LoadRouteAsync(new WindowsRepositoryRoute(
            WindowsRepositoryRouteKind.OneDriveNotice,
            validation.RepoPath,
            validation,
            null,
            state));

        TestAssert.Empty(bridge.CloudStatePaths, nameof(bridge.CloudStatePaths));
        TestAssert.Equal("Folder: C:\\Users\\me\\OneDrive\\AreaMatrix", model.FolderText, nameof(model.FolderText));
        TestAssert.Equal("Sync provider: OneDrive", model.SyncProviderText, nameof(model.SyncProviderText));
        TestAssert.Equal("Status: Available", model.StatusText, nameof(model.StatusText));
        TestAssert.Contains("OneDrive path detected", model.StatusSummary, nameof(model.StatusSummary));
        TestAssert.SequenceEqual(
            ["OneDrive SDK is not managed by AreaMatrix.", "Conflict copies may appear later."],
            model.RiskReasons,
            nameof(model.RiskReasons));
    }

    private static async Task MissingRouteCloudStateDetectsThroughCoreBridge()
    {
        WindowsRepositoryValidation validation = WindowsRepositoryValidationSamples.OneDriveDirectory(
            @"C:\Users\me\OneDrive\AreaMatrix");
        FakeWindowsRepositoryCoreBridge bridge = new(validation);
        OneDriveNoticeViewModel model = new(bridge);

        await model.LoadRouteAsync(new WindowsRepositoryRoute(
            WindowsRepositoryRouteKind.OneDriveNotice,
            validation.RepoPath,
            validation,
            null));

        TestAssert.SequenceEqual([validation.RepoPath], bridge.CloudStatePaths, nameof(bridge.CloudStatePaths));
        TestAssert.Equal("Status: Available", model.StatusText, nameof(model.StatusText));
        TestAssert.True(model.CanOpenOneDriveFolder, nameof(model.CanOpenOneDriveFolder));
        TestAssert.Null(model.Error, nameof(model.Error));
    }

    private static async Task PermissionDeniedStateMapsToUnknownStatusAndReadableError()
    {
        WindowsRepositoryValidation validation = WindowsRepositoryValidationSamples.OneDriveDirectory(
            @"C:\Users\me\OneDrive\Locked");
        WindowsCloudStorageState state = PermissionDeniedOneDrive(validation.RepoPath);
        FakeWindowsRepositoryCoreBridge bridge = new(validation, state);
        OneDriveNoticeViewModel model = new(bridge);

        await model.LoadRouteAsync(new WindowsRepositoryRoute(
            WindowsRepositoryRouteKind.OneDriveNotice,
            validation.RepoPath,
            validation,
            null,
            state));

        TestAssert.Equal("Status: Unknown", model.StatusText, nameof(model.StatusText));
        TestAssert.Equal(WindowsRepositoryErrorKind.PermissionDenied, model.Error?.Kind, "error kind");
        TestAssert.Contains("cannot read OneDrive metadata", model.ErrorText, nameof(model.ErrorText));
        TestAssert.Contains("cannot control OneDrive sync timing", model.StatusSummary, nameof(model.StatusSummary));
    }

    private static async Task RetryStatusCheckUsesCoreBridgeAfterInitialLoad()
    {
        WindowsRepositoryValidation validation = WindowsRepositoryValidationSamples.OneDriveDirectory(
            @"C:\Users\me\OneDrive\AreaMatrix");
        FakeWindowsRepositoryCoreBridge bridge = new(validation);
        OneDriveNoticeViewModel model = new(bridge);

        await model.LoadRouteAsync(new WindowsRepositoryRoute(
            WindowsRepositoryRouteKind.OneDriveNotice,
            validation.RepoPath,
            validation,
            null));
        await model.RetryStatusCheckAsync();

        TestAssert.SequenceEqual(
            [validation.RepoPath, validation.RepoPath],
            bridge.CloudStatePaths,
            nameof(bridge.CloudStatePaths));
        TestAssert.Equal("Status: Available", model.StatusText, nameof(model.StatusText));
    }

    private static async Task AcknowledgementRequiresCheckboxAndPersistsThroughCoreBridge()
    {
        WindowsRepositoryValidation validation = WindowsRepositoryValidationSamples.OneDriveDirectory(
            @"C:\Users\me\OneDrive\AreaMatrix");
        WindowsCloudStorageState state = WindowsCloudStorageStateSamples.UnacknowledgedOneDrive(validation.RepoPath);
        FakeWindowsRepositoryCoreBridge bridge = new(validation, state);
        OneDriveNoticeViewModel model = new(bridge);

        await model.LoadRouteAsync(new WindowsRepositoryRoute(
            WindowsRepositoryRouteKind.OneDriveNotice,
            validation.RepoPath,
            validation,
            null,
            state));

        TestAssert.True(model.ShouldShowConfirmation, nameof(model.ShouldShowConfirmation));
        TestAssert.False(model.CanContinueWithOneDrive, nameof(model.CanContinueWithOneDrive));
        TestAssert.Contains(
            "Confirm OneDrive sync risks",
            model.ContinueDisabledReason,
            nameof(model.ContinueDisabledReason));

        model.IsRiskNoticeConfirmed = true;
        bool completed = await model.ContinueWithOneDriveAsync();

        TestAssert.True(completed, nameof(completed));
        TestAssert.SequenceEqual([validation.RepoPath], bridge.AcknowledgedPaths, nameof(bridge.AcknowledgedPaths));
        TestAssert.True(model.CloudState?.NoticeAcknowledged == true, "notice acknowledged");
        TestAssert.Equal(
            WindowsCloudStorageRecommendedAction.None,
            model.CloudState?.RecommendedAction,
            "recommended action");
    }

    private static async Task UninitializedNoticeConfirmationDoesNotCallCoreAcknowledgement()
    {
        WindowsRepositoryValidation validation = WindowsRepositoryValidationSamples.OneDriveEmptyDirectory(
            @"C:\Users\me\OneDrive\Empty");
        WindowsCloudStorageState state = WindowsCloudStorageStateSamples.UnacknowledgedOneDrive(validation.RepoPath);
        FakeWindowsRepositoryCoreBridge bridge = new(validation, state);
        OneDriveNoticeViewModel model = new(bridge);

        await model.LoadRouteAsync(new WindowsRepositoryRoute(
            WindowsRepositoryRouteKind.OneDriveNotice,
            validation.RepoPath,
            validation,
            null,
            state));

        model.IsRiskNoticeConfirmed = true;
        bool completed = await model.ContinueWithOneDriveAsync();

        TestAssert.True(completed, nameof(completed));
        TestAssert.Empty(bridge.AcknowledgedPaths, nameof(bridge.AcknowledgedPaths));
        TestAssert.False(model.CloudState?.NoticeAcknowledged == true, "notice acknowledged");
    }

    private static async Task ConnectedNoticeStateEnablesWatcherStatusEntryWithoutConfirmation()
    {
        WindowsRepositoryValidation validation = WindowsRepositoryValidationSamples.OneDriveDirectory(
            @"C:\Users\me\OneDrive\AreaMatrix");
        WindowsCloudStorageState state = WindowsCloudStorageStateSamples.AcknowledgedOneDrive(validation.RepoPath);
        FakeWindowsRepositoryCoreBridge bridge = new(validation, state);
        OneDriveNoticeViewModel model = new(bridge);

        await model.LoadRouteAsync(new WindowsRepositoryRoute(
            WindowsRepositoryRouteKind.OneDriveNotice,
            validation.RepoPath,
            validation,
            null,
            state));

        TestAssert.False(model.ShouldShowConfirmation, nameof(model.ShouldShowConfirmation));
        TestAssert.True(model.ShouldShowConnectedActions, nameof(model.ShouldShowConnectedActions));
        TestAssert.True(model.CanOpenWatcherStatus, nameof(model.CanOpenWatcherStatus));
        TestAssert.False(model.CanContinueWithOneDrive, nameof(model.CanContinueWithOneDrive));
        TestAssert.Empty(bridge.AcknowledgedPaths, nameof(bridge.AcknowledgedPaths));
    }

    private static WindowsCloudStorageState PermissionDeniedOneDrive(string path)
    {
        return new WindowsCloudStorageState(
            path,
            WindowsCloudStorageProviderKind.OneDrive,
            WindowsCloudStorageRiskLevel.Unknown,
            WindowsCloudPlaceholderState.Unknown,
            WindowsCloudPermissionState.PermissionDenied,
            "OneDrive status is unknown because metadata is unreadable.",
            ["Permission denied while reading OneDrive metadata."],
            WindowsCloudStorageRecommendedAction.ReconnectFolder,
            RequiresNoticeAcknowledgement: true,
            NoticeAcknowledged: false,
            CanRetry: true,
            RequiresReconnect: true);
    }
}
