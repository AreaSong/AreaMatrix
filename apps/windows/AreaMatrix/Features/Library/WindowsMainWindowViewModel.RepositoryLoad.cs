using System.Threading;
using System.Threading.Tasks;
using AreaMatrix.Features.Onboarding;

namespace AreaMatrix.Features.Library;

public sealed partial class WindowsMainWindowViewModel
{
    private CancellationTokenSource? repositoryLoadCancellation;
    private long repositoryLoadGeneration;

    public async Task OpenRepositoryAsync(
        WindowsRepositoryRoute route,
        CancellationToken cancellationToken = default)
    {
        RepositoryLoadTransition transition = BeginRepositoryLoad(cancellationToken);
        try
        {
            CancellationToken loadCancellation = transition.Token;
            string repositoryPath = route.RepoPath;

            currentRoute = route;
            RepoPath = repositoryPath;
            RepoName = RepositoryName(repositoryPath);
            SearchQuery = string.Empty;
            SelectedCategory = null;
            OnPropertyChanged(nameof(CanOpenOneDriveStatus));
            OnPropertyChanged(nameof(OneDriveStatusRoute));
            OnPropertyChanged(nameof(CanOpenWatcherStatus));
            OnPropertyChanged(nameof(WatcherStatusRoute));
            OnPropertyChanged(nameof(ImportRoute));
            OnPropertyChanged(nameof(SelectedMissingFileRecoveryRoute));
            OnPropertyChanged(nameof(CanOpenMissingFileRecovery));
            await LoadSnapshotAsync(
                isInitialLoad: true,
                cancellationToken: loadCancellation,
                selectedFileId: null,
                generation: transition.Generation,
                repositoryPath: repositoryPath,
                category: null);
            if (!IsCurrentRepositoryLoad(transition))
            {
                return;
            }

            if (SyncConflictEntry is not null)
            {
                await SyncConflictEntry.OpenRepositoryAsync(repositoryPath, loadCancellation);
                if (!IsCurrentRepositoryLoad(transition))
                {
                    return;
                }

                OnPropertyChanged(nameof(SelectedFileSyncConflict));
            }
        }
        catch (OperationCanceledException) when (
            transition.Token.IsCancellationRequested
            && !cancellationToken.IsCancellationRequested)
        {
        }
        finally
        {
            EndRepositoryLoad(transition);
        }
    }

    private RepositoryLoadTransition BeginRepositoryLoad(CancellationToken cancellationToken)
    {
        if (repositoryLoadCancellation is { } previous)
        {
            previous.Cancel();
        }

        repositoryLoadGeneration += 1;
        CancellationTokenSource linked = CancellationTokenSource.CreateLinkedTokenSource(cancellationToken);
        repositoryLoadCancellation = linked;
        return new RepositoryLoadTransition(repositoryLoadGeneration, linked, linked.Token);
    }

    private bool IsCurrentRepositoryLoad(RepositoryLoadTransition transition)
    {
        return IsCurrentRepositoryLoad(transition.Generation)
            && ReferenceEquals(repositoryLoadCancellation, transition.Cancellation)
            && !transition.Token.IsCancellationRequested;
    }

    private bool IsCurrentRepositoryLoad(long generation)
    {
        return generation == repositoryLoadGeneration
            && repositoryLoadCancellation is not null
            && !repositoryLoadCancellation.IsCancellationRequested;
    }

    private void EndRepositoryLoad(RepositoryLoadTransition transition)
    {
        if (ReferenceEquals(repositoryLoadCancellation, transition.Cancellation))
        {
            repositoryLoadCancellation = null;
        }

        transition.Cancellation.Dispose();
    }

    private readonly record struct RepositoryLoadTransition(
        long Generation,
        CancellationTokenSource Cancellation,
        CancellationToken Token);
}
