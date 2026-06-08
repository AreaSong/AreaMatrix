using System;
using System.Diagnostics;
using System.ComponentModel;
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

    public event Func<WindowsCloudStorageState?, Task>? ContinueWithOneDriveRequested;

    public event Action? OpenWatcherStatusRequested;

    public OneDriveNoticeViewModel? ViewModel
    {
        get => DataContext as OneDriveNoticeViewModel;
        set
        {
            if (DataContext is OneDriveNoticeViewModel previous)
            {
                previous.PropertyChanged -= ViewModel_PropertyChanged;
            }

            DataContext = value;
            if (value is not null)
            {
                value.PropertyChanged += ViewModel_PropertyChanged;
            }

            UpdateC414Visibility();
        }
    }

    public async Task OpenRouteAsync(WindowsRepositoryRoute route)
    {
        if (ViewModel is null)
        {
            return;
        }

        await ViewModel.LoadRouteAsync(route);
        UpdateC414Visibility();
    }

    private async void ContinueWithOneDriveButton_Click(object sender, RoutedEventArgs e)
    {
        if (ViewModel is null)
        {
            return;
        }

        bool completed = await ViewModel.ContinueWithOneDriveAsync();
        if (completed && ContinueWithOneDriveRequested is { } continueRequested)
        {
            await continueRequested(ViewModel.CloudState);
        }
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

    private void OpenWatcherStatusButton_Click(object sender, RoutedEventArgs e)
    {
        if (ViewModel?.CanOpenWatcherStatus == true)
        {
            OpenWatcherStatusRequested?.Invoke();
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

    private void ViewModel_PropertyChanged(object? sender, PropertyChangedEventArgs e)
    {
        UpdateC414Visibility();
    }

    private void UpdateC414Visibility()
    {
        Visibility confirmationVisibility = ViewModel?.ShouldShowConfirmation == true
            ? Visibility.Visible
            : Visibility.Collapsed;

        RiskConfirmationCheckBox.Visibility = confirmationVisibility;
        ContinueDisabledReasonTextBlock.Visibility = confirmationVisibility;
        ContinueWithOneDriveButton.Visibility = confirmationVisibility;

        bool shouldShowConnectedActions = ViewModel?.ShouldShowConnectedActions == true;
        Visibility connectedActionVisibility = shouldShowConnectedActions
            ? Visibility.Visible
            : Visibility.Collapsed;
        Visibility initialActionVisibility = shouldShowConnectedActions
            ? Visibility.Collapsed
            : Visibility.Visible;

        OpenWatcherStatusButton.Visibility = connectedActionVisibility;
        RetryStatusButton.Visibility = initialActionVisibility;
        ChooseLocalFolderButton.Visibility = initialActionVisibility;
    }
}
