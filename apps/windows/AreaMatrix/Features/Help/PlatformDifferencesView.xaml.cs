using System;
using System.ComponentModel;
using System.Linq;
using System.Threading.Tasks;
using Microsoft.UI.Xaml;
using Microsoft.UI.Xaml.Controls;

namespace AreaMatrix.Features.Help;

public sealed partial class PlatformDifferencesView : UserControl
{
    public PlatformDifferencesView()
    {
        InitializeComponent();
        BindingTargetComboBox.ItemsSource = Enum.GetValues<PlatformDifferencesBindingTarget>();
        BindingTargetComboBox.SelectedItem = PlatformDifferencesBindingTarget.Kotlin;
        Unloaded += PlatformDifferencesView_Unloaded;
    }

    public event Action? CloseRequested;

    public PlatformDifferencesViewModel? ViewModel
    {
        get => DataContext as PlatformDifferencesViewModel;
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
                BindingTargetComboBox.SelectedItem = value.SelectedTargetPlatform;
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

    private async void CheckContractButton_Click(object sender, RoutedEventArgs e)
    {
        if (ViewModel is null)
        {
            return;
        }

        await ViewModel.InspectContractAsync();
        RefreshState();
    }

    private async void CheckCapabilitiesButton_Click(object sender, RoutedEventArgs e)
    {
        if (ViewModel is null)
        {
            return;
        }

        await ViewModel.LoadCapabilitiesAsync();
        RefreshState();
    }

    private async void BindingTargetComboBox_SelectionChanged(object sender, SelectionChangedEventArgs e)
    {
        if (ViewModel is null || BindingTargetComboBox.SelectedItem is not PlatformDifferencesBindingTarget target)
        {
            return;
        }

        ViewModel.SelectedTargetPlatform = target;
        await ViewModel.InspectContractAsync();
        RefreshState();
    }

    private void ClosePlatformDifferencesButton_Click(object sender, RoutedEventArgs e)
    {
        CloseRequested?.Invoke();
    }

    private void ViewModel_PropertyChanged(object? sender, PropertyChangedEventArgs e)
    {
        RefreshState();
    }

    private void PlatformDifferencesView_Unloaded(object sender, RoutedEventArgs e)
    {
        if (ViewModel is { } model)
        {
            model.PropertyChanged -= ViewModel_PropertyChanged;
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
        PlatformSummaryTextBlock.Text = $"Platform: {ViewModel.HostPlatform}. {ViewModel.RepositoryText}";
        CheckCapabilitiesButton.IsEnabled = !ViewModel.IsCheckingCapabilities;
        CapabilitiesProgressRing.Visibility = ViewModel.IsCheckingCapabilities ? Visibility.Visible : Visibility.Collapsed;
        CapabilitiesProgressRing.IsActive = ViewModel.IsCheckingCapabilities;
        CheckContractButton.Content = ViewModel.ActionTitle;
        CheckContractButton.IsEnabled = !ViewModel.IsChecking;
        ContractProgressRing.Visibility = ViewModel.IsChecking ? Visibility.Visible : Visibility.Collapsed;
        ContractProgressRing.IsActive = ViewModel.IsChecking;
        RefreshCapabilitiesStatus();
        RefreshContractStatus();
        RefreshContractRows();
    }

    private void RefreshCapabilitiesStatus()
    {
        if (ViewModel is null)
        {
            return;
        }

        CapabilitiesSummaryTextBlock.Text = ViewModel.CapabilitySummaryText;
        CapabilityRowsItemsControl.ItemsSource = ViewModel.CapabilityRows;
        CapabilitiesStatusInfoBar.Message = ViewModel.CapabilityErrorMessage is not null
            ? ViewModel.CapabilityRecoveryText ?? "Retry the platform capability check."
            : "Platform capability snapshot is available.";
        CapabilitiesStatusInfoBar.Severity = ViewModel.CapabilityErrorMessage is not null
            ? InfoBarSeverity.Warning
            : InfoBarSeverity.Informational;
    }

    private void RefreshContractStatus()
    {
        if (ViewModel is null)
        {
            return;
        }

        ContractSummaryTextBlock.Text = ViewModel.SummaryText;
        ContractStatusInfoBar.Message = ViewModel.Status switch
        {
            PlatformDifferencesContractStatus.Loading => "Checking binding contract...",
            PlatformDifferencesContractStatus.Loaded => "Binding contract is available.",
            PlatformDifferencesContractStatus.Failed => ViewModel.RecoveryText ?? "Retry the contract check.",
            _ => "Binding contract has not been checked."
        };
        ContractStatusInfoBar.Severity = ViewModel.Status == PlatformDifferencesContractStatus.Failed
            ? InfoBarSeverity.Error
            : InfoBarSeverity.Informational;
    }

    private void RefreshContractRows()
    {
        PlatformDifferencesBindingContractReport? report = ViewModel?.Report;
        SupportedApisItemsControl.ItemsSource = report?.SupportedApis.Select(ApiRow).ToArray() ?? [];
        TypeMappingsItemsControl.ItemsSource = report?.TypeMappings.Select(TypeMappingRow).ToArray() ?? [];
        MissingCapabilitiesItemsControl.ItemsSource = report?.MissingCapabilities.Count > 0
            ? report.MissingCapabilities.Select(MissingCapabilityRow).ToArray()
            : ["No missing binding capabilities for this target."];
    }

    private static string ApiRow(PlatformDifferencesBindingApiContract item)
    {
        return $"{item.Name} - {item.Capability} - {item.Status}{Reason(item.Reason)}";
    }

    private static string TypeMappingRow(PlatformDifferencesBindingTypeMapping item)
    {
        return $"{item.RustType} -> {item.TargetType} - {item.Status}{Reason(item.Reason)}";
    }

    private static string MissingCapabilityRow(PlatformDifferencesBindingMissingCapability item)
    {
        return $"{item.Label} - {item.Capability} - {item.Status}: {item.Reason}";
    }

    private static string Reason(string? reason)
    {
        return string.IsNullOrWhiteSpace(reason) ? string.Empty : $": {reason}";
    }
}
