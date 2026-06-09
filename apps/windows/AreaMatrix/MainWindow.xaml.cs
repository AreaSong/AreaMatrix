using AreaMatrix.Core;
using AreaMatrix.Features.Conflicts;
using AreaMatrix.Features.Help;
using AreaMatrix.Features.Import;
using AreaMatrix.Features.Library;
using AreaMatrix.Features.Onboarding;
using Microsoft.UI.Xaml;
using WinRT.Interop;
using System.ComponentModel;

namespace AreaMatrix;

public sealed partial class MainWindow : Window
{
    private readonly LazyAreaMatrixWindowsCoreClient coreClient = new();
    private readonly IWindowsRepositoryCoreBridge repositoryBridge;
    private readonly WindowsWatcherDiagnostics watcherDiagnostics = new();
    private bool oneDriveNoticeOpenedFromMainWindow;

    public MainWindow()
    {
        InitializeComponent();
        Title = "AreaMatrix";
        repositoryBridge = new WindowsRepositoryCoreBridge(coreClient);
        ChooseRepositoryPage.ViewModel = new ChooseRepositoryViewModel(repositoryBridge);
        ChooseRepositoryPage.ViewModel.PropertyChanged += ChooseRepositoryViewModel_PropertyChanged;
        OneDriveNoticePage.ViewModel = new OneDriveNoticeViewModel(repositoryBridge);
        OneDriveNoticePage.ChooseLocalFolderRequested += OneDriveNoticePage_ChooseLocalFolderRequested;
        OneDriveNoticePage.CloseRequested += OneDriveNoticePage_CloseRequested;
        OneDriveNoticePage.ContinueWithOneDriveRequested += OneDriveNoticePage_ContinueWithOneDriveRequested;
        OneDriveNoticePage.OpenWatcherStatusRequested += OneDriveNoticePage_OpenWatcherStatusRequested;
        WindowsMainWindowPage.ViewModel = new WindowsMainWindowViewModel(
            new DesktopMainQueryCoreBridge(coreClient),
            new SyncConflictEntryCoreBridge(coreClient));
        WindowsMainWindowPage.OpenSyncConflictReviewRequested += WindowsMainWindowPage_OpenSyncConflictReviewRequested;
        WindowsMainWindowPage.OpenOneDriveStatusRequested += WindowsMainWindowPage_OpenOneDriveStatusRequested;
        WindowsMainWindowPage.OpenWatcherStatusRequested += WindowsMainWindowPage_OpenWatcherStatusRequested;
        WindowsMainWindowPage.OpenImportRequested += WindowsMainWindowPage_OpenImportRequested;
        WindowsMainWindowPage.OpenImportDroppedSourcesRequested += WindowsMainWindowPage_OpenImportDroppedSourcesRequested;
        WindowsMainWindowPage.OpenPlatformDifferencesRequested += WindowsMainWindowPage_OpenPlatformDifferencesRequested;
        WindowsImportPage.ViewModel = new WindowsImportViewModel(
            new DesktopImportCoreBridge(coreClient, new WindowsImportFileProbe()));
        WindowsImportPage.ParentWindowHandle = WindowNative.GetWindowHandle(this);
        WindowsImportPage.CloseRequested += WindowsImportPage_CloseRequested;
        WatcherStatusPage.ViewModel = new WatcherStatusViewModel(
            new WatcherStatusCoreBridge(coreClient),
            watcherDiagnostics);
        WatcherStatusPage.CloseRequested += WatcherStatusPage_CloseRequested;
        WatcherStatusPage.OpenRescanConfirmRequested += WatcherStatusPage_OpenRescanConfirmRequested;
        PlatformDifferencesPage.ViewModel = new PlatformDifferencesViewModel(
            new PlatformDifferencesCoreBridge(coreClient));
        PlatformDifferencesPage.CloseRequested += PlatformDifferencesPage_CloseRequested;
        RescanConfirmPage.CloseRequested += RescanConfirmPage_CloseRequested;
        Closed += MainWindow_Closed;
    }

