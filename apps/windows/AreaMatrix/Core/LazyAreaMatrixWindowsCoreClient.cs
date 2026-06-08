using System;
using System.Threading;
using System.Threading.Tasks;
using AreaMatrix.Features.Library;
using AreaMatrix.Features.Onboarding;

namespace AreaMatrix.Core;

internal sealed class LazyAreaMatrixWindowsCoreClient :
    IAreaMatrixWindowsCoreClient,
    IAreaMatrixDesktopQueryCoreClient,
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
