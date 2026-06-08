using AreaMatrix.Core;
using AreaMatrix.Features.Library;
using AreaMatrix.Features.Onboarding;
using Microsoft.UI.Xaml;
using System.ComponentModel;

namespace AreaMatrix;

public sealed partial class MainWindow : Window
{
    private readonly LazyAreaMatrixWindowsCoreClient coreClient = new();

    public MainWindow()
    {
        InitializeComponent();
        Title = "AreaMatrix";
        ChooseRepositoryPage.ViewModel = new ChooseRepositoryViewModel(new WindowsRepositoryCoreBridge(coreClient));
        ChooseRepositoryPage.ViewModel.PropertyChanged += ChooseRepositoryViewModel_PropertyChanged;
        WindowsMainWindowPage.ViewModel = new WindowsMainWindowViewModel(
            new DesktopMainQueryCoreBridge(coreClient));
        Closed += MainWindow_Closed;
    }

    private async void ChooseRepositoryViewModel_PropertyChanged(
        object? sender,
        PropertyChangedEventArgs e)
    {
        if (e.PropertyName != nameof(ChooseRepositoryViewModel.Route)
            || ChooseRepositoryPage.ViewModel?.Route.Kind != WindowsRepositoryRouteKind.MainWindow)
        {
            return;
        }

        WindowsRepositoryRoute route = ChooseRepositoryPage.ViewModel.Route;
        ChooseRepositoryPage.Visibility = Visibility.Collapsed;
        WindowsMainWindowPage.Visibility = Visibility.Visible;
        await WindowsMainWindowPage.OpenRepositoryAsync(route);
    }

    private void MainWindow_Closed(object sender, WindowEventArgs args)
    {
        if (ChooseRepositoryPage.ViewModel is { } viewModel)
        {
            viewModel.PropertyChanged -= ChooseRepositoryViewModel_PropertyChanged;
        }

        coreClient.Dispose();
    }
}
