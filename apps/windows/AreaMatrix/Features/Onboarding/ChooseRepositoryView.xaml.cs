using System.ComponentModel;
using System.Threading.Tasks;
using Microsoft.UI.Xaml;
using Microsoft.UI.Xaml.Controls;
using Microsoft.UI.Xaml.Input;
using Windows.Storage.Pickers;
using Windows.System;

namespace AreaMatrix.Features.Onboarding;

public sealed partial class ChooseRepositoryView : Page
{
    public ChooseRepositoryView()
    {
        InitializeComponent();
        Unloaded += ChooseRepositoryView_Unloaded;
    }

    public ChooseRepositoryViewModel? ViewModel
    {
        get => DataContext as ChooseRepositoryViewModel;
        set
        {
            if (ViewModel is { } previousModel)
            {
                previousModel.PropertyChanged -= ViewModel_PropertyChanged;
            }

            DataContext = value;
            if (value is not null)
            {
                value.PropertyChanged += ViewModel_PropertyChanged;
                RepositoryFolderTextBox.Text = value.RepositoryPath;
            }

            RefreshState();
        }
    }

    private void ViewModel_PropertyChanged(object? sender, PropertyChangedEventArgs e)
    {
        RefreshState();
    }

    private void ChooseRepositoryView_Unloaded(object sender, RoutedEventArgs e)
    {
        if (ViewModel is { } model)
        {
            model.PropertyChanged -= ViewModel_PropertyChanged;
        }
    }

    private async void RepositoryFolderTextBox_LostFocus(object sender, RoutedEventArgs e)
    {
        await CheckTypedRepositoryPathAsync();
    }

    private async void RepositoryFolderTextBox_KeyDown(object sender, KeyRoutedEventArgs e)
    {
        if (e.Key != VirtualKey.Enter)
        {
            return;
        }

        e.Handled = true;
        await CheckTypedRepositoryPathAsync();
    }

    private void RepositoryFolderTextBox_TextChanged(object sender, TextChangedEventArgs e)
    {
        if (ViewModel is null || RepositoryFolderTextBox.Text == ViewModel.RepositoryPath)
        {
            return;
        }

        ViewModel.RepositoryPath = RepositoryFolderTextBox.Text;
    }

    private async void BrowseButton_Click(object sender, RoutedEventArgs e)
    {
        FolderPicker picker = new();
        picker.FileTypeFilter.Add("*");

        Windows.Storage.StorageFolder? folder = await picker.PickSingleFolderAsync();
        if (folder is null || ViewModel is null)
        {
            return;
        }

        await ViewModel.CheckRepositoryPathAsync(folder.Path);
        RepositoryFolderTextBox.Text = ViewModel.RepositoryPath;
        RefreshState();
    }

    private async void ContinueButton_Click(object sender, RoutedEventArgs e)
    {
        if (ViewModel is null)
        {
            return;
        }

        await ViewModel.ContinueAsync();
        RefreshState();
    }

    private void CancelButton_Click(object sender, RoutedEventArgs e)
    {
        ViewModel?.ResetRoute();
        RefreshState();
    }

    private async Task CheckTypedRepositoryPathAsync()
    {
        if (ViewModel is null)
        {
            return;
        }

        string typedPath = RepositoryFolderTextBox.Text;
        if (string.IsNullOrWhiteSpace(typedPath) && string.IsNullOrWhiteSpace(ViewModel.RepositoryPath))
        {
            RefreshState();
            return;
        }

        await ViewModel.CheckRepositoryPathAsync(typedPath);
        RepositoryFolderTextBox.Text = ViewModel.RepositoryPath;
    }

    private void RefreshState()
    {
        if (ViewModel is null)
        {
            ContinueButton.IsEnabled = false;
            CheckingProgressRing.Visibility = Visibility.Collapsed;
            StatusTextBlock.Text = string.Empty;
            return;
        }

        ContinueButton.IsEnabled = ViewModel.CanContinue;
        CheckingProgressRing.Visibility = ViewModel.IsChecking
            ? Visibility.Visible
            : Visibility.Collapsed;
        StatusTextBlock.Text = ViewModel.StatusText;
    }
}
