namespace AreaMatrix.Linux.Features.Help;

public sealed class PlatformDifferencesView
{
    public PlatformDifferencesView(PlatformDifferencesViewModel viewModel)
    {
        ViewModel = viewModel;
    }

    public event Action? CloseRequested;

    public PlatformDifferencesViewModel ViewModel { get; }

    public Task OpenAsync(CancellationToken cancellationToken = default)
    {
        return ViewModel.LoadAsync(cancellationToken);
    }

    public Task CheckCapabilitiesAsync(CancellationToken cancellationToken = default)
    {
        return ViewModel.LoadCapabilitiesAsync(cancellationToken);
    }

    public async Task SelectTargetAndCheckAsync(
        PlatformDifferencesBindingTarget targetPlatform,
        CancellationToken cancellationToken = default)
    {
        ViewModel.SelectedTargetPlatform = targetPlatform;
        await ViewModel.InspectContractAsync(cancellationToken).ConfigureAwait(false);
    }

    public Task CheckContractAsync(CancellationToken cancellationToken = default)
    {
        return ViewModel.InspectContractAsync(cancellationToken);
    }

    public void Close()
    {
        CloseRequested?.Invoke();
    }
}
