using System;
using System.ComponentModel;
using System.Threading.Tasks;
using Microsoft.UI.Xaml;
using Microsoft.UI.Xaml.Controls;

namespace AreaMatrix.Features.Onboarding;

public sealed partial class RepositoryAdoptConfirmDialog : UserControl
{
    private bool isRefreshingState;

    public RepositoryAdoptConfirmDialog()
    {
        InitializeComponent();
        RefreshState();
    }

    public event Action? CancelRequested;

    public event Action? ChooseAnotherFolderRequested;

    public event Func<WindowsRepositoryRoute, Task>? RepositoryOpenedRequested;

    public RepositoryAdoptConfirmViewModel? ViewModel
    {
        get => DataContext as RepositoryAdoptConfirmViewModel;
        set
        {
            if (DataContext is RepositoryAdoptConfirmViewModel previousModel)
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

    public async Task OpenRouteAsync(WindowsRepositoryRoute route)
    {
        if (ViewModel is null)
        {
            return;
        }

        await ViewModel.OpenRouteAsync(route);
        RefreshState();
    }

    private async void UseThisFolderButton_Click(object sender, RoutedEventArgs e)
    {
        await AdoptRepositoryFromCurrentRouteAsync();
    }

    private async void TryAgainButton_Click(object sender, RoutedEventArgs e)
    {
        await AdoptRepositoryFromCurrentRouteAsync();
    }

    private void CancelButton_Click(object sender, RoutedEventArgs e)
    {
        CancelRequested?.Invoke();
    }

    private void ChooseAnotherFolderButton_Click(object sender, RoutedEventArgs e)
    {
        ChooseAnotherFolderRequested?.Invoke();
    }

    private void AcknowledgementCheckBox_Changed(object sender, RoutedEventArgs e)
    {
        if (isRefreshingState || ViewModel is null)
        {
            return;
        }

        ViewModel.IsMetadataAcknowledged = MetadataAcknowledgementCheckBox.IsChecked == true;
        ViewModel.IsSyncRiskAcknowledged = SyncRiskAcknowledgementCheckBox.IsChecked == true;
        RefreshState();
    }

    private async Task AdoptRepositoryFromCurrentRouteAsync()
    {
        if (ViewModel is null)
        {
            return;
        }

        await ViewModel.AdoptRepositoryAsync();
        RefreshState();

        if (ViewModel.CompletedRoute.Kind == WindowsRepositoryRouteKind.MainWindow
            && RepositoryOpenedRequested is { } repositoryOpened)
        {
            await repositoryOpened(ViewModel.CompletedRoute);
        }
    }

    private void ViewModel_PropertyChanged(object? sender, PropertyChangedEventArgs e)
    {
        RefreshState();
    }

    private void RefreshState()
    {
        RepositoryAdoptConfirmViewModel? model = ViewModel;
        if (model is null)
        {
            SetEmptyState();
            return;
        }

        isRefreshingState = true;
        try
        {
            MetadataAcknowledgementCheckBox.IsChecked = model.IsMetadataAcknowledged;
            SyncRiskAcknowledgementCheckBox.IsChecked = model.IsSyncRiskAcknowledged;
            SyncRiskAcknowledgementCheckBox.Visibility = model.RequiresSyncRiskAcknowledgement
                ? Visibility.Visible
                : Visibility.Collapsed;
        }
        finally
        {
            isRefreshingState = false;
        }

        StatusTextBlock.Text = model.StatusText;
        SafetyTextBlock.Text = model.SafetyText;
        MetadataAddTextBlock.Text = model.MetadataAddText;
        RollbackTextBlock.Text = model.RollbackText;
        FolderTextBlock.Text = model.FolderText;
        EstimatedItemsTextBlock.Text = model.EstimatedItemsText;
        WritableTextBlock.Text = model.WritableText;
        MetadataTextBlock.Text = model.MetadataText;
        LocationTypeTextBlock.Text = model.LocationTypeText;
        AddedDetailsTextBlock.Text = model.AddedDetailsText;
        RiskTextBlock.Text = model.RiskText;
        RiskTextBlock.Visibility = string.IsNullOrWhiteSpace(model.RiskText)
            ? Visibility.Collapsed
            : Visibility.Visible;

        ErrorTextBlock.Text = model.Error?.Message ?? string.Empty;
        FailureSection.Visibility = model.Error is null
            ? Visibility.Collapsed
            : Visibility.Visible;
        TryAgainButton.IsEnabled = model.CanRetryAdopt;

        DisabledReasonTextBlock.Text = model.CanAdoptRepository
            ? string.Empty
            : model.DisabledReason;
        UseThisFolderButton.IsEnabled = model.CanAdoptRepository;
        UseThisFolderButton.Content = model.IsAdopting
            ? "Preparing repository..."
            : "Use This Folder";
        RepositoryAdoptProgressRing.Visibility = model.IsChecking || model.IsAdopting
            ? Visibility.Visible
            : Visibility.Collapsed;
    }

    private void SetEmptyState()
    {
        StatusTextBlock.Text = string.Empty;
        SafetyTextBlock.Text = string.Empty;
        MetadataAddTextBlock.Text = string.Empty;
        RollbackTextBlock.Text = string.Empty;
        FolderTextBlock.Text = string.Empty;
        EstimatedItemsTextBlock.Text = string.Empty;
        WritableTextBlock.Text = string.Empty;
        MetadataTextBlock.Text = string.Empty;
        LocationTypeTextBlock.Text = string.Empty;
        AddedDetailsTextBlock.Text = string.Empty;
        RiskTextBlock.Text = string.Empty;
        ErrorTextBlock.Text = string.Empty;
        DisabledReasonTextBlock.Text = string.Empty;
        FailureSection.Visibility = Visibility.Collapsed;
        RepositoryAdoptProgressRing.Visibility = Visibility.Collapsed;
        UseThisFolderButton.IsEnabled = false;
        TryAgainButton.IsEnabled = false;
        MetadataAcknowledgementCheckBox.IsChecked = false;
        SyncRiskAcknowledgementCheckBox.IsChecked = false;
        SyncRiskAcknowledgementCheckBox.Visibility = Visibility.Collapsed;
    }
}
