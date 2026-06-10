using System;
using System.ComponentModel;
using System.Threading.Tasks;
using Microsoft.UI.Xaml;
using Microsoft.UI.Xaml.Controls;

namespace AreaMatrix.Features.Settings;

public sealed partial class RepositorySettingsView : UserControl
{
    public RepositorySettingsView()
    {
        InitializeComponent();
        Unloaded += RepositorySettingsView_Unloaded;
    }

    public event Action? ReconnectRepositoryRequested;

    public event Action? ChooseAnotherFolderRequested;

    public event Action? PlatformCapabilitiesRequested;

    public event Action? ExportDiagnosticsRequested;

    public RepositorySettingsViewModel? ViewModel
    {
        get => DataContext as RepositorySettingsViewModel;
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

    public async Task OpenAsync()
    {
        if (ViewModel is not null)
        {
            await ViewModel.LoadAsync();
        }

        RefreshState();
    }

    private void ViewModel_PropertyChanged(object? sender, PropertyChangedEventArgs e)
    {
        RefreshState();
    }

    private void RepositorySettingsView_Unloaded(object sender, RoutedEventArgs e)
    {
        if (ViewModel is { } model)
        {
            model.PropertyChanged -= ViewModel_PropertyChanged;
        }
    }

    private void ReconnectRepositoryButton_Click(object sender, RoutedEventArgs e)
    {
        ReconnectRepositoryRequested?.Invoke();
    }

    private void ChooseAnotherFolderButton_Click(object sender, RoutedEventArgs e)
    {
        ChooseAnotherFolderRequested?.Invoke();
    }

    private void PlatformCapabilitiesButton_Click(object sender, RoutedEventArgs e)
    {
        PlatformCapabilitiesRequested?.Invoke();
    }

    private void ExportDiagnosticsButton_Click(object sender, RoutedEventArgs e)
    {
        ExportDiagnosticsRequested?.Invoke();
    }

    public async Task<bool> ExportDiagnosticsAsync()
    {
        if (ViewModel is null)
        {
            return false;
        }

        bool exported = await ViewModel.ExportDiagnosticsAsync();
        RefreshState();
        return exported;
    }

    private async void FallbackToInboxCheckBox_Click(object sender, RoutedEventArgs e)
    {
        if (ViewModel is null || FallbackToInboxCheckBox.IsChecked is not bool enabled)
        {
            return;
        }

        await ViewModel.SaveFallbackToInboxAsync(enabled);
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
        ExportDiagnosticsButton.IsEnabled = ViewModel.CanExportDiagnostics
            && ExportDiagnosticsRequested is not null;
        if (ViewModel.Snapshot is { } snapshot)
        {
            RefreshLoaded(snapshot);
            return;
        }

        RefreshNonLoadedState();
    }

    private void RefreshLoaded(RepositorySettingsSnapshot snapshot)
    {
        RepositorySummaryTextBlock.Text = $"Repository: {snapshot.Location}";
        StatusInfoBar.Message = "Repository settings loaded.";
        StatusInfoBar.Severity = InfoBarSeverity.Informational;
        NameTextBlock.Text = $"Name: {snapshot.Name}";
        LocationTextBlock.Text = $"Location: {snapshot.Location}";
        TypeTextBlock.Text = $"Type: {snapshot.LocationType}";
        LastOpenedTextBlock.Text = $"Last opened: {snapshot.LastOpened}";
        CoreVersionTextBlock.Text = $"Core version: {snapshot.CoreVersion}";
        AccessTextBlock.Text = $"Access: {snapshot.Access}";
        WatcherTextBlock.Text = $"Watcher: {snapshot.Watcher}";
        CloudTextBlock.Text = $"Cloud: {snapshot.Cloud}";
        LocaleTextBlock.Text = $"Locale: {snapshot.Config.Locale}";
        FallbackToInboxCheckBox.IsChecked = snapshot.Config.FallbackToInbox;
        FallbackToInboxCheckBox.IsEnabled = ViewModel?.IsSaving == false;
        SaveFailureTextBlock.Text = ViewModel?.SaveFailure is { } saveFailure
            ? $"{saveFailure.Message} {saveFailure.Recovery}"
            : string.Empty;
        DiagnosticsStatusTextBlock.Text = DiagnosticsStatusText();
    }

    private void RefreshNonLoadedState()
    {
        RepositorySummaryTextBlock.Text = ViewModel?.RepositoryPath ?? "No repository connected.";
        NameTextBlock.Text = string.Empty;
        LocationTextBlock.Text = string.Empty;
        TypeTextBlock.Text = string.Empty;
        LastOpenedTextBlock.Text = string.Empty;
        CoreVersionTextBlock.Text = string.Empty;
        AccessTextBlock.Text = string.Empty;
        WatcherTextBlock.Text = string.Empty;
        CloudTextBlock.Text = string.Empty;
        LocaleTextBlock.Text = string.Empty;
        FallbackToInboxCheckBox.IsChecked = false;
        FallbackToInboxCheckBox.IsEnabled = false;
        SaveFailureTextBlock.Text = string.Empty;
        DiagnosticsStatusTextBlock.Text = string.Empty;
        StatusInfoBar.Message = ViewModel?.Status switch
        {
            RepositorySettingsStatus.Loading => "Loading repository settings...",
            RepositorySettingsStatus.Empty => "No repository connected.",
            RepositorySettingsStatus.Failed => ViewModel.Failure?.Recovery ?? "Try again.",
            _ => "Repository settings are idle."
        };
        StatusInfoBar.Severity = ViewModel?.Status == RepositorySettingsStatus.Failed
            ? InfoBarSeverity.Error
            : InfoBarSeverity.Informational;
    }

    private string DiagnosticsStatusText()
    {
        if (ViewModel?.IsExportingDiagnostics == true)
        {
            return "Exporting diagnostics...";
        }

        if (ViewModel?.LastDiagnosticsExportPath is { } path)
        {
            return $"Diagnostics exported: {path}";
        }

        if (ViewModel?.DiagnosticsFailure is { } failure)
        {
            return $"{failure.Message} {failure.Recovery}";
        }

        return "Diagnostics do not include user file contents.";
    }
}
