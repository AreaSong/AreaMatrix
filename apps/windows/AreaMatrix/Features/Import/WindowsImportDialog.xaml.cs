using System;
using System.Collections.Generic;
using System.ComponentModel;
using System.Linq;
using System.Threading.Tasks;
using Microsoft.UI.Xaml;
using Microsoft.UI.Xaml.Controls;
using Microsoft.UI.Xaml.Input;
using WinRT.Interop;
using Windows.ApplicationModel.DataTransfer;
using Windows.Storage;
using Windows.Storage.Pickers;

namespace AreaMatrix.Features.Import;

public sealed partial class WindowsImportDialog : UserControl
{
    private readonly IWindowsImportFileProbe fileProbe = new WindowsImportFileProbe();
    private bool refreshingControls;

    public WindowsImportDialog()
    {
        InitializeComponent();
        Unloaded += WindowsImportDialog_Unloaded;
    }

    public event Action? CloseRequested;

    public nint ParentWindowHandle { get; set; }

    public WindowsImportViewModel? ViewModel
    {
        get => DataContext as WindowsImportViewModel;
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

    public void OpenRepository(string repoPath)
    {
        ViewModel?.OpenRepository(repoPath);
        RefreshState();
    }

    private void ViewModel_PropertyChanged(object? sender, PropertyChangedEventArgs e)
    {
        RefreshState();
    }

    private void WindowsImportDialog_Unloaded(object sender, RoutedEventArgs e)
    {
        if (ViewModel is { } model)
        {
            model.PropertyChanged -= ViewModel_PropertyChanged;
        }
    }

    private void SourcePathsTextBox_TextChanged(object sender, TextChangedEventArgs e)
    {
        if (refreshingControls || ViewModel is null)
        {
            return;
        }

        ViewModel.SourcePathsText = SourcePathsTextBox.Text;
        RefreshState();
    }

    private void TargetCategoryTextBox_TextChanged(object sender, TextChangedEventArgs e)
    {
        if (!refreshingControls && ViewModel is not null)
        {
            ViewModel.TargetCategory = TargetCategoryTextBox.Text;
        }
    }

    private void TargetDirectoryTextBox_TextChanged(object sender, TextChangedEventArgs e)
    {
        if (!refreshingControls && ViewModel is not null)
        {
            ViewModel.TargetDirectory = TargetDirectoryTextBox.Text;
        }
    }

    private void ImportModeComboBox_SelectionChanged(object sender, SelectionChangedEventArgs e)
    {
        if (refreshingControls || ViewModel is null)
        {
            return;
        }

        ViewModel.Mode = ImportModeComboBox.SelectedIndex == 1
            ? DesktopImportMode.Move
            : DesktopImportMode.Copy;
        RefreshState();
    }

    private void DuplicateStrategyComboBox_SelectionChanged(object sender, SelectionChangedEventArgs e)
    {
        if (refreshingControls || ViewModel is null)
        {
            return;
        }

        ViewModel.DuplicateStrategy = DuplicateStrategyComboBox.SelectedIndex switch
        {
            0 => DesktopImportDuplicateStrategy.Skip,
            2 => DesktopImportDuplicateStrategy.Ask,
            _ => DesktopImportDuplicateStrategy.KeepBoth
        };
    }

    private void PreserveFolderStructureCheckBox_Changed(object sender, RoutedEventArgs e)
    {
        if (!refreshingControls && ViewModel is not null)
        {
            ViewModel.PreserveFolderStructure = PreserveFolderStructureCheckBox.IsChecked == true;
        }
    }

    private void MoveConfirmedCheckBox_Changed(object sender, RoutedEventArgs e)
    {
        if (!refreshingControls && ViewModel is not null)
        {
            ViewModel.MoveConfirmed = MoveConfirmedCheckBox.IsChecked == true;
            RefreshState();
        }
    }

    private void AddFilesButton_Click(object sender, RoutedEventArgs e)
    {
        _ = PickFilesAsync();
    }

    private void AddFolderButton_Click(object sender, RoutedEventArgs e)
    {
        _ = PickFolderAsync();
    }

    private async void PreparePreviewButton_Click(object sender, RoutedEventArgs e)
    {
        if (ViewModel is null)
        {
            return;
        }

        await ViewModel.PreparePreviewAsync();
        RefreshState();
    }

    private async void ImportButton_Click(object sender, RoutedEventArgs e)
    {
        if (ViewModel is null)
        {
            return;
        }

        await ViewModel.ImportAsync();
        RefreshState();
    }

    private async void PreviewReplaceButton_Click(object sender, RoutedEventArgs e)
    {
        if (ViewModel is null)
        {
            return;
        }

        await ViewModel.PreviewReplaceAsync();
        RefreshState();
    }

    private async void ApplyReplaceButton_Click(object sender, RoutedEventArgs e)
    {
        if (ViewModel is null)
        {
            return;
        }

        await ViewModel.ApplyReplaceAsync();
        RefreshState();
    }

    private void ReplaceConfirmedCheckBox_Changed(object sender, RoutedEventArgs e)
    {
        if (!refreshingControls && ViewModel is not null)
        {
            ViewModel.ReplaceConfirmed = ReplaceConfirmedCheckBox.IsChecked == true;
            RefreshState();
        }
    }

    private void CancelReplaceButton_Click(object sender, RoutedEventArgs e)
    {
        ViewModel?.CancelReplace();
        RefreshState();
    }

    private void UseCopyInsteadButton_Click(object sender, RoutedEventArgs e)
    {
        ViewModel?.UseCopyInstead();
        RefreshState();
    }

    private void ClearButton_Click(object sender, RoutedEventArgs e)
    {
        ViewModel?.Clear();
        RefreshState();
    }

    private void CancelButton_Click(object sender, RoutedEventArgs e)
    {
        CloseRequested?.Invoke();
    }

    private void ImportDialog_DragOver(object sender, DragEventArgs e)
    {
        e.AcceptedOperation = DataPackageOperation.Copy;
        e.DragUIOverride.Caption = "Import to AreaMatrix";
        e.DragUIOverride.IsCaptionVisible = true;
    }

    private async void ImportDialog_Drop(object sender, DragEventArgs e)
    {
        if (!e.DataView.Contains(StandardDataFormats.StorageItems))
        {
            return;
        }

        IReadOnlyList<IStorageItem> items = await e.DataView.GetStorageItemsAsync();
        AppendSourcePaths(fileProbe.ExpandSources(items.Select(item => item.Path)));
        if (ViewModel is not null)
        {
            await ViewModel.PreparePreviewAsync();
            RefreshState();
        }
    }

    private async Task PickFilesAsync()
    {
        FileOpenPicker picker = new()
        {
            SuggestedStartLocation = PickerLocationId.Downloads
        };
        foreach (string fileType in new[] { ".pdf", ".docx", ".xlsx", ".pptx", ".txt", ".md", ".jpg", ".png", ".zip" })
        {
            picker.FileTypeFilter.Add(fileType);
        }

        InitializePicker(picker);
        IReadOnlyList<StorageFile> files = await picker.PickMultipleFilesAsync();
        AppendSourcePaths(fileProbe.ExpandSources(files.Select(file => file.Path)));
        if (ViewModel is not null && files.Count > 0)
        {
            await ViewModel.PreparePreviewAsync();
            RefreshState();
        }
    }

    private async Task PickFolderAsync()
    {
        FolderPicker picker = new()
        {
            SuggestedStartLocation = PickerLocationId.Downloads
        };
        picker.FileTypeFilter.Add("*");
        InitializePicker(picker);
        StorageFolder? folder = await picker.PickSingleFolderAsync();
        if (folder is null)
        {
            return;
        }

        AppendSourcePaths(fileProbe.ExpandSources([folder.Path]));
        if (ViewModel is not null)
        {
            await ViewModel.PreparePreviewAsync();
            RefreshState();
        }
    }

    private void InitializePicker(object picker)
    {
        if (ParentWindowHandle == 0)
        {
            return;
        }

        InitializeWithWindow.Initialize(picker, ParentWindowHandle);
    }

    private void AppendSourcePaths(IEnumerable<DesktopImportSource> importSources)
    {
        if (ViewModel is null)
        {
            return;
        }

        DesktopImportSource[] existing = ViewModel.SourcePathsText
            .Split(['\r', '\n'], StringSplitOptions.RemoveEmptyEntries | StringSplitOptions.TrimEntries)
            .Select(path => new DesktopImportSource(path))
            .ToArray();
        DesktopImportSource[] incoming = importSources
            .Where(source => !string.IsNullOrWhiteSpace(source.SourcePath))
            .Select(source => source with { SourcePath = source.SourcePath.Trim() })
            .ToArray();
        ViewModel.SetSources(existing.Concat(incoming));
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
        RefreshControlsFromModel();
        SourceSummaryTextBlock.Text = ViewModel.SourceSummaryText;
        MoveConfirmationTextBlock.Text = ViewModel.MoveConfirmationText;
        MovePreflightInfoBar.Message = ViewModel.MovePreflightText;
        MovePreflightInfoBar.Severity = ViewModel.MovePreflight.CanMove
            ? InfoBarSeverity.Success
            : InfoBarSeverity.Warning;
        ProgressTextBlock.Text = ViewModel.StatusText;
        ImportButton.IsEnabled = ViewModel.CanImport;
        PreviewReplaceButton.IsEnabled = ViewModel.CanPreviewReplace;
        ApplyReplaceButton.IsEnabled = ViewModel.CanApplyReplace;
        PreparePreviewButton.IsEnabled = ViewModel.CanPrepare;
        ProgressRing.Visibility = ViewModel.IsPreparing || ViewModel.IsImporting
            ? Visibility.Visible
            : Visibility.Collapsed;
        MoveConfirmationSection.Visibility = ViewModel.RequiresMoveConfirmation
            ? Visibility.Visible
            : Visibility.Collapsed;
        PreserveFolderStructureCheckBox.Visibility = ViewModel.HasFolderSources
            ? Visibility.Visible
            : Visibility.Collapsed;
        ResultsSection.Visibility = ViewModel.Results.Count > 0
            ? Visibility.Visible
            : Visibility.Collapsed;
        ReplaceConfirmationSection.Visibility = ViewModel.HasNameConflicts || ViewModel.HasPendingReplaceConfirmation
            ? Visibility.Visible
            : Visibility.Collapsed;
        ReplaceInfoBar.Message = ViewModel.ReplaceStatusText;
        ReplaceInfoBar.Severity = ViewModel.PendingReplaceConfirmation?.CanConfirm == true
            ? InfoBarSeverity.Warning
            : InfoBarSeverity.Informational;
        ReplaceExistingPathTextBlock.Text = ViewModel.PendingReplaceConfirmation?.ExistingPath ?? string.Empty;
        ReplaceIncomingPathTextBlock.Text = ViewModel.PendingReplaceConfirmation?.IncomingPath ?? string.Empty;
        ReplaceTargetPathTextBlock.Text = ViewModel.PendingReplaceConfirmation is { } confirmation
            ? $"Target: {confirmation.TargetPath}"
            : string.Empty;
        ResultSummaryTextBlock.Text = ViewModel.ResultSummaryText;
        PreviewListView.ItemsSource = ViewModel.PreviewItems;
        ResultsListView.ItemsSource = ViewModel.Results;
        StatusInfoBar.IsOpen = ViewModel.Error is not null;
        StatusInfoBar.Severity = ViewModel.Error is null ? InfoBarSeverity.Informational : InfoBarSeverity.Error;
        StatusInfoBar.Message = ViewModel.Error?.Message ?? string.Empty;
    }

    private void RefreshControlsFromModel()
    {
        refreshingControls = true;
        try
        {
            if (SourcePathsTextBox.Text != ViewModel?.SourcePathsText)
            {
                SourcePathsTextBox.Text = ViewModel?.SourcePathsText ?? string.Empty;
            }

            TargetDirectoryTextBox.Text = ViewModel?.TargetDirectory ?? string.Empty;
            TargetCategoryTextBox.Text = ViewModel?.TargetCategory ?? string.Empty;
            ImportModeComboBox.SelectedIndex = ViewModel?.Mode == DesktopImportMode.Move ? 1 : 0;
            DuplicateStrategyComboBox.SelectedIndex = ViewModel?.DuplicateStrategy switch
            {
                DesktopImportDuplicateStrategy.KeepBoth => 1,
                DesktopImportDuplicateStrategy.Ask => 2,
                _ => 0
            };
            PreserveFolderStructureCheckBox.IsChecked = ViewModel?.PreserveFolderStructure == true;
            MoveConfirmedCheckBox.IsChecked = ViewModel?.MoveConfirmed == true;
            ReplaceConfirmedCheckBox.IsChecked = ViewModel?.ReplaceConfirmed == true;
        }
        finally
        {
            refreshingControls = false;
        }
    }
}
