namespace AreaMatrix.Linux.Features.Library;

public sealed class LinuxMainWindow
{
    public LinuxMainWindow(LinuxMainWindowViewModel viewModel)
    {
        ViewModel = viewModel;
    }

    public LinuxMainWindowViewModel ViewModel { get; }

    public Task OpenRepositoryAsync(
        Onboarding.LinuxRepositoryRoute route,
        CancellationToken cancellationToken = default)
    {
        return ViewModel.OpenRepositoryAsync(route, cancellationToken);
    }

    public Task RefreshAsync(CancellationToken cancellationToken = default)
    {
        return ViewModel.RefreshAsync(cancellationToken);
    }

    public Task SearchAsync(
        string query,
        CancellationToken cancellationToken = default)
    {
        ViewModel.SearchQuery = query;
        return ViewModel.RunSearchAsync(cancellationToken);
    }

    public Task SelectCategoryAsync(
        DesktopCategoryNode? category,
        CancellationToken cancellationToken = default)
    {
        return ViewModel.SelectCategoryAsync(category, cancellationToken);
    }

    public Task SelectFileAsync(
        DesktopFileEntry? file,
        CancellationToken cancellationToken = default)
    {
        return ViewModel.SelectFileAsync(file, cancellationToken);
    }

    public Task LoadMoreAsync(CancellationToken cancellationToken = default)
    {
        return ViewModel.LoadMoreAsync(cancellationToken);
    }
}
