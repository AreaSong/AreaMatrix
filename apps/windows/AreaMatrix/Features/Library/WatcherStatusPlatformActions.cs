using System;
using System.Threading;
using System.Threading.Tasks;

namespace AreaMatrix.Features.Library;

public sealed partial class WatcherStatusViewModel
{
    public bool CanExportDiagnostics => !IsBusy && Snapshot is not null;

    public bool CanOpenRepositoryFolder => !IsBusy
        && Snapshot is not null
        && !Snapshot.IsPathMissing
        && !string.IsNullOrWhiteSpace(RepoPath);

    public string? LastDiagnosticsExportPath { get; private set; }

    public async Task<bool> ExportDiagnosticsAsync(CancellationToken cancellationToken = default)
    {
        if (!CanExportDiagnostics || Snapshot is null)
        {
            return false;
        }

        Error = null;
        try
        {
            LastDiagnosticsExportPath = await diagnostics
                .ExportDiagnosticsAsync(RepoPath, Snapshot, cancellationToken)
                .ConfigureAwait(false);
            OnPropertyChanged(nameof(LastDiagnosticsExportPath));
            return true;
        }
        catch (Exception exception) when (exception is not OperationCanceledException)
        {
            ReportPlatformActionError("Export diagnostics", exception);
            return false;
        }
    }

    public async Task<bool> OpenRepositoryFolderAsync(CancellationToken cancellationToken = default)
    {
        if (!CanOpenRepositoryFolder)
        {
            return false;
        }

        Error = null;
        try
        {
            await diagnostics
                .OpenRepositoryFolderAsync(RepoPath, cancellationToken)
                .ConfigureAwait(false);
            return true;
        }
        catch (Exception exception) when (exception is not OperationCanceledException)
        {
            ReportPlatformActionError("Open repository folder", exception);
            return false;
        }
    }
}
