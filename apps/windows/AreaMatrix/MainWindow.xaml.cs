using AreaMatrix.Core;
using AreaMatrix.Features.Library;
using AreaMatrix.Features.Onboarding;
using Microsoft.UI.Xaml;
using System.ComponentModel;

namespace AreaMatrix;

public sealed partial class MainWindow : Window
{
    private readonly LazyAreaMatrixWindowsCoreClient coreClient = new();
    private readonly IWindowsRepositoryCoreBridge repositoryBridge;
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
            new DesktopMainQueryCoreBridge(coreClient));
        WindowsMainWindowPage.OpenOneDriveStatusRequested += WindowsMainWindowPage_OpenOneDriveStatusRequested;
        WatcherStatusPage.CloseRequested += WatcherStatusPage_CloseRequested;
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
            WatcherStatusPage.Visibility = Visibility.Collapsed;
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
        WatcherStatusPage.Visibility = Visibility.Collapsed;
        WindowsMainWindowPage.Visibility = Visibility.Visible;
        await WindowsMainWindowPage.OpenRepositoryAsync(route);
    }

    private void OneDriveNoticePage_ChooseLocalFolderRequested()
    {
        oneDriveNoticeOpenedFromMainWindow = false;
        ChooseRepositoryPage.ViewModel?.ResetRoute();
        OneDriveNoticePage.Visibility = Visibility.Collapsed;
        WindowsMainWindowPage.Visibility = Visibility.Collapsed;
        WatcherStatusPage.Visibility = Visibility.Collapsed;
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
            WatcherStatusPage.Visibility = Visibility.Collapsed;
            ChooseRepositoryPage.Visibility = Visibility.Visible;
        }
    }

    private async void WindowsMainWindowPage_OpenOneDriveStatusRequested(WindowsRepositoryRoute route)
    {
        oneDriveNoticeOpenedFromMainWindow = true;
        ChooseRepositoryPage.Visibility = Visibility.Collapsed;
        WindowsMainWindowPage.Visibility = Visibility.Collapsed;
        WatcherStatusPage.Visibility = Visibility.Collapsed;
        OneDriveNoticePage.Visibility = Visibility.Visible;
        await OneDriveNoticePage.OpenRouteAsync(route);
    }

    private void OneDriveNoticePage_OpenWatcherStatusRequested()
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
        WatcherStatusPage.Visibility = Visibility.Visible;
        WatcherStatusPage.OpenRoute(route);
    }

    private void WatcherStatusPage_CloseRequested()
    {
        WatcherStatusPage.Visibility = Visibility.Collapsed;
        OneDriveNoticePage.Visibility = Visibility.Collapsed;
        ChooseRepositoryPage.Visibility = Visibility.Collapsed;
        WindowsMainWindowPage.Visibility = Visibility.Visible;
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
        WatcherStatusPage.CloseRequested -= WatcherStatusPage_CloseRequested;
        coreClient.Dispose();
    }
}
