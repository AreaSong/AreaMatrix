using System;
using System.Diagnostics;
using System.Threading.Tasks;
using Microsoft.UI.Xaml;
using Microsoft.UI.Xaml.Controls;

namespace AreaMatrix.Features.Onboarding;

public sealed partial class OneDriveNoticeDialog : UserControl
{
    public OneDriveNoticeDialog()
    {
        InitializeComponent();
    }

    public event Action? ChooseLocalFolderRequested;

    public event Action? CloseRequested;

    public OneDriveNoticeViewModel? ViewModel
    {
        get => DataContext as OneDriveNoticeViewModel;
        set => DataContext = value;
    }

    public async Task OpenRouteAsync(WindowsRepositoryRoute route)
    {
        if (ViewModel is null)
        {
            return;
        }

        await ViewModel.LoadRouteAsync(route);
    }

    private async void RetryStatusButton_Click(object sender, RoutedEventArgs e)
    {
        if (ViewModel is null)
        {
            return;
        }

        await ViewModel.RetryStatusCheckAsync();
    }

    private void OpenOneDriveFolderButton_Click(object sender, RoutedEventArgs e)
    {
        if (ViewModel is null || string.IsNullOrWhiteSpace(ViewModel.RepositoryPath))
        {
            return;
        }

        try
        {
            Process.Start(new ProcessStartInfo
            {
                FileName = ViewModel.RepositoryPath,
                UseShellExecute = true
            });
        }
        catch (Exception exception)
        {
            ViewModel.ReportOpenFolderError(exception);
        }
    }

    private void ChooseLocalFolderButton_Click(object sender, RoutedEventArgs e)
    {
        ChooseLocalFolderRequested?.Invoke();
    }

    private void CloseButton_Click(object sender, RoutedEventArgs e)
    {
        CloseRequested?.Invoke();
    }
}
