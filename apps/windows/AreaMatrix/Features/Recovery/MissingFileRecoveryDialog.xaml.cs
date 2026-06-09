using System;
using System.ComponentModel;
using System.Threading.Tasks;
using Microsoft.UI.Xaml;
using Microsoft.UI.Xaml.Controls;
using Windows.Storage;
using Windows.Storage.Pickers;
using WinRT.Interop;

namespace AreaMatrix.Features.Recovery;

public sealed partial class MissingFileRecoveryDialog : UserControl
{
    public MissingFileRecoveryDialog()
    {
        InitializeComponent();
        Unloaded += MissingFileRecoveryDialog_Unloaded;
    }

    public event Action<MissingFileRecoveryReport?>? CloseRequested;

    public nint ParentWindowHandle { get; set; }

    public MissingFileRecoveryViewModel? ViewModel
    {
        get => DataContext as MissingFileRecoveryViewModel;
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

    public async Task OpenRouteAsync(MissingFileRecoveryRoute route)
    {
        if (ViewModel is null)
        {
            return;
        }

        await ViewModel.OpenAsync(route.RepoPath, route.FileId);
        RefreshState();
    }

    private void ViewModel_PropertyChanged(object? sender, PropertyChangedEventArgs e)
    {
        RefreshState();
    }

    private void MissingFileRecoveryDialog_Unloaded(object sender, RoutedEventArgs e)
    {
        if (ViewModel is { } model)
        {
            model.PropertyChanged -= ViewModel_PropertyChanged;
        }
    }

    private async void RelinkButton_Click(object sender, RoutedEventArgs e)
    {
        if (ViewModel is null)
        {
            return;
        }

        StorageFile? file = await PickRelinkFileAsync();
        if (file is null)
        {
            return;
        }

        ViewModel.SelectedRelinkPath = file.Path;
        await ViewModel.RelinkSelectedFileAsync();
        RefreshState();
        CloseAfterSuccessfulChange();
    }

    private async void TryAgainButton_Click(object sender, RoutedEventArgs e)
    {
        if (ViewModel is null)
        {
            return;
        }

        await ViewModel.RefreshAsync();
        RefreshState();
    }

    private void DecideLaterButton_Click(object sender, RoutedEventArgs e)
    {
        CloseRequested?.Invoke(ViewModel?.Report);
    }

    private async void RemoveRecordButton_Click(object sender, RoutedEventArgs e)
    {
        if (ViewModel is null)
        {
            return;
        }

        await ViewModel.RemoveRecordAsync();
        RefreshState();
        CloseAfterSuccessfulChange();
    }

    private async Task<StorageFile?> PickRelinkFileAsync()
    {
        FileOpenPicker picker = new()
        {
            SuggestedStartLocation = PickerLocationId.DocumentsLibrary
        };
        picker.FileTypeFilter.Add("*");
        if (ParentWindowHandle != 0)
        {
            InitializeWithWindow.Initialize(picker, ParentWindowHandle);
        }

        return await picker.PickSingleFileAsync();
    }

    private void CloseAfterSuccessfulChange()
    {
        if (ViewModel?.Report is { Status: MissingFileRecoveryStatus.Relinked or MissingFileRecoveryStatus.RecordRemoved } report)
        {
            CloseRequested?.Invoke(report);
        }
    }

    private void RefreshState()
    {
        if (ViewModel is null)
        {
            IsEnabled = false;
            return;
        }

        IsEnabled = true;
        RelinkButton.IsEnabled = ViewModel.State?.CanLocate == true
            && !ViewModel.IsLoading
            && !ViewModel.IsWorking;
        TryAgainButton.IsEnabled = ViewModel.CanTryAgain;
        RemoveRecordButton.IsEnabled = ViewModel.CanRemoveRecord;
    }
}
