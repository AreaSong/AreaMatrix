namespace AreaMatrix.Linux.Features.Onboarding;

public sealed class LocalFolderNoticeView
{
    private readonly ILinuxFolderOpener folderOpener;

    public LocalFolderNoticeView(
        LocalFolderNoticeViewModel viewModel,
        ILinuxFolderOpener? folderOpener = null)
    {
        ViewModel = viewModel;
        this.folderOpener = folderOpener ?? new LinuxSystemFolderOpener();
    }

    public LocalFolderNoticeViewModel ViewModel { get; }

    public Task LoadAsync(
        LinuxRepositoryRoute route,
        CancellationToken cancellationToken = default)
    {
        return ViewModel.LoadRouteAsync(route, cancellationToken);
    }

    public Task<bool> ContinueAsync(CancellationToken cancellationToken = default)
    {
        return ViewModel.ContinueAsync(cancellationToken);
    }

    public void ChooseAnotherFolder()
    {
        ViewModel.ChooseAnotherFolder();
    }

    public async Task OpenFolderAsync(CancellationToken cancellationToken = default)
    {
        try
        {
            await folderOpener
                .OpenFolderAsync(ViewModel.RepositoryPath, cancellationToken)
                .ConfigureAwait(false);
        }
        catch (LinuxFolderOpenException exception)
        {
            ViewModel.ReportOpenFolderError(exception.Message);
        }
    }
}
