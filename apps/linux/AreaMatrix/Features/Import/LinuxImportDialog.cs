namespace AreaMatrix.Linux.Features.Import;

public sealed class LinuxImportDialog
{
    private readonly ILinuxImportPickerAdapter pickerAdapter;
    private bool closeWhenDoneRequested;

    public LinuxImportDialog(
        LinuxImportViewModel viewModel,
        ILinuxImportFileProbe fileProbe,
        ILinuxImportPickerAdapter? pickerAdapter = null)
    {
        ViewModel = viewModel;
        FileProbe = fileProbe;
        this.pickerAdapter = pickerAdapter ?? new LinuxSystemImportPickerAdapter();
    }

    public event Action<LinuxImportCloseRequest>? CloseRequested;

    public LinuxImportViewModel ViewModel { get; }

    public ILinuxImportFileProbe FileProbe { get; }

    public bool CloseWhenDoneRequested => closeWhenDoneRequested;

    public void OpenRepository(string repoPath)
    {
        ViewModel.OpenRepository(repoPath);
    }

    public async Task OpenRepositoryWithSourcesAsync(
        string repoPath,
        IEnumerable<string> sourcePaths,
        CancellationToken cancellationToken = default)
    {
        OpenRepository(repoPath);
        await AddPathsAndPrepareAsync(sourcePaths, cancellationToken).ConfigureAwait(false);
    }

    public async Task AddFilesAsync(CancellationToken cancellationToken = default)
    {
        IReadOnlyList<string> paths = await pickerAdapter.PickFilesAsync(cancellationToken)
            .ConfigureAwait(false);
        await AddPathsAndPrepareAsync(paths, cancellationToken).ConfigureAwait(false);
    }

    public async Task AddFolderAsync(CancellationToken cancellationToken = default)
    {
        string? folder = await pickerAdapter.PickFolderAsync(cancellationToken).ConfigureAwait(false);
        if (!string.IsNullOrWhiteSpace(folder))
        {
            await AddPathsAndPrepareAsync([folder], cancellationToken).ConfigureAwait(false);
        }
    }

    public Task DropPathsAsync(
        IEnumerable<string> sourcePaths,
        CancellationToken cancellationToken = default)
    {
        return AddPathsAndPrepareAsync(sourcePaths, cancellationToken);
    }

    public void AddSelectedPaths(IEnumerable<string> sourcePaths)
    {
        AppendSelectedPaths(sourcePaths);
    }

    public void SetImportMode(DesktopImportMode mode)
    {
        ViewModel.Mode = mode;
    }

    public void SetDuplicateStrategy(DesktopImportDuplicateStrategy strategy)
    {
        ViewModel.DuplicateStrategy = strategy;
    }

    public void SetTargetCategory(string category)
    {
        ViewModel.TargetCategory = category;
    }

    public void SetTargetDirectory(string directory)
    {
        ViewModel.TargetDirectory = directory;
    }

    public void SetPreserveFolderStructure(bool preserve)
    {
        ViewModel.PreserveFolderStructure = preserve;
    }

    public void ConfirmMoveOriginals(bool confirmed)
    {
        ViewModel.MoveConfirmed = confirmed;
    }

    public Task PreparePreviewAsync(CancellationToken cancellationToken = default)
    {
        return ViewModel.PreparePreviewAsync(cancellationToken);
    }

    public Task ImportAsync(CancellationToken cancellationToken = default)
    {
        return ImportAndCloseIfRequestedAsync(cancellationToken);
    }

    public Task RetryFailedAsync(
        DesktopImportResult failedResult,
        CancellationToken cancellationToken = default)
    {
        return ViewModel.RetryFailedAsync(failedResult, cancellationToken);
    }

    public LinuxImportCloseRequest CreateCloseRequest()
    {
        return ViewModel.CreateCloseRequest();
    }

    public void UseCopyInstead()
    {
        ViewModel.UseCopyInstead();
    }

    public void CancelOrClose()
    {
        if (ViewModel.IsImporting)
        {
            closeWhenDoneRequested = true;
            return;
        }

        RequestClose();
    }

    private async Task AddPathsAndPrepareAsync(
        IEnumerable<string> sourcePaths,
        CancellationToken cancellationToken)
    {
        AppendSelectedPaths(sourcePaths);
        if (ViewModel.CanPrepare)
        {
            await PreparePreviewAsync(cancellationToken).ConfigureAwait(false);
        }
    }

    private void AppendSelectedPaths(IEnumerable<string> sourcePaths)
    {
        IReadOnlyList<DesktopImportSource> incoming = FileProbe.ExpandSources(sourcePaths);
        ViewModel.SetSources(ViewModel.Sources.Concat(incoming));
    }

    private async Task ImportAndCloseIfRequestedAsync(CancellationToken cancellationToken)
    {
        await ViewModel.ImportAsync(cancellationToken).ConfigureAwait(false);
        if (closeWhenDoneRequested && !ViewModel.IsImporting)
        {
            RequestClose();
        }
    }

    private void RequestClose()
    {
        closeWhenDoneRequested = false;
        CloseRequested?.Invoke(CreateCloseRequest());
    }
}
