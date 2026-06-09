using System;
using System.ComponentModel;
using System.Threading.Tasks;
using Microsoft.UI.Xaml;
using Microsoft.UI.Xaml.Controls;

namespace AreaMatrix.Features.Onboarding;

public sealed partial class RepositoryInitConfirmDialog : UserControl
{
    public RepositoryInitConfirmDialog()
    {
        InitializeComponent();
        RefreshState();
    }

    public event Action? CancelRequested;

    public event Action? ChooseAnotherFolderRequested;

    public event Func<WindowsRepositoryRoute, Task>? RepositoryOpenedRequested;

    public RepositoryInitConfirmViewModel? ViewModel
    {
        get => DataContext as RepositoryInitConfirmViewModel;
        set
        {
            if (DataContext is RepositoryInitConfirmViewModel previousModel)
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

    private async void CreateRepositoryButton_Click(object sender, RoutedEventArgs e)
    {
        await CreateRepositoryFromCurrentRouteAsync();
    }

    private async void TryAgainButton_Click(object sender, RoutedEventArgs e)
    {
        await CreateRepositoryFromCurrentRouteAsync();
    }

    private void CancelButton_Click(object sender, RoutedEventArgs e)
    {
        CancelRequested?.Invoke();
    }

    private void ChooseAnotherFolderButton_Click(object sender, RoutedEventArgs e)
    {
        ChooseAnotherFolderRequested?.Invoke();
    }

    private async Task CreateRepositoryFromCurrentRouteAsync()
    {
        if (ViewModel is null)
        {
            return;
        }

        await ViewModel.CreateRepositoryAsync();
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
        RepositoryInitConfirmViewModel? model = ViewModel;
        if (model is null)
        {
            SetEmptyState();
            return;
        }

        StatusTextBlock.Text = model.StatusText;
        SafetyTextBlock.Text = model.SafetyText;
        NoOverwriteTextBlock.Text = model.NoOverwriteText;
        FolderTextBlock.Text = model.FolderText;
        PathTypeTextBlock.Text = model.PathTypeText;
        WritableTextBlock.Text = model.WritableText;
        FolderCheckTextBlock.Text = model.FolderCheckText;
        WritePermissionTextBlock.Text = model.WritePermissionText;
        DiskSpaceTextBlock.Text = model.DiskSpaceText;
        RiskTextBlock.Text = model.RiskText;
        RiskTextBlock.Visibility = string.IsNullOrWhiteSpace(model.RiskText)
            ? Visibility.Collapsed
            : Visibility.Visible;

        ErrorTextBlock.Text = model.Error?.Message ?? string.Empty;
        FailureSection.Visibility = model.Error is null
            ? Visibility.Collapsed
            : Visibility.Visible;
        TryAgainButton.IsEnabled = model.CanRetryCreate;

        DisabledReasonTextBlock.Text = model.CanCreateRepository
            ? string.Empty
            : model.DisabledReason;
        CreateRepositoryButton.IsEnabled = model.CanCreateRepository;
        CreateRepositoryButton.Content = model.IsCreating
            ? "Creating metadata..."
            : "Create Repository";
        RepositoryInitProgressRing.Visibility = model.IsChecking || model.IsCreating
            ? Visibility.Visible
            : Visibility.Collapsed;
    }

    private void SetEmptyState()
    {
        StatusTextBlock.Text = string.Empty;
        SafetyTextBlock.Text = string.Empty;
        NoOverwriteTextBlock.Text = string.Empty;
        FolderTextBlock.Text = string.Empty;
        PathTypeTextBlock.Text = string.Empty;
        WritableTextBlock.Text = string.Empty;
        FolderCheckTextBlock.Text = string.Empty;
        WritePermissionTextBlock.Text = string.Empty;
        DiskSpaceTextBlock.Text = string.Empty;
        RiskTextBlock.Text = string.Empty;
        ErrorTextBlock.Text = string.Empty;
        DisabledReasonTextBlock.Text = string.Empty;
        FailureSection.Visibility = Visibility.Collapsed;
        RepositoryInitProgressRing.Visibility = Visibility.Collapsed;
        CreateRepositoryButton.IsEnabled = false;
        TryAgainButton.IsEnabled = false;
    }
}
