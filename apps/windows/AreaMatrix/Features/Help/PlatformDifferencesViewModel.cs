using System.ComponentModel;
using System.Runtime.CompilerServices;

namespace AreaMatrix.Features.Help;

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
    private PlatformDifferencesBindingTarget selectedTargetPlatform = PlatformDifferencesBindingTarget.Kotlin;
    private string? errorMessage;
    private string? recoveryText;
    private bool isChecking;

    public PlatformDifferencesViewModel(
        IPlatformDifferencesCoreBridge coreBridge,
        string hostPlatform = "Windows",
        long bindingVersion = 1)
    {
        this.coreBridge = coreBridge;
        HostPlatform = hostPlatform;
        BindingVersion = bindingVersion;
    }

    public event PropertyChangedEventHandler? PropertyChanged;

    public string HostPlatform { get; }

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

    public string? ErrorMessage
    {
        get => errorMessage;
        private set
        {
            errorMessage = value;
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

    public bool IsChecking
    {
        get => isChecking;
        private set
        {
            isChecking = value;
            OnPropertyChanged();
        }
    }

    public string ActionTitle => IsChecking ? "Checking contract..." : "Check contract";

    public string RepositoryText => "Repository: Not connected";

    public string SummaryText => Report is { } currentReport
        ? $"{currentReport.TargetPlatform} binding v{currentReport.BindingVersion}, Core {currentReport.CoreVersion}"
        : "Binding contract has not been checked.";

    public async Task LoadAsync(CancellationToken cancellationToken = default)
    {
        await InspectContractAsync(cancellationToken).ConfigureAwait(false);
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

    private static string RecoveryFor(Exception error)
    {
        return error is OperationCanceledException
            ? "Retry the contract check."
            : "Check the Core bridge integration, then retry.";
    }

    private void OnPropertyChanged([CallerMemberName] string? propertyName = null)
    {
        PropertyChanged?.Invoke(this, new PropertyChangedEventArgs(propertyName));
    }
}
