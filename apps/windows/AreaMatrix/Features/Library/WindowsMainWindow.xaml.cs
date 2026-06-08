using System;
using System.Collections.Generic;
using System.ComponentModel;
using System.Linq;
using System.Threading.Tasks;
using AreaMatrix.Features.Onboarding;
using Microsoft.UI.Xaml;
using Microsoft.UI.Xaml.Controls;
using Microsoft.UI.Xaml.Input;
using Windows.ApplicationModel.DataTransfer;
using Windows.Storage;
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

    public event Action<WindowsRepositoryRoute>? OpenOneDriveStatusRequested;

    public event Action<WindowsRepositoryRoute>? OpenWatcherStatusRequested;

    public event Action<WindowsRepositoryRoute>? OpenImportRequested;

    public event Action<WindowsRepositoryRoute, IReadOnlyList<string>>? OpenImportDroppedSourcesRequested;

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

    public async Task RefreshAndSelectFileAsync(long fileId)
    {
        if (ViewModel is null)
        {
            return;
        }

        await ViewModel.RefreshAndSelectFileAsync(fileId);
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

    private void OneDriveStatusButton_Click(object sender, RoutedEventArgs e)
    {
        if (ViewModel?.OneDriveStatusRoute is { } route)
        {
            OpenOneDriveStatusRequested?.Invoke(route);
        }
    }

    private void WatcherStatusButton_Click(object sender, RoutedEventArgs e)
    {
        if (ViewModel?.WatcherStatusRoute is { } route)
        {
            OpenWatcherStatusRequested?.Invoke(route);
        }
    }

    private void ImportButton_Click(object sender, RoutedEventArgs e)
    {
        if (ViewModel?.ImportRoute is { } route)
        {
            OpenImportRequested?.Invoke(route);
        }
    }

    private void MainWindowDrop_DragEnter(object sender, DragEventArgs e)
    {
        ApplyDropState(e);
    }

    private void MainWindowDrop_DragOver(object sender, DragEventArgs e)
    {
        ApplyDropState(e);
    }

    private void MainWindowDrop_DragLeave(object sender, DragEventArgs e)
    {
        DropOverlay.Visibility = Visibility.Collapsed;
    }

    private async void MainWindowDrop_Drop(object sender, DragEventArgs e)
    {
        DropOverlay.Visibility = Visibility.Collapsed;
        if (!CanAcceptDrop(e) || ViewModel?.ImportRoute is not { } route)
        {
            return;
        }

        IReadOnlyList<IStorageItem> items = await e.DataView.GetStorageItemsAsync();
        string[] sourcePaths = items
            .Select(item => item.Path)
            .Where(path => !string.IsNullOrWhiteSpace(path))
            .ToArray();
        if (sourcePaths.Length == 0)
        {
            return;
        }

        OpenImportDroppedSourcesRequested?.Invoke(route, sourcePaths);
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

    private void ApplyDropState(DragEventArgs e)
    {
        if (!CanAcceptDrop(e))
        {
            e.AcceptedOperation = DataPackageOperation.None;
            DropOverlay.Visibility = Visibility.Collapsed;
            return;
        }

        e.AcceptedOperation = DataPackageOperation.Copy;
        e.DragUIOverride.Caption = "Import to AreaMatrix";
        e.DragUIOverride.IsCaptionVisible = true;
        DropOverlay.Visibility = Visibility.Visible;
    }

    private bool CanAcceptDrop(DragEventArgs e)
    {
        return ViewModel?.ImportRoute is not null
            && ViewModel.CanRunQuery
            && e.DataView.Contains(StandardDataFormats.StorageItems);
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
        ImportButton.IsEnabled = ViewModel.CanRunQuery;
        OneDriveStatusButton.IsEnabled = ViewModel.CanOpenOneDriveStatus;
        WatcherStatusButton.IsEnabled = ViewModel.CanOpenWatcherStatus;
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
