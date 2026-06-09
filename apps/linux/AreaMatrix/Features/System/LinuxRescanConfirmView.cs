namespace AreaMatrix.Linux.Features.System;

public sealed class LinuxRescanConfirmView
{
    public LinuxRescanConfirmView(LinuxRescanConfirmViewModel viewModel)
    {
        ViewModel = viewModel;
    }

    public event Action<LinuxReindexReport?>? CloseRequested;

    public LinuxRescanConfirmViewModel ViewModel { get; }

    public LinuxRescanConfirmRequest? Request { get; private set; }

    public void OpenRequest(LinuxRescanConfirmRequest request)
    {
        Request = request;
        ViewModel.OpenRequest(request);
    }

    public void SetConfirmation(bool confirmed)
    {
        ViewModel.UserConfirmed = confirmed;
    }

    public Task<bool> RunRescanAsync(CancellationToken cancellationToken = default)
    {
        return ViewModel.RunRescanAsync(cancellationToken);
    }

    public void Close()
    {
        CloseRequested?.Invoke(ViewModel.Result);
    }
}
