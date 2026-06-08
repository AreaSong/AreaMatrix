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

    public MainWindow()
    {
        InitializeComponent();
        Title = "AreaMatrix";
        repositoryBridge = new WindowsRepositoryCoreBridge(coreClient);
        ChooseRepositoryPage.ViewModel = new ChooseRepositoryViewModel(repositoryBridge);
        ChooseRepositoryPage.ViewModel.PropertyChanged += ChooseRepositoryViewModel_PropertyChanged;
        OneDriveNoticePage.ViewModel = new OneDriveNoticeViewModel(repositoryBridge);
        OneDriveNoticePage.ChooseLocalFolderRequested += OneDriveNoticePage_ChooseLocalFolderRequested;
        OneDriveNoticePage.CloseRequested += OneDriveNoticePage_ChooseLocalFolderRequested;
        WindowsMainWindowPage.ViewModel = new WindowsMainWindowViewModel(
            new DesktopMainQueryCoreBridge(coreClient));
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
            ChooseRepositoryPage.Visibility = Visibility.Collapsed;
            WindowsMainWindowPage.Visibility = Visibility.Collapsed;
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
        WindowsMainWindowPage.Visibility = Visibility.Visible;
        await WindowsMainWindowPage.OpenRepositoryAsync(route);
    }

    private void OneDriveNoticePage_ChooseLocalFolderRequested()
    {
        ChooseRepositoryPage.ViewModel?.ResetRoute();
        OneDriveNoticePage.Visibility = Visibility.Collapsed;
        WindowsMainWindowPage.Visibility = Visibility.Collapsed;
        ChooseRepositoryPage.Visibility = Visibility.Visible;
    }

    private void MainWindow_Closed(object sender, WindowEventArgs args)
    {
        if (ChooseRepositoryPage.ViewModel is { } viewModel)
        {
            viewModel.PropertyChanged -= ChooseRepositoryViewModel_PropertyChanged;
        }

        OneDriveNoticePage.ChooseLocalFolderRequested -= OneDriveNoticePage_ChooseLocalFolderRequested;
        OneDriveNoticePage.CloseRequested -= OneDriveNoticePage_ChooseLocalFolderRequested;
        coreClient.Dispose();
    }
}
