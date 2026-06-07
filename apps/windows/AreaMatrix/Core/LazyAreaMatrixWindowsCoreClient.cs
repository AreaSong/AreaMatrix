using System;
using System.Threading;
using System.Threading.Tasks;
using AreaMatrix.Features.Onboarding;

namespace AreaMatrix.Core;

internal sealed class LazyAreaMatrixWindowsCoreClient : IAreaMatrixWindowsCoreClient, IDisposable
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

    public Task InitRepoAsync(
        string repoPath,
        CoreRepoInitOptions options,
        CancellationToken cancellationToken = default)
    {
        return Current.InitRepoAsync(repoPath, options, cancellationToken);
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
