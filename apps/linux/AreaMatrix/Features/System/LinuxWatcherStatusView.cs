using AreaMatrix.Linux.Features.Onboarding;

namespace AreaMatrix.Linux.Features.System;

public sealed class LinuxWatcherStatusView
{
    public LinuxWatcherStatusView(LinuxWatcherStatusViewModel viewModel)
    {
        ViewModel = viewModel;
    }

    public event Action<LinuxRescanConfirmRequest>? OpenRescanConfirmRequested;

    public event Action? CloseRequested;

    public LinuxWatcherStatusViewModel ViewModel { get; }

    public LinuxRepositoryRoute? Route { get; private set; }

    public Task OpenRouteAsync(
        LinuxRepositoryRoute route,
        CancellationToken cancellationToken = default)
    {
        Route = route;
        return ViewModel.OpenRouteAsync(route, cancellationToken);
    }

    public Task RestartWatcherAsync(CancellationToken cancellationToken = default)
    {
        return ViewModel.RestartWatcherAsync(cancellationToken);
    }

    public async Task<bool> RunRescanNow(CancellationToken cancellationToken = default)
    {
        if (Route is null || !ViewModel.CanRequestRescanConfirm())
        {
            return false;
        }

        bool prepared = await ViewModel
            .PrepareRescanConfirmAsync(cancellationToken)
            .ConfigureAwait(false);
        if (!prepared || ViewModel.RescanPreview is not { } preview)
        {
            return false;
        }

        OpenRescanConfirmRequested?.Invoke(new LinuxRescanConfirmRequest(Route, preview));
        return true;
    }

    public Task<bool> ExportDiagnosticsAsync(CancellationToken cancellationToken = default)
    {
        return ViewModel.ExportDiagnosticsAsync(cancellationToken);
    }

    public Task<bool> OpenRepositoryFolderAsync(CancellationToken cancellationToken = default)
    {
        return ViewModel.OpenRepositoryFolderAsync(cancellationToken);
    }

    public void Close()
    {
        CloseRequested?.Invoke();
    }
}
