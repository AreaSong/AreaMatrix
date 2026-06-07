using AreaMatrix.Core;
using AreaMatrix.Features.Onboarding;
using Microsoft.UI.Xaml;

namespace AreaMatrix;

public sealed partial class MainWindow : Window
{
    private readonly LazyAreaMatrixWindowsCoreClient coreClient = new();

    public MainWindow()
    {
        InitializeComponent();
        Title = "AreaMatrix";
        ChooseRepositoryPage.ViewModel = new ChooseRepositoryViewModel(
            new WindowsRepositoryCoreBridge(coreClient));
        Closed += MainWindow_Closed;
    }

    private void MainWindow_Closed(object sender, WindowEventArgs args)
    {
        coreClient.Dispose();
    }
}