    private async void ChooseRepositoryViewModel_PropertyChanged(
        object? sender,
        PropertyChangedEventArgs e)
    {
        if (e.PropertyName != nameof(ChooseRepositoryViewModel.Route)
            || ChooseRepositoryPage.ViewModel?.Route is not { } route)
        {
            return;
        }

        if (route.Kind == WindowsRepositoryRouteKind.OneDriveNotice)
        {
            oneDriveNoticeOpenedFromMainWindow = false;
            ChooseRepositoryPage.Visibility = Visibility.Collapsed;
            WindowsMainWindowPage.Visibility = Visibility.Collapsed;
            WindowsImportPage.Visibility = Visibility.Collapsed;
            WatcherStatusPage.Visibility = Visibility.Collapsed;
            RescanConfirmPage.Visibility = Visibility.Collapsed;
            PlatformDifferencesPage.Visibility = Visibility.Collapsed;
            OneDriveNoticePage.Visibility = Visibility.Visible;
            await OneDriveNoticePage.OpenRouteAsync(route);
            return;
        }

        if (route.Kind != WindowsRepositoryRouteKind.MainWindow)
        {
            return;
        }

        ChooseRepositoryPage.Visibility = Visibility.Collapsed;
        OneDriveNoticePage.Visibility = Visibility.Collapsed;
        WindowsImportPage.Visibility = Visibility.Collapsed;
        WatcherStatusPage.Visibility = Visibility.Collapsed;
        RescanConfirmPage.Visibility = Visibility.Collapsed;
        PlatformDifferencesPage.Visibility = Visibility.Collapsed;
        WindowsMainWindowPage.Visibility = Visibility.Visible;
        await WindowsMainWindowPage.OpenRepositoryAsync(route);
    }

    private void OneDriveNoticePage_ChooseLocalFolderRequested()
    {
        oneDriveNoticeOpenedFromMainWindow = false;
        ChooseRepositoryPage.ViewModel?.ResetRoute();
        OneDriveNoticePage.Visibility = Visibility.Collapsed;
        WindowsMainWindowPage.Visibility = Visibility.Collapsed;
        WindowsImportPage.Visibility = Visibility.Collapsed;
        WatcherStatusPage.Visibility = Visibility.Collapsed;
        RescanConfirmPage.Visibility = Visibility.Collapsed;
        PlatformDifferencesPage.Visibility = Visibility.Collapsed;
        ChooseRepositoryPage.Visibility = Visibility.Visible;
    }

    private void OneDriveNoticePage_CloseRequested()
    {
        if (!oneDriveNoticeOpenedFromMainWindow)
        {
            OneDriveNoticePage_ChooseLocalFolderRequested();
            return;
        }

        oneDriveNoticeOpenedFromMainWindow = false;
        OneDriveNoticePage.Visibility = Visibility.Collapsed;
        WatcherStatusPage.Visibility = Visibility.Collapsed;
        WindowsImportPage.Visibility = Visibility.Collapsed;
        RescanConfirmPage.Visibility = Visibility.Collapsed;
        PlatformDifferencesPage.Visibility = Visibility.Collapsed;
        ChooseRepositoryPage.Visibility = Visibility.Collapsed;
        WindowsMainWindowPage.Visibility = Visibility.Visible;
    }

    private async Task OneDriveNoticePage_ContinueWithOneDriveRequested(WindowsCloudStorageState? state)
    {
        if (ChooseRepositoryPage.ViewModel is not { } viewModel)
        {
            return;
        }

        await viewModel.ContinueAfterOneDriveNoticeAsync(state);
        if (viewModel.Route.Kind is WindowsRepositoryRouteKind.RepositoryInitConfirm
            or WindowsRepositoryRouteKind.RepositoryAdoptConfirm)
        {
            OneDriveNoticePage.Visibility = Visibility.Collapsed;
            WindowsMainWindowPage.Visibility = Visibility.Collapsed;
            WindowsImportPage.Visibility = Visibility.Collapsed;
            WatcherStatusPage.Visibility = Visibility.Collapsed;
            RescanConfirmPage.Visibility = Visibility.Collapsed;
            PlatformDifferencesPage.Visibility = Visibility.Collapsed;
            ChooseRepositoryPage.Visibility = Visibility.Visible;
        }
    }

    private async void WindowsMainWindowPage_OpenOneDriveStatusRequested(WindowsRepositoryRoute route)
    {
        oneDriveNoticeOpenedFromMainWindow = true;
        ChooseRepositoryPage.Visibility = Visibility.Collapsed;
        WindowsMainWindowPage.Visibility = Visibility.Collapsed;
        WindowsImportPage.Visibility = Visibility.Collapsed;
        WatcherStatusPage.Visibility = Visibility.Collapsed;
        RescanConfirmPage.Visibility = Visibility.Collapsed;
        PlatformDifferencesPage.Visibility = Visibility.Collapsed;
        OneDriveNoticePage.Visibility = Visibility.Visible;
        await OneDriveNoticePage.OpenRouteAsync(route);
    }

