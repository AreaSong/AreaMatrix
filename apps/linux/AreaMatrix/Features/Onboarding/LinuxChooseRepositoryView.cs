namespace AreaMatrix.Linux.Features.Onboarding;

public sealed class LinuxChooseRepositoryView
{
    private readonly ILinuxFolderPickerAdapter folderPicker;
    private readonly LinuxDefaultRepositoryPathProvider defaultPathProvider;
    private readonly List<LinuxRecentRepository> recentRepositories = [];

    public LinuxChooseRepositoryView(
        LinuxChooseRepositoryViewModel viewModel,
        ILinuxFolderPickerAdapter folderPicker,
        LinuxDefaultRepositoryPathProvider? defaultPathProvider = null)
    {
        ViewModel = viewModel;
        this.folderPicker = folderPicker;
        this.defaultPathProvider = defaultPathProvider ?? new LinuxDefaultRepositoryPathProvider();
    }

    public LinuxChooseRepositoryViewModel ViewModel { get; }

    public IReadOnlyList<LinuxRecentRepository> RecentRepositories => recentRepositories;

    public string DefaultRepositoryPath => defaultPathProvider.SuggestedRepositoryPath;

    public void SetRecentRepositories(IEnumerable<LinuxRecentRepository> repositories)
    {
        recentRepositories.Clear();
        recentRepositories.AddRange(repositories);
    }

    public async Task BrowseAsync(CancellationToken cancellationToken = default)
    {
        string? selectedPath;
        try
        {
            selectedPath = await folderPicker.PickFolderAsync(cancellationToken);
        }
        catch (LinuxFolderPickerException exception)
        {
            ViewModel.ReportFolderPickerError(exception.Message);
            return;
        }

        if (!string.IsNullOrWhiteSpace(selectedPath))
        {
            await ViewModel.CheckRepositoryPathAsync(selectedPath, cancellationToken);
        }
    }

    public Task UseDefaultPathAsync(CancellationToken cancellationToken = default)
    {
        return ViewModel.CheckRepositoryPathAsync(DefaultRepositoryPath, cancellationToken);
    }

    public Task SelectRecentRepositoryAsync(
        LinuxRecentRepository repository,
        CancellationToken cancellationToken = default)
    {
        return ViewModel.CheckRepositoryPathAsync(repository.RepoPath, cancellationToken);
    }

    public Task TypeRepositoryPathAsync(
        string path,
        CancellationToken cancellationToken = default)
    {
        return ViewModel.CheckRepositoryPathAsync(path, cancellationToken);
    }

    public Task ContinueAsync(CancellationToken cancellationToken = default)
    {
        return ViewModel.ContinueAsync(cancellationToken);
    }
}
