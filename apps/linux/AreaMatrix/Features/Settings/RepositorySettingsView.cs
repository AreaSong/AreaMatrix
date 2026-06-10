namespace AreaMatrix.Linux.Features.Settings;

public sealed class RepositorySettingsView
{
    public RepositorySettingsView(RepositorySettingsViewModel viewModel)
    {
        ViewModel = viewModel;
    }

    public event Action? ReconnectRepositoryRequested;

    public event Action? ChooseAnotherFolderRequested;

    public event Action? PlatformCapabilitiesRequested;

    public event Action? ExportDiagnosticsRequested;

    public RepositorySettingsViewModel ViewModel { get; }

    public Task OpenAsync(CancellationToken cancellationToken = default)
    {
        return ViewModel.LoadAsync(cancellationToken);
    }

    public void ReconnectRepository()
    {
        ReconnectRepositoryRequested?.Invoke();
    }

    public void ChooseAnotherFolder()
    {
        ChooseAnotherFolderRequested?.Invoke();
    }

    public void OpenPlatformCapabilities()
    {
        PlatformCapabilitiesRequested?.Invoke();
    }

    public Task<bool> ExportDiagnosticsAsync(CancellationToken cancellationToken = default)
    {
        ExportDiagnosticsRequested?.Invoke();
        return ViewModel.ExportDiagnosticsAsync(cancellationToken);
    }

    public Task SaveFallbackToInboxAsync(
        bool enabled,
        CancellationToken cancellationToken = default)
    {
        return ViewModel.SaveFallbackToInboxAsync(enabled, cancellationToken);
    }
}
