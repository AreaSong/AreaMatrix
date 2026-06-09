using System;
using System.Threading;
using System.Threading.Tasks;
using AreaMatrix.Features.Import;
using AreaMatrix.Features.Library;
using AreaMatrix.Features.Onboarding;
using AreaMatrix.Features.Help;

namespace AreaMatrix.Core;

internal sealed class LazyAreaMatrixWindowsCoreClient :
    IAreaMatrixWindowsCoreClient,
    IAreaMatrixBindingContractCoreClient,
    IAreaMatrixDesktopQueryCoreClient,
    IAreaMatrixDesktopImportCoreClient,
    IAreaMatrixWatcherStatusCoreClient,
    IDisposable
{
    private readonly object sync = new();
    private AreaMatrixNativeCoreClient? client;

    public Task<CoreRepoPathValidation> ValidateRepoPathAsync(
        string repoPath,
        CancellationToken cancellationToken = default)
    {
        return Current.ValidateRepoPathAsync(repoPath, cancellationToken);
    }

    public Task<CoreRepoConfig> LoadConfigAsync(
        string repoPath,
        CancellationToken cancellationToken = default)
    {
        return Current.LoadConfigAsync(repoPath, cancellationToken);
    }

    public Task<CoreCloudStorageState> DetectCloudStorageStateAsync(
        string repoPath,
        CancellationToken cancellationToken = default)
    {
        return Current.DetectCloudStorageStateAsync(repoPath, cancellationToken);
    }

    public Task<CoreCloudStorageState> AcknowledgeOneDriveRiskNoticeAsync(
        string repoPath,
        CancellationToken cancellationToken = default)
    {
        return Current.AcknowledgeOneDriveRiskNoticeAsync(repoPath, cancellationToken);
    }

    public Task InitRepoAsync(
        string repoPath,
        CoreRepoInitOptions options,
        CancellationToken cancellationToken = default)
    {
        return Current.InitRepoAsync(repoPath, options, cancellationToken);
    }

    public Task<CoreBindingContractReport> InspectBindingContractAsync(
        string targetPlatform,
        long bindingVersion,
        CancellationToken cancellationToken = default)
    {
        return Current.InspectBindingContractAsync(targetPlatform, bindingVersion, cancellationToken);
    }

    public Task<CorePlatformCapabilities> GetPlatformCapabilitiesAsync(
        string platform,
        string appVersion,
        CancellationToken cancellationToken = default)
    {
        return Current.GetPlatformCapabilitiesAsync(platform, appVersion, cancellationToken);
    }

    public Task<IReadOnlyList<CoreDesktopFileEntry>> ListFilesAsync(
        string repoPath,
        CoreDesktopFileFilter filter,
        CancellationToken cancellationToken = default)
    {
        return Current.ListFilesAsync(repoPath, filter, cancellationToken);
    }

    public Task<CoreDesktopFileEntry> GetFileAsync(
        string repoPath,
        long fileId,
        CancellationToken cancellationToken = default)
    {
        return Current.GetFileAsync(repoPath, fileId, cancellationToken);
    }

    public Task<string> ListTreeJsonAsync(
        string repoPath,
        string locale,
        CancellationToken cancellationToken = default)
    {
        return Current.ListTreeJsonAsync(repoPath, locale, cancellationToken);
    }

    public Task<CoreDesktopSearchResultPage> SearchFilesAsync(
        string repoPath,
        string query,
        CoreDesktopSearchFilter filter,
        string sort,
        CoreDesktopSearchPagination pagination,
        CancellationToken cancellationToken = default)
    {
        return Current.SearchFilesAsync(repoPath, query, filter, sort, pagination, cancellationToken);
    }

    public Task<CoreDesktopClassifyResult> PredictCategoryAsync(
        string repoPath,
        string filename,
        CancellationToken cancellationToken = default)
    {
        return Current.PredictCategoryAsync(repoPath, filename, cancellationToken);
    }

    public Task<CoreDesktopImportResult> ImportFileWithResultAsync(
        string repoPath,
        string sourcePath,
        CoreDesktopImportOptions options,
        CancellationToken cancellationToken = default)
    {
        return Current.ImportFileWithResultAsync(repoPath, sourcePath, options, cancellationToken);
    }

    public Task<CoreDesktopImportConflictBatchPreviewReport> PreviewImportConflictBatchAsync(
        string repoPath,
        CoreDesktopImportConflictBatchPreviewRequest request,
        CancellationToken cancellationToken = default)
    {
        return Current.PreviewImportConflictBatchAsync(repoPath, request, cancellationToken);
    }

    public Task<CoreDesktopImportConflictBatchApplyReport> ApplyImportConflictBatchAsync(
        string repoPath,
        CoreDesktopImportConflictBatchApplyRequest request,
        string previewToken,
        CancellationToken cancellationToken = default)
    {
        return Current.ApplyImportConflictBatchAsync(repoPath, request, previewToken, cancellationToken);
    }

    public Task<CoreWatcherStatusSnapshot> RecordWatcherHealthAsync(
        string repoPath,
        CoreWatcherStatusHealthSignal signal,
        CancellationToken cancellationToken = default)
    {
        return Current.RecordWatcherHealthAsync(repoPath, signal, cancellationToken);
    }

    public Task<CoreManualRescanPreviewReport> PreviewManualRescanAsync(
        string repoPath,
        CancellationToken cancellationToken = default)
    {
        return Current.PreviewManualRescanAsync(repoPath, cancellationToken);
    }

    public Task<CoreReindexReport> ReindexFromFilesystemAsync(
        string repoPath,
        CancellationToken cancellationToken = default)
    {
        return Current.ReindexFromFilesystemAsync(repoPath, cancellationToken);
    }

    public Task<CoreScanSession?> GetLatestScanSessionAsync(
        string repoPath,
        CancellationToken cancellationToken = default)
    {
        return Current.GetLatestScanSessionAsync(repoPath, cancellationToken);
    }

    public Task<CoreReindexReport> ResumeScanSessionAsync(
        string repoPath,
        long scanSessionId,
        CancellationToken cancellationToken = default)
    {
        return Current.ResumeScanSessionAsync(repoPath, scanSessionId, cancellationToken);
    }

    public void Dispose()
    {
        lock (sync)
        {
            client?.Dispose();
            client = null;
        }
    }

    private AreaMatrixNativeCoreClient Current
    {
        get
        {
            lock (sync)
            {
                client ??= new AreaMatrixNativeCoreClient();
                return client;
            }
        }
    }
}
