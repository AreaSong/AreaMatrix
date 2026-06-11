namespace AreaMatrix.Linux.Features.Onboarding;

public sealed class RepositoryInitConfirmView
{
    public RepositoryInitConfirmView(RepositoryInitConfirmViewModel viewModel)
    {
        ViewModel = viewModel;
    }

    public RepositoryInitConfirmViewModel ViewModel { get; }

    public Task OpenRouteAsync(
        LinuxRepositoryRoute route,
        CancellationToken cancellationToken = default)
    {
        return ViewModel.OpenRouteAsync(route, cancellationToken);
    }

    public Task CreateRepositoryAsync(CancellationToken cancellationToken = default)
    {
        return ViewModel.CreateRepositoryAsync(cancellationToken);
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
