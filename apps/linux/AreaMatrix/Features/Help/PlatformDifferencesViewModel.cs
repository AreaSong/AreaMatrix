using System.ComponentModel;
using System.Runtime.CompilerServices;
using AreaMatrix.Linux.Features.Onboarding;

namespace AreaMatrix.Linux.Features.Help;

public enum PlatformDifferencesContractStatus
{
    Idle,
    Loading,
    Loaded,
    Failed
}

public sealed class PlatformDifferencesViewModel : INotifyPropertyChanged
{
    private readonly IPlatformDifferencesCoreBridge coreBridge;
    private PlatformDifferencesBindingContractReport? report;
    private LinuxPlatformCapabilities? capabilities;
    private PlatformDifferencesBindingTarget selectedTargetPlatform = PlatformDifferencesBindingTarget.Python;
    private string? errorMessage;
    private string? recoveryText;
    private string? capabilityErrorMessage;
    private string? capabilityRecoveryText;
    private bool isChecking;
    private bool isCheckingCapabilities;

    public PlatformDifferencesViewModel(
        IPlatformDifferencesCoreBridge coreBridge,
        LinuxPlatformId hostPlatform = LinuxPlatformId.Linux,
        string appVersion = "1",
        long bindingVersion = 1)
    {
        this.coreBridge = coreBridge;
        HostPlatform = hostPlatform;
        AppVersion = appVersion;
        BindingVersion = bindingVersion;
    }

    public event PropertyChangedEventHandler? PropertyChanged;

    public LinuxPlatformId HostPlatform { get; }

    public string AppVersion { get; }

    public long BindingVersion { get; }

    public PlatformDifferencesContractStatus Status { get; private set; } = PlatformDifferencesContractStatus.Idle;

    public PlatformDifferencesBindingTarget SelectedTargetPlatform
    {
        get => selectedTargetPlatform;
        set
        {
            if (selectedTargetPlatform == value)
            {
                return;
            }

            selectedTargetPlatform = value;
            OnPropertyChanged();
        }
    }

    public PlatformDifferencesBindingContractReport? Report
    {
        get => report;
        private set
        {
            report = value;
            OnPropertyChanged();
        }
    }

    public LinuxPlatformCapabilities? Capabilities
    {
        get => capabilities;
        private set
        {
            capabilities = value;
            OnPropertyChanged();
        }
    }

    public string? ErrorMessage
    {
        get => errorMessage;
        private set
        {
            errorMessage = value;
            OnPropertyChanged();
        }
    }

    public string? CapabilityErrorMessage
    {
        get => capabilityErrorMessage;
        private set
        {
            capabilityErrorMessage = value;
            OnPropertyChanged();
        }
    }

    public string? RecoveryText
    {
        get => recoveryText;
        private set
        {
            recoveryText = value;
            OnPropertyChanged();
        }
    }

    public string? CapabilityRecoveryText
    {
        get => capabilityRecoveryText;
        private set
        {
            capabilityRecoveryText = value;
            OnPropertyChanged();
        }
    }

    public bool IsChecking
    {
        get => isChecking;
        private set
        {
            isChecking = value;
            OnPropertyChanged();
        }
    }

    public bool IsCheckingCapabilities
    {
        get => isCheckingCapabilities;
        private set
        {
            isCheckingCapabilities = value;
            OnPropertyChanged();
        }
    }

    public string ActionTitle => IsChecking ? "Checking contract..." : "Check contract";

    public string RepositoryText => "Repository: Not connected";

    public string SummaryText => Report is { } currentReport
        ? $"{currentReport.TargetPlatform} binding v{currentReport.BindingVersion}, Core {currentReport.CoreVersion}"
        : "Binding contract has not been checked.";

    public string CapabilitySummaryText => Capabilities is { } currentCapabilities
        ? $"{currentCapabilities.Platform} capabilities for app {currentCapabilities.AppVersion}"
        : "Capability snapshot has not been checked.";

    public IReadOnlyList<string> CapabilityRows => Capabilities is { } currentCapabilities
        ? PlatformDifferencesCapabilitiesDisplay.RowsFor(currentCapabilities)
        : [];

    public async Task LoadAsync(CancellationToken cancellationToken = default)
    {
        await LoadCapabilitiesAsync(cancellationToken).ConfigureAwait(false);
        await InspectContractAsync(cancellationToken).ConfigureAwait(false);
    }

    public async Task LoadCapabilitiesAsync(CancellationToken cancellationToken = default)
    {
        BeginCheckingCapabilities();
        try
        {
            Capabilities = await coreBridge
                .GetPlatformCapabilitiesAsync(HostPlatform, AppVersion, cancellationToken)
                .ConfigureAwait(false);
        }
        catch (Exception error)
        {
            Capabilities = PlatformDifferencesCapabilitiesDisplay.UnknownSnapshot(
                HostPlatform,
                AppVersion,
                error.Message);
            CapabilityErrorMessage = "Capability snapshot unavailable";
            CapabilityRecoveryText = RecoveryForCapability(error);
        }
        finally
        {
            IsCheckingCapabilities = false;
            OnPropertyChanged(nameof(CapabilitySummaryText));
            OnPropertyChanged(nameof(CapabilityRows));
        }
    }

    public async Task InspectContractAsync(CancellationToken cancellationToken = default)
    {
        BeginChecking();
        try
        {
            Report = await coreBridge
                .InspectBindingContractAsync(SelectedTargetPlatform, BindingVersion, cancellationToken)
                .ConfigureAwait(false);
            Status = PlatformDifferencesContractStatus.Loaded;
        }
        catch (Exception error)
        {
            Report = null;
            ErrorMessage = "Binding contract unavailable";
            RecoveryText = RecoveryFor(error);
            Status = PlatformDifferencesContractStatus.Failed;
        }
        finally
        {
            IsChecking = false;
            OnPropertyChanged(nameof(ActionTitle));
            OnPropertyChanged(nameof(SummaryText));
            OnPropertyChanged(nameof(Status));
        }
    }

    private void BeginChecking()
    {
        IsChecking = true;
        Status = PlatformDifferencesContractStatus.Loading;
        ErrorMessage = null;
        RecoveryText = null;
        OnPropertyChanged(nameof(ActionTitle));
        OnPropertyChanged(nameof(Status));
    }

    private void BeginCheckingCapabilities()
    {
        IsCheckingCapabilities = true;
        CapabilityErrorMessage = null;
        CapabilityRecoveryText = null;
        OnPropertyChanged(nameof(CapabilitySummaryText));
    }

    private static string RecoveryFor(Exception error)
    {
        return error is OperationCanceledException
            ? "Retry the contract check."
            : "Check the Core bridge integration, then retry.";
    }

    private static string RecoveryForCapability(Exception error)
    {
        return error is OperationCanceledException
            ? "Retry the platform capability check."
            : "Check the Core platform capability bridge, then retry.";
    }

    private void OnPropertyChanged([CallerMemberName] string? propertyName = null)
    {
        PropertyChanged?.Invoke(this, new PropertyChangedEventArgs(propertyName));
    }
}