    private async void WindowsMainWindowPage_OpenWatcherStatusRequested(WindowsRepositoryRoute route)
    {
        OneDriveNoticePage.Visibility = Visibility.Collapsed;
        ChooseRepositoryPage.Visibility = Visibility.Collapsed;
        WindowsMainWindowPage.Visibility = Visibility.Collapsed;
        WindowsImportPage.Visibility = Visibility.Collapsed;
        RescanConfirmPage.Visibility = Visibility.Collapsed;
        PlatformDifferencesPage.Visibility = Visibility.Collapsed;
        WatcherStatusPage.Visibility = Visibility.Visible;
        await WatcherStatusPage.OpenRouteAsync(route);
    }

    private void WindowsMainWindowPage_OpenImportRequested(WindowsRepositoryRoute route)
    {
        ShowImportPage();
        WindowsImportPage.OpenRepository(route.RepoPath);
    }

    private void WindowsMainWindowPage_OpenSyncConflictReviewRequested(SyncConflictEntryReviewRoute route)
    {
        WindowsMainWindowPage.Visibility = Visibility.Visible;
        WindowsMainWindowPage.ShowSyncConflictReviewRoute(route);
    }

    private async void WindowsMainWindowPage_OpenImportDroppedSourcesRequested(
        WindowsRepositoryRoute route,
        IReadOnlyList<string> sourcePaths)
    {
        ShowImportPage();
        await WindowsImportPage.OpenRepositoryWithSourcesAsync(route.RepoPath, sourcePaths);
    }

    private async void WindowsImportPage_CloseRequested(WindowsImportCloseRequest request)
    {
        WindowsImportPage.Visibility = Visibility.Collapsed;
        OneDriveNoticePage.Visibility = Visibility.Collapsed;
        ChooseRepositoryPage.Visibility = Visibility.Collapsed;
        WatcherStatusPage.Visibility = Visibility.Collapsed;
        RescanConfirmPage.Visibility = Visibility.Collapsed;
        PlatformDifferencesPage.Visibility = Visibility.Collapsed;
        WindowsMainWindowPage.Visibility = Visibility.Visible;
        if (request.ImportedFileIds.FirstOrDefault() is > 0 and long selectedFileId)
        {
            await WindowsMainWindowPage.RefreshAndSelectFileAsync(selectedFileId);
        }
    }

    private async void OneDriveNoticePage_OpenWatcherStatusRequested()
    {
        WindowsRepositoryRoute route = OneDriveNoticePage.ViewModel is { } model
            ? new WindowsRepositoryRoute(
                WindowsRepositoryRouteKind.WatcherStatus,
                model.RepositoryPath,
                null,
                null,
                model.CloudState)
            : WindowsRepositoryRoute.None;

        OneDriveNoticePage.Visibility = Visibility.Collapsed;
        ChooseRepositoryPage.Visibility = Visibility.Collapsed;
        WindowsMainWindowPage.Visibility = Visibility.Collapsed;
        WindowsImportPage.Visibility = Visibility.Collapsed;
        RescanConfirmPage.Visibility = Visibility.Collapsed;
        PlatformDifferencesPage.Visibility = Visibility.Collapsed;
        WatcherStatusPage.Visibility = Visibility.Visible;
        await WatcherStatusPage.OpenRouteAsync(route);
    }

    private void WatcherStatusPage_CloseRequested()
    {
        WatcherStatusPage.Visibility = Visibility.Collapsed;
        OneDriveNoticePage.Visibility = Visibility.Collapsed;
        RescanConfirmPage.Visibility = Visibility.Collapsed;
        WindowsImportPage.Visibility = Visibility.Collapsed;
        PlatformDifferencesPage.Visibility = Visibility.Collapsed;
        ChooseRepositoryPage.Visibility = Visibility.Collapsed;
        WindowsMainWindowPage.Visibility = Visibility.Visible;
    }

    private void WatcherStatusPage_OpenRescanConfirmRequested(RescanConfirmRequest request)
    {
        OneDriveNoticePage.Visibility = Visibility.Collapsed;
        ChooseRepositoryPage.Visibility = Visibility.Collapsed;
        WindowsMainWindowPage.Visibility = Visibility.Collapsed;
        WindowsImportPage.Visibility = Visibility.Collapsed;
        WatcherStatusPage.Visibility = Visibility.Collapsed;
        PlatformDifferencesPage.Visibility = Visibility.Collapsed;
        RescanConfirmPage.Visibility = Visibility.Visible;
        RescanConfirmPage.OpenRequest(request);
    }

    private async void WindowsMainWindowPage_OpenPlatformDifferencesRequested()
    {
        PlatformDifferencesPage.ViewModel = new PlatformDifferencesViewModel(
            new PlatformDifferencesCoreBridge(coreClient),
            repositoryPath: WindowsMainWindowPage.ViewModel?.RepoPath);
        ShowPlatformDifferencesPage();
        await PlatformDifferencesPage.OpenAsync();
    }

