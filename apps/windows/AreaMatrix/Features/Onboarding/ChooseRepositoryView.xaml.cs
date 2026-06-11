using System;
using System.Collections.Generic;
using System.ComponentModel;
using System.Linq;
using System.Threading.Tasks;
using Microsoft.UI.Xaml;
using Microsoft.UI.Xaml.Controls;
using Microsoft.UI.Xaml.Input;
using Windows.ApplicationModel.DataTransfer;
using Windows.Storage.Pickers;
using Windows.System;

namespace AreaMatrix.Features.Onboarding;

public sealed partial class ChooseRepositoryView : Page
{
    private readonly List<WindowsRecentRepository> recentRepositories = [];

    public ChooseRepositoryView()
    {
        InitializeComponent();
        Unloaded += ChooseRepositoryView_Unloaded;
    }

    public event Action<WindowsRecentRepository>? RecentRepositoryRemoved;

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

    public void SetRecentRepositories(IEnumerable<WindowsRecentRepository> repositories)
    {
        recentRepositories.Clear();
        recentRepositories.AddRange(repositories);
        RefreshRecentRepositories();
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

        await CheckRepositoryPathValueAsync(folder.Path);
    }

    private async void PastePathFromClipboard_Click(object sender, RoutedEventArgs e)
    {
        if (ViewModel is null)
        {
            return;
        }

        DataPackageView clipboardContent = Clipboard.GetContent();
        if (!clipboardContent.Contains(StandardDataFormats.Text))
        {
            return;
        }

        string clipboardPath = await clipboardContent.GetTextAsync();
        if (string.IsNullOrWhiteSpace(clipboardPath))
        {
            return;
        }

        await CheckRepositoryPathValueAsync(clipboardPath);
        RepositoryFolderTextBox.Focus(FocusState.Programmatic);
    }

    private async void RecentRepositoriesListView_SelectionChanged(
        object sender,
        SelectionChangedEventArgs e)
    {
        if (ViewModel is null || RecentRepositoriesListView.SelectedItem is not WindowsRecentRepository recent)
        {
            return;
        }

        RecentRepositoriesListView.SelectedItem = null;
        await CheckRepositoryPathValueAsync(recent.RepoPath);
    }

    private void RemoveRecentRepositoryButton_Click(object sender, RoutedEventArgs e)
    {
        if (sender is not FrameworkElement { DataContext: WindowsRecentRepository recent })
        {
            return;
        }

        recentRepositories.RemoveAll(item => item.RepoPath == recent.RepoPath);
        RecentRepositoryRemoved?.Invoke(recent);
        RefreshRecentRepositories();
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

        await CheckRepositoryPathValueAsync(typedPath);
    }

    private async Task CheckRepositoryPathValueAsync(string path)
    {
        if (ViewModel is null)
        {
            return;
        }

        await ViewModel.CheckRepositoryPathAsync(path);
        RepositoryFolderTextBox.Text = ViewModel.RepositoryPath;
        RefreshState();
    }

    private void RefreshRecentRepositories()
    {
        RecentRepositoriesListView.ItemsSource = null;
        RecentRepositoriesListView.ItemsSource = recentRepositories.ToList();
        RecentRepositoriesSection.Visibility = recentRepositories.Count > 0
            ? Visibility.Visible
            : Visibility.Collapsed;
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

        if (ViewModel.Error is not null)
        {
            RepositoryFolderTextBox.Focus(FocusState.Programmatic);
        }
    }
}
