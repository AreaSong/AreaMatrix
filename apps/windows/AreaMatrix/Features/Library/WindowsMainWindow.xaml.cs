using System;
using System.ComponentModel;
using System.Linq;
using System.Threading.Tasks;
using AreaMatrix.Features.Onboarding;
using Microsoft.UI.Xaml;
using Microsoft.UI.Xaml.Controls;
using Microsoft.UI.Xaml.Input;
using Windows.System;

namespace AreaMatrix.Features.Library;

public sealed partial class WindowsMainWindow : UserControl
{
    private bool refreshingControls;

    public WindowsMainWindow()
    {
        InitializeComponent();
        Unloaded += WindowsMainWindow_Unloaded;
    }

    public WindowsMainWindowViewModel? ViewModel
    {
        get => DataContext as WindowsMainWindowViewModel;
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
            }

            RefreshState();
        }
    }

    public async Task OpenRepositoryAsync(WindowsRepositoryRoute route)
    {
        if (ViewModel is null)
        {
            return;
        }

        await ViewModel.OpenRepositoryAsync(route);
        RefreshState();
    }

    private void ViewModel_PropertyChanged(object? sender, PropertyChangedEventArgs e)
    {
        RefreshState();
    }

    private void WindowsMainWindow_Unloaded(object sender, RoutedEventArgs e)
    {
        if (ViewModel is { } model)
        {
            model.PropertyChanged -= ViewModel_PropertyChanged;
        }
    }

    private async void RefreshButton_Click(object sender, RoutedEventArgs e)
    {
        if (ViewModel is null)
        {
            return;
        }

        await ViewModel.RefreshAsync();
        RefreshState();
    }

    private async void SearchButton_Click(object sender, RoutedEventArgs e)
    {
        await RunSearchAsync();
    }

    private async void SearchTextBox_KeyDown(object sender, KeyRoutedEventArgs e)
    {
        if (e.Key != VirtualKey.Enter)
        {
            return;
        }

        e.Handled = true;
        await RunSearchAsync();
    }

    private async void CategoryListView_SelectionChanged(
        object sender,
        SelectionChangedEventArgs e)
    {
        if (ViewModel is null || refreshingControls)
        {
            return;
        }

        await ViewModel.SelectCategoryAsync(CategoryListView.SelectedItem as DesktopCategoryNode);
        SearchTextBox.Text = ViewModel.SearchQuery;
        RefreshState();
    }

    private async void FileListView_SelectionChanged(
        object sender,
        SelectionChangedEventArgs e)
    {
        if (ViewModel is null || refreshingControls)
        {
            return;
        }

        await ViewModel.SelectFileAsync(FileListView.SelectedItem as DesktopFileEntry);
        RefreshState();
    }

    private async Task RunSearchAsync()
    {
        if (ViewModel is null)
        {
            return;
        }

        ViewModel.SearchQuery = SearchTextBox.Text;
        await ViewModel.RunSearchAsync();
        RefreshState();
    }

    private void RefreshState()
    {
        if (ViewModel is null)
        {
            IsEnabled = false;
            return;
        }

        IsEnabled = true;
        RepoNameTextBlock.Text = ViewModel.RepoName;
        RepoPathTextBlock.Text = ViewModel.RepoPath;
        StatusTextBlock.Text = ViewModel.StatusText;
        SnapshotTextBlock.Text = ViewModel.Snapshot.SearchIndexStatus is { } indexStatus
            ? $"Search index: {indexStatus}"
            : $"{ViewModel.Files.Count} visible";

        RefreshButton.IsEnabled = ViewModel.CanRunQuery;
        LoadingProgressRing.Visibility = ViewModel.IsLoading || ViewModel.IsRefreshing
            ? Visibility.Visible
            : Visibility.Collapsed;

        StatusInfoBar.IsOpen = ViewModel.Error is not null;
        StatusInfoBar.Message = ViewModel.Error?.Message ?? string.Empty;
        StatusInfoBar.Severity = ViewModel.Error is null
            ? InfoBarSeverity.Informational
            : InfoBarSeverity.Error;

        RefreshItemsSources();
        RefreshDetail();
    }

    private void RefreshItemsSources()
    {
        if (ViewModel is null)
        {
            return;
        }

        refreshingControls = true;
        try
        {
            if (!ReferenceEquals(CategoryListView.ItemsSource, ViewModel.Categories))
            {
                CategoryListView.ItemsSource = ViewModel.Categories;
            }

            if (!ReferenceEquals(FileListView.ItemsSource, ViewModel.Files))
            {
                FileListView.ItemsSource = ViewModel.Files;
            }

            if (ViewModel.SelectedFile is { } selected)
            {
                FileListView.SelectedItem = ViewModel.Files.FirstOrDefault(file => file.Id == selected.Id);
            }
        }
        finally
        {
            refreshingControls = false;
        }
    }

    private void RefreshDetail()
    {
        DesktopFileEntry? file = ViewModel?.SelectedFile;
        DetailTitleTextBlock.Text = ViewModel?.SelectedFileTitle ?? "No file selected";
        DetailPathTextBlock.Text = ViewModel?.SelectedFilePath ?? string.Empty;
        DetailStatusTextBlock.Text = ViewModel?.SelectedFileStatus ?? string.Empty;
        DetailCategoryTextBlock.Text = file is null ? "Category: -" : $"Category: {file.Category}";
        DetailSizeTextBlock.Text = file is null ? "Size: -" : $"Size: {file.SizeText}";
        DetailUpdatedTextBlock.Text = file is null ? "Updated: -" : $"Updated: {file.UpdatedAtText}";
    }
}
