using System;
using System.Collections.Generic;
using System.ComponentModel;
using System.Linq;
using System.Threading.Tasks;
using AreaMatrix.Features.Conflicts;
using AreaMatrix.Features.Onboarding;
using AreaMatrix.Features.Recovery;
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

    public event Action? OpenPlatformDifferencesRequested;

    public event Action<SyncConflictEntryReviewRoute>? OpenSyncConflictReviewRequested;

    public event Action<MissingFileRecoveryRoute>? OpenMissingFileRecoveryRequested;

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

    private void PlatformDifferencesButton_Click(object sender, RoutedEventArgs e)
    {
        OpenPlatformDifferencesRequested?.Invoke();
    }

    private void SyncConflictReviewButton_Click(object sender, RoutedEventArgs e)
    {
        OpenSyncConflictReview(ViewModel?.SyncConflictEntry?.FirstReviewableConflict);
    }

    private void SyncConflictLaterButton_Click(object sender, RoutedEventArgs e)
    {
        ViewModel?.SyncConflictEntry?.DismissBanner();
        RefreshState();
    }

    private async void SyncConflictRetryButton_Click(object sender, RoutedEventArgs e)
    {
        if (ViewModel?.SyncConflictEntry is null)
        {
            return;
        }

        await ViewModel.SyncConflictEntry.RefreshAsync();
        RefreshState();
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

    private void NeedsReviewListView_SelectionChanged(
        object sender,
        SelectionChangedEventArgs e)
    {
        if (refreshingControls)
        {
            return;
        }

        OpenSyncConflictReview(NeedsReviewListView.SelectedItem as SyncConflictEntryConflict);
        NeedsReviewListView.SelectedItem = null;
    }

    private void DetailSyncConflictReviewButton_Click(object sender, RoutedEventArgs e)
    {
        OpenSyncConflictReview(ViewModel?.SelectedFileSyncConflict);
    }

    private void DetailMissingFileRecoveryButton_Click(object sender, RoutedEventArgs e)
    {
        if (ViewModel?.SelectedMissingFileRecoveryRoute is { } route)
        {
            OpenMissingFileRecoveryRequested?.Invoke(route);
        }
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
        RefreshSyncConflictEntry();
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
        RefreshDetailSyncConflict();
        RefreshDetailMissingFileRecovery();
    }

    private void RefreshSyncConflictEntry()
    {
        SyncConflictEntryViewModel? entry = ViewModel?.SyncConflictEntry;
        if (entry is null)
        {
            SyncConflictBanner.Visibility = Visibility.Collapsed;
            NeedsReviewPanel.Visibility = Visibility.Collapsed;
            return;
        }

        refreshingControls = true;
        try
        {
            if (!ReferenceEquals(NeedsReviewListView.ItemsSource, entry.Conflicts))
            {
                NeedsReviewListView.ItemsSource = entry.Conflicts;
            }
        }
        finally
        {
            refreshingControls = false;
        }

        bool hasVisibleState = entry.IsBannerVisible || entry.IsLoading || entry.Error is not null;
        SyncConflictBanner.Visibility = VisibilityFor(hasVisibleState);
        NeedsReviewPanel.Visibility = VisibilityFor(entry.HasConflicts);
        SyncConflictStatusTextBlock.Text = SyncConflictStatusText(entry);
        SyncConflictRetryButton.Visibility = VisibilityFor(entry.Error is not null);
        SyncConflictReviewButton.IsEnabled = entry.FirstReviewableConflict is not null;
        SyncConflictLaterButton.IsEnabled = entry.HasConflicts;
    }

    private void RefreshDetailSyncConflict()
    {
        SyncConflictEntryConflict? conflict = ViewModel?.SelectedFileSyncConflict;
        DetailSyncConflictBanner.Visibility = VisibilityFor(conflict is not null);
        DetailSyncConflictSummaryTextBlock.Text = conflict?.SummaryText ?? string.Empty;
        DetailSyncConflictReviewButton.IsEnabled = ViewModel?.SyncConflictEntry?.ReviewRouteFor(conflict) is not null;
    }

    private void RefreshDetailMissingFileRecovery()
    {
        bool canRecover = ViewModel?.CanOpenMissingFileRecovery == true;
        DetailMissingFileRecoveryBanner.Visibility = VisibilityFor(canRecover);
        DetailMissingFileRecoveryButton.IsEnabled = canRecover;
    }

    private void OpenSyncConflictReview(SyncConflictEntryConflict? conflict)
    {
        if (ViewModel?.SyncConflictEntry?.ReviewRouteFor(conflict) is { } route)
        {
            OpenSyncConflictReviewRequested?.Invoke(route);
        }
    }

    public void ShowSyncConflictReviewRoute(SyncConflictEntryReviewRoute route)
    {
        StatusInfoBar.Title = "Review sync conflict";
        StatusInfoBar.Message = $"{route.PrimaryPath} ({route.ConflictId})";
        StatusInfoBar.Severity = InfoBarSeverity.Warning;
        StatusInfoBar.IsOpen = true;
    }

    private static string SyncConflictStatusText(SyncConflictEntryViewModel entry)
    {
        if (entry.Error is { } error)
        {
            return $"{error.Message}. {error.SuggestedAction}";
        }

        if (entry.HasConflicts && entry.FirstReviewableConflict is null)
        {
            return "Repair index first";
        }

        return entry.StatusText;
    }

    private static Visibility VisibilityFor(bool isVisible)
    {
        return isVisible ? Visibility.Visible : Visibility.Collapsed;
    }
}
