namespace AreaMatrix.Linux.Features.Recovery;

public sealed class MissingFileRecoveryView
{
    private readonly IMissingFileRecoveryFilePicker filePicker;

    public MissingFileRecoveryView(
        MissingFileRecoveryViewModel viewModel,
        IMissingFileRecoveryFilePicker? filePicker = null)
    {
        ViewModel = viewModel;
        this.filePicker = filePicker ?? new LinuxMissingFileRecoveryFilePicker();
    }

    public event Action<MissingFileRecoveryReport?>? CloseRequested;

    public MissingFileRecoveryViewModel ViewModel { get; }

    public MissingFileRecoveryRoute? Route { get; private set; }

    public async Task OpenRouteAsync(
        MissingFileRecoveryRoute route,
        CancellationToken cancellationToken = default)
    {
        Route = route;
        await ViewModel.OpenAsync(route.RepoPath, route.FileId, cancellationToken).ConfigureAwait(false);
    }

    public Task TryAgainAsync(CancellationToken cancellationToken = default)
    {
        return ViewModel.RefreshAsync(cancellationToken);
    }

    public async Task LocateFileAsync(CancellationToken cancellationToken = default)
    {
        string? selectedPath;
        try
        {
            selectedPath = await filePicker.PickReplacementFileAsync(cancellationToken)
                .ConfigureAwait(false);
        }
        catch (Exception exception) when (exception is not OperationCanceledException)
        {
            ViewModel.RecordLocateFileFailure(exception);
            return;
        }

        if (!string.IsNullOrWhiteSpace(selectedPath))
        {
            ViewModel.SelectRelinkPath(selectedPath);
        }
    }

    public async Task RelinkSelectedFileAsync(CancellationToken cancellationToken = default)
    {
        await ViewModel.RelinkSelectedFileAsync(cancellationToken).ConfigureAwait(false);
        CloseAfterSuccessfulChange();
    }

    public async Task RelinkSelectedPathAsync(
        string selectedPath,
        CancellationToken cancellationToken = default)
    {
        ViewModel.SelectRelinkPath(selectedPath);
        await RelinkSelectedFileAsync(cancellationToken).ConfigureAwait(false);
    }

    public async Task RemoveRecordAsync(
        bool confirmed,
        CancellationToken cancellationToken = default)
    {
        ViewModel.RemoveRecordConfirmed = confirmed;
        await ViewModel.RemoveRecordAsync(cancellationToken).ConfigureAwait(false);
        CloseAfterSuccessfulChange();
    }

    public void DecideLater()
    {
        CloseRequested?.Invoke(ViewModel.Report);
    }

    private void CloseAfterSuccessfulChange()
    {
        if (ViewModel.Report is { Status: MissingFileRecoveryStatus.Relinked or MissingFileRecoveryStatus.RecordRemoved }
            report)
        {
            CloseRequested?.Invoke(report);
        }
    }
}