    private void PlatformDifferencesPage_CloseRequested()
    {
        PlatformDifferencesPage.Visibility = Visibility.Collapsed;
        OneDriveNoticePage.Visibility = Visibility.Collapsed;
        ChooseRepositoryPage.Visibility = Visibility.Collapsed;
        WindowsImportPage.Visibility = Visibility.Collapsed;
        WatcherStatusPage.Visibility = Visibility.Collapsed;
        RescanConfirmPage.Visibility = Visibility.Collapsed;
        WindowsMainWindowPage.Visibility = Visibility.Visible;
    }

    private void RescanConfirmPage_CloseRequested()
    {
        RescanConfirmPage.Visibility = Visibility.Collapsed;
        OneDriveNoticePage.Visibility = Visibility.Collapsed;
        ChooseRepositoryPage.Visibility = Visibility.Collapsed;
        WindowsImportPage.Visibility = Visibility.Collapsed;
        WatcherStatusPage.Visibility = Visibility.Visible;
        WindowsMainWindowPage.Visibility = Visibility.Collapsed;
        PlatformDifferencesPage.Visibility = Visibility.Collapsed;
    }

    private void MainWindow_Closed(object sender, WindowEventArgs args)
    {
        if (ChooseRepositoryPage.ViewModel is { } viewModel)
        {
            viewModel.PropertyChanged -= ChooseRepositoryViewModel_PropertyChanged;
        }

        OneDriveNoticePage.ChooseLocalFolderRequested -= OneDriveNoticePage_ChooseLocalFolderRequested;
        OneDriveNoticePage.CloseRequested -= OneDriveNoticePage_CloseRequested;
        OneDriveNoticePage.ContinueWithOneDriveRequested -= OneDriveNoticePage_ContinueWithOneDriveRequested;
        OneDriveNoticePage.OpenWatcherStatusRequested -= OneDriveNoticePage_OpenWatcherStatusRequested;
        WindowsMainWindowPage.OpenOneDriveStatusRequested -= WindowsMainWindowPage_OpenOneDriveStatusRequested;
        WindowsMainWindowPage.OpenWatcherStatusRequested -= WindowsMainWindowPage_OpenWatcherStatusRequested;
        WindowsMainWindowPage.OpenImportRequested -= WindowsMainWindowPage_OpenImportRequested;
        WindowsMainWindowPage.OpenSyncConflictReviewRequested -= WindowsMainWindowPage_OpenSyncConflictReviewRequested;
        WindowsMainWindowPage.OpenImportDroppedSourcesRequested -= WindowsMainWindowPage_OpenImportDroppedSourcesRequested;
        WindowsMainWindowPage.OpenPlatformDifferencesRequested -= WindowsMainWindowPage_OpenPlatformDifferencesRequested;
        WindowsImportPage.CloseRequested -= WindowsImportPage_CloseRequested;
        WatcherStatusPage.CloseRequested -= WatcherStatusPage_CloseRequested;
        WatcherStatusPage.OpenRescanConfirmRequested -= WatcherStatusPage_OpenRescanConfirmRequested;
        PlatformDifferencesPage.CloseRequested -= PlatformDifferencesPage_CloseRequested;
        RescanConfirmPage.CloseRequested -= RescanConfirmPage_CloseRequested;
        watcherDiagnostics.Dispose();
        coreClient.Dispose();
    }

    private void ShowImportPage()
    {
        OneDriveNoticePage.Visibility = Visibility.Collapsed;
        ChooseRepositoryPage.Visibility = Visibility.Collapsed;
        WindowsMainWindowPage.Visibility = Visibility.Collapsed;
        WatcherStatusPage.Visibility = Visibility.Collapsed;
        RescanConfirmPage.Visibility = Visibility.Collapsed;
        PlatformDifferencesPage.Visibility = Visibility.Collapsed;
        WindowsImportPage.Visibility = Visibility.Visible;
    }

    private void ShowPlatformDifferencesPage()
    {
        OneDriveNoticePage.Visibility = Visibility.Collapsed;
        ChooseRepositoryPage.Visibility = Visibility.Collapsed;
        WindowsMainWindowPage.Visibility = Visibility.Collapsed;
        WindowsImportPage.Visibility = Visibility.Collapsed;
        WatcherStatusPage.Visibility = Visibility.Collapsed;
        RescanConfirmPage.Visibility = Visibility.Collapsed;
        PlatformDifferencesPage.Visibility = Visibility.Visible;
    }
}
