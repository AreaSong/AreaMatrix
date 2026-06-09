using System.Collections.Generic;
using System.ComponentModel;
using System.Linq;
using System.Runtime.CompilerServices;
using System.Threading;
using System.Threading.Tasks;
using AreaMatrix.Features.Library;

namespace AreaMatrix.Features.Conflicts;

public sealed class SyncConflictEntryViewModel : INotifyPropertyChanged
{
    private readonly ISyncConflictEntryCoreBridge coreBridge;
    private string repoPath = string.Empty;
    private bool isLoading;
    private bool isBannerDismissed;
    private IReadOnlyList<SyncConflictEntryConflict> conflicts = [];
    private SyncConflictEntryError? error;

    public SyncConflictEntryViewModel(ISyncConflictEntryCoreBridge coreBridge)
    {
        this.coreBridge = coreBridge;
    }

    public event PropertyChangedEventHandler? PropertyChanged;

    public IReadOnlyList<SyncConflictEntryConflict> Conflicts
    {
        get => conflicts;
        private set
        {
            if (SetProperty(ref conflicts, value))
            {
                OnDerivedStateChanged();
            }
        }
    }

    public SyncConflictEntryError? Error
    {
        get => error;
        private set
        {
            if (SetProperty(ref error, value))
            {
                OnDerivedStateChanged();
            }
        }
    }

    public bool IsLoading
    {
        get => isLoading;
        private set
        {
            if (SetProperty(ref isLoading, value))
            {
                OnPropertyChanged(nameof(StatusText));
            }
        }
    }

    public bool IsBannerDismissed
    {
        get => isBannerDismissed;
        private set
        {
            if (SetProperty(ref isBannerDismissed, value))
            {
                OnPropertyChanged(nameof(IsBannerVisible));
            }
        }
    }

    public bool HasConflicts => Conflicts.Count > 0;

    public bool IsBannerVisible => HasConflicts && !IsBannerDismissed;

    public SyncConflictEntryConflict? FirstReviewableConflict =>
        Conflicts.FirstOrDefault(conflict => conflict.NormalizedConflictId is not null);

    public string StatusText
    {
        get
        {
            if (IsLoading)
            {
                return "Checking conflicts...";
            }

            if (Error is not null)
            {
                return "Could not load review items";
            }

            return HasConflicts
                ? $"{Conflicts.Count} sync conflict(s) need review"
                : "No items need review.";
        }
    }

    public async Task OpenRepositoryAsync(
        string repositoryPath,
        CancellationToken cancellationToken = default)
    {
        repoPath = repositoryPath;
        IsBannerDismissed = false;
        await RefreshAsync(cancellationToken).ConfigureAwait(false);
    }

    public async Task RefreshAsync(CancellationToken cancellationToken = default)
    {
        if (string.IsNullOrWhiteSpace(repoPath))
        {
            return;
        }

        IsLoading = true;
        Error = null;
        try
        {
            IReadOnlyList<SyncConflictEntryConflict> loaded = await coreBridge
                .DetectSyncConflictsAsync(repoPath, cancellationToken)
                .ConfigureAwait(false);
            Conflicts = loaded
                .Where(conflict => conflict.Status == SyncConflictEntryStatus.NeedsReview)
                .OrderByDescending(conflict => conflict.Severity)
                .ThenByDescending(conflict => conflict.DetectedAt ?? 0)
                .ToArray();
        }
        catch (Exception exception) when (exception is not OperationCanceledException)
        {
            Error = SyncConflictEntryError.FromException(exception);
        }
        finally
        {
            IsLoading = false;
        }
    }

    public void DismissBanner()
    {
        IsBannerDismissed = true;
    }

    public SyncConflictEntryReviewRoute? ReviewRouteFor(SyncConflictEntryConflict? conflict)
    {
        if (conflict?.NormalizedConflictId is not { } conflictId)
        {
            return null;
        }

        return new SyncConflictEntryReviewRoute(repoPath, conflictId, conflict.PrimaryPath);
    }

    public SyncConflictEntryConflict? DetailConflictFor(DesktopFileEntry? file)
    {
        return file is null ? null : Conflicts.FirstOrDefault(conflict => conflict.Matches(file));
    }

    private void OnDerivedStateChanged()
    {
        OnPropertyChanged(nameof(HasConflicts));
        OnPropertyChanged(nameof(IsBannerVisible));
        OnPropertyChanged(nameof(FirstReviewableConflict));
        OnPropertyChanged(nameof(StatusText));
    }

    private bool SetProperty<T>(
        ref T storage,
        T value,
        [CallerMemberName] string propertyName = "")
    {
        if (EqualityComparer<T>.Default.Equals(storage, value))
        {
            return false;
        }

        storage = value;
        OnPropertyChanged(propertyName);
        return true;
    }

    private void OnPropertyChanged([CallerMemberName] string propertyName = "")
    {
        PropertyChanged?.Invoke(this, new PropertyChangedEventArgs(propertyName));
    }
}
