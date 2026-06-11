using System;
using System.ComponentModel;
using System.Threading.Tasks;
using AreaMatrix.Features.Onboarding;
using Microsoft.UI.Xaml;
using Microsoft.UI.Xaml.Controls;

namespace AreaMatrix.Features.Library;

public sealed partial class WatcherStatusView : UserControl
{
    public WatcherStatusView()
    {
        InitializeComponent();
        Unloaded += WatcherStatusView_Unloaded;
    }

    public event Action? CloseRequested;

    public event Action<RescanConfirmRequest>? OpenRescanConfirmRequested;

    public WindowsRepositoryRoute? Route { get; private set; }

    public WatcherStatusViewModel? ViewModel
    {
        get => DataContext as WatcherStatusViewModel;
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

    public async void OpenRoute(WindowsRepositoryRoute route)
    {
        await OpenRouteAsync(route);
    }

    public async Task OpenRouteAsync(WindowsRepositoryRoute route)
    {
        Route = route;
        if (ViewModel is not null)
        {
            await ViewModel.OpenRouteAsync(route);
        }

        RefreshState();
    }

    private void ViewModel_PropertyChanged(object? sender, PropertyChangedEventArgs e)
    {
        RefreshState();
    }

    private void WatcherStatusView_Unloaded(object sender, RoutedEventArgs e)
    {
        if (ViewModel is { } model)
        {
            model.PropertyChanged -= ViewModel_PropertyChanged;
        }
    }

    private async void RestartWatcherButton_Click(object sender, RoutedEventArgs e)
    {
        if (ViewModel is null)
        {
            return;
        }

        await ViewModel.RestartWatcherAsync();
        RefreshState();
    }

    private async void RunRescanNowButton_Click(object sender, RoutedEventArgs e)
    {
        if (ViewModel is null || Route is null)
        {
            return;
        }

        if (await ViewModel.PrepareRescanConfirmAsync()
            && ViewModel.RescanPreview is { } preview)
        {
            OpenRescanConfirmRequested?.Invoke(new RescanConfirmRequest(Route, preview));
        }

        RefreshState();
    }

    private async void ExportDiagnosticsButton_Click(object sender, RoutedEventArgs e)
    {
        if (ViewModel is null)
        {
            return;
        }

        await ViewModel.ExportDiagnosticsAsync();
        RefreshState();
    }

    private async void OpenRepositoryFolderButton_Click(object sender, RoutedEventArgs e)
    {
        if (ViewModel is null)
        {
            return;
        }

        await ViewModel.OpenRepositoryFolderAsync();
        RefreshState();
    }

    private void CloseWatcherStatusButton_Click(object sender, RoutedEventArgs e)
    {
        CloseRequested?.Invoke();
    }

    private void RefreshState()
    {
        if (ViewModel is null)
        {
            IsEnabled = false;
            return;
        }

        IsEnabled = true;
        WatcherRouteTextBlock.Text = ViewModel.WatchingText;
        RefreshStatusText();
        RefreshStatusControls();
    }

    private void RefreshStatusText()
    {
        if (ViewModel is null)
        {
            return;
        }

        WatcherStatusTextBlock.Text = ViewModel.StatusText;
        WatcherSummaryTextBlock.Text = ViewModel.SummaryText;
        WatcherLastEventTextBlock.Text = ViewModel.LastEventText;
        WatcherPendingEventsTextBlock.Text = ViewModel.PendingEventsText;
        WatcherLastSyncTextBlock.Text = ViewModel.LastSyncText;
        WatcherLastRescanTextBlock.Text = ViewModel.LastRescanText;
        WatcherBackendTextBlock.Text = ViewModel.BackendText;
        WatcherCountTextBlock.Text = ViewModel.WatchCountText;
        LatestScanSessionTextBlock.Text = ViewModel.LatestScanSessionText;
        RescanPreviewTextBlock.Text = ViewModel.RescanPreviewText;
        OneDriveNoticeTextBlock.Text = ViewModel.OneDriveNoticeText;
        OneDriveNoticeTextBlock.Visibility = ViewModel.HasOneDriveNotice
            ? Visibility.Visible
            : Visibility.Collapsed;
    }

    private void RefreshStatusControls()
    {
        if (ViewModel is null)
        {
            return;
        }

        WatcherRecoveryInfoBar.Message = ViewModel.RecoveryText;
        WatcherRecoveryInfoBar.Severity = ViewModel.Error is null
            ? InfoBarSeverity.Informational
            : InfoBarSeverity.Error;
        WatcherNoEventsTextBlock.Visibility = ViewModel.HasRecentEvents
            ? Visibility.Collapsed
            : Visibility.Visible;
        bool showProgress = ViewModel.IsBusy || ViewModel.IsWatcherStarting;
        WatcherStatusProgressRing.Visibility = showProgress
            ? Visibility.Visible
            : Visibility.Collapsed;
        WatcherStatusProgressRing.IsActive = showProgress;

        RestartWatcherButton.IsEnabled = ViewModel.CanRestartWatcher;
        RunRescanNowButton.IsEnabled = ViewModel.CanOpenRescanConfirm;
        RunRescanNowButton.Tag = ViewModel.RescanDisabledReason;
        ExportDiagnosticsButton.IsEnabled = ViewModel.CanExportDiagnostics;
        OpenRepositoryFolderButton.IsEnabled = ViewModel.CanOpenRepositoryFolder;
    }
}
