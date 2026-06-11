namespace AreaMatrix.Linux.Features.Onboarding;

public sealed class RepositoryAdoptConfirmView
{
    public RepositoryAdoptConfirmView(RepositoryAdoptConfirmViewModel viewModel)
    {
        ViewModel = viewModel;
    }

    public RepositoryAdoptConfirmViewModel ViewModel { get; }

    public Task OpenRouteAsync(
        LinuxRepositoryRoute route,
        CancellationToken cancellationToken = default)
    {
        return ViewModel.OpenRouteAsync(route, cancellationToken);
    }

    public Task UseThisFolderAsync(CancellationToken cancellationToken = default)
    {
        return ViewModel.AdoptRepositoryAsync(cancellationToken);
    }

    public LinuxRepositoryRoute ChooseAnotherFolder()
    {
        return new LinuxRepositoryRoute(
            LinuxRepositoryRouteKind.ChooseRepository,
            string.Empty,
            null);
    }

    public LinuxRepositoryRoute Cancel()
    {
        return LinuxRepositoryRoute.None;
    }
}
