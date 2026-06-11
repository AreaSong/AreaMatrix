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
    private bool isPreviewingReplace;
    private bool isApplyingReplace;
    private bool isBannerDismissed;
    private bool replaceConfirmed;
    private IReadOnlyList<SyncConflictEntryConflict> conflicts = [];
    private SyncConflictEntryReviewRoute? activeReviewRoute;
    private SyncConflictResolutionPreviewReport? replacePreview;
    private SyncConflictReplaceConfirmation? pendingReplaceConfirmation;
    private SyncConflictResolveReport? replaceResult;
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

    public bool IsPreviewingReplace
    {
        get => isPreviewingReplace;
        private set
        {
            if (SetProperty(ref isPreviewingReplace, value))
            {
                OnReplaceStateChanged();
            }
        }
    }

    public bool IsApplyingReplace
    {
        get => isApplyingReplace;
        private set
        {
            if (SetProperty(ref isApplyingReplace, value))
            {
                OnReplaceStateChanged();
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

    public SyncConflictEntryReviewRoute? ActiveReviewRoute
    {
        get => activeReviewRoute;
        private set
        {
            if (SetProperty(ref activeReviewRoute, value))
            {
                OnReplaceStateChanged();
            }
        }
    }

    public SyncConflictResolutionPreviewReport? ReplacePreview
    {
        get => replacePreview;
        private set
        {
            if (SetProperty(ref replacePreview, value))
            {
                OnReplaceStateChanged();
            }
        }
    }

    public SyncConflictReplaceConfirmation? PendingReplaceConfirmation
    {
        get => pendingReplaceConfirmation;
        private set
        {
            if (SetProperty(ref pendingReplaceConfirmation, value))
            {
                OnReplaceStateChanged();
            }
        }
    }

    public SyncConflictResolveReport? ReplaceResult
    {
        get => replaceResult;
        private set
        {
            if (SetProperty(ref replaceResult, value))
            {
                OnReplaceStateChanged();
            }
        }
    }

    public bool ReplaceConfirmed
    {
        get => replaceConfirmed;
        private set
        {
            if (SetProperty(ref replaceConfirmed, value))
            {
                OnReplaceStateChanged();
            }
        }
    }

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

    public bool CanConfirmReplacePlan => ReplacePreview is { } preview
        && preview.Resolution == SyncConflictResolutionStrategy.UseIncoming
        && preview.ReplacePlan is not null
        && preview.NormalizedPreviewToken is not null
        && preview.RequiresReplaceConfirmation
        && preview.HasRecoverableOldVersion
        && (preview.CanApply || preview.BlocksOnlyForReplaceConfirmation)
        && !IsPreviewingReplace
        && !IsApplyingReplace;

    public bool CanApplyReplace => PendingReplaceConfirmation is not null
        && ReplaceConfirmed
        && !IsPreviewingReplace
        && !IsApplyingReplace;

    public string ReplaceStatusText
    {
        get
        {
            if (IsPreviewingReplace)
            {
                return "Checking recovery options...";
            }

            if (IsApplyingReplace)
            {
                return "Applying replace through AreaMatrix Core...";
            }

            if (ReplaceResult is { } result)
            {
                return $"Resolved {result.ConflictId}; change log: {result.ChangeLogAction}";
            }

            if (PendingReplaceConfirmation is { } confirmation)
            {
                return $"Confirm Replace: {confirmation.ReplacePlan.OldPath} -> {confirmation.ReplacePlan.NewPath}";
            }

            if (ReplacePreview is { } preview)
            {
                return ReplaceDisabledReason(preview) ?? "Replace plan is ready for confirmation.";
            }

            if (ActiveReviewRoute is { } route)
            {
                return $"Review sync conflict: {route.PrimaryPath} ({route.ConflictId})";
            }

            return StatusText;
        }
    }

    public string ReplacePlanText
    {
        get
        {
            if (ReplacePreview?.ReplacePlan is not { } plan)
            {
                return "Replace is unavailable until Core returns a complete replace plan.";
            }

            return $"Old file path: {plan.OldPath}\n"
                + $"New file path: {plan.NewPath}\n"
                + $"Old hash: {plan.OldHashText}\n"
                + $"New hash: {plan.NewHashText}\n"
                + $"Affected record: {plan.AffectedRecordText}\n"
                + $"Conflict or import item: {ReplacePreview.ConflictId}\n"
                + $"Old version will be kept at: {plan.BackupTargetText}\n"
                + $"Database update: {plan.DatabaseUpdate}\n"
                + $"Change log: {plan.ChangeLogAction}\n"
                + $"Recovery note: {plan.RecoveryNote}";
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

    public async Task OpenReviewRouteAsync(
        SyncConflictEntryReviewRoute route,
        CancellationToken cancellationToken = default)
    {
        ActiveReviewRoute = route;
        ReplacePreview = null;
        PendingReplaceConfirmation = null;
        ReplaceResult = null;
        ReplaceConfirmed = false;
        Error = null;
        IsPreviewingReplace = true;

        try
        {
            ReplacePreview = await coreBridge
                .PreviewSyncConflictResolutionAsync(
                    route.RepoPath,
                    route.ConflictId,
                    SyncConflictResolutionStrategy.UseIncoming,
                    cancellationToken)
                .ConfigureAwait(false);
        }
        catch (Exception exception) when (exception is not OperationCanceledException)
        {
            Error = SyncConflictEntryError.FromException(exception);
        }
        finally
        {
            IsPreviewingReplace = false;
        }
    }

    public void ConfirmReplacePlan(bool understandsReplace)
    {
        ReplaceConfirmed = understandsReplace;
        if (!understandsReplace || !CanConfirmReplacePlan || ReplacePreview is not { } preview)
        {
            PendingReplaceConfirmation = null;
            return;
        }

        if (preview.ReplacePlan is not { } plan || preview.NormalizedPreviewToken is not { } token)
        {
            PendingReplaceConfirmation = null;
            return;
        }

        PendingReplaceConfirmation = new SyncConflictReplaceConfirmation(
            preview.ConflictId,
            token,
            ConfirmationId(preview.ConflictId, token),
            plan);
    }

    public async Task ApplyReplaceAsync(CancellationToken cancellationToken = default)
    {
        if (!CanApplyReplace || PendingReplaceConfirmation is not { } confirmation)
        {
            return;
        }

        IsApplyingReplace = true;
        Error = null;
        try
        {
            ReplaceResult = await coreBridge
                .ResolveSyncConflictAsync(
                    ActiveReviewRoute?.RepoPath ?? repoPath,
                    confirmation.ConflictId,
                    new SyncConflictResolutionRequest(
                        SyncConflictResolutionStrategy.UseIncoming,
                        confirmation.PreviewToken,
                        true,
                        confirmation.ConfirmationId),
                    cancellationToken)
                .ConfigureAwait(false);
            Conflicts = Conflicts
                .Where(conflict => !string.Equals(
                    conflict.ConflictId,
                    confirmation.ConflictId,
                    StringComparison.Ordinal))
                .ToArray();
            PendingReplaceConfirmation = null;
            ReplaceConfirmed = false;
        }
        catch (Exception exception) when (exception is not OperationCanceledException)
        {
            Error = SyncConflictEntryError.FromException(exception);
        }
        finally
        {
            IsApplyingReplace = false;
        }
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

    private void OnReplaceStateChanged()
    {
        OnPropertyChanged(nameof(CanConfirmReplacePlan));
        OnPropertyChanged(nameof(CanApplyReplace));
        OnPropertyChanged(nameof(ReplaceStatusText));
        OnPropertyChanged(nameof(ReplacePlanText));
    }

    private static string? ReplaceDisabledReason(SyncConflictResolutionPreviewReport preview)
    {
        if (preview.ReplacePlan is null)
        {
            return "Could not build replace plan.";
        }

        if (preview.NormalizedPreviewToken is null)
        {
            return "Replace preflight expired. Try again.";
        }

        if (!preview.HasRecoverableOldVersion)
        {
            return "Recycle Bin is unavailable and Core safety backup is unavailable. Use Keep both.";
        }

        if (!preview.CanApply && !preview.BlocksOnlyForReplaceConfirmation)
        {
            return preview.BlockedReason ?? "Replace is not available.";
        }

        if (!preview.RequiresReplaceConfirmation)
        {
            return "Replace requires second confirmation.";
        }

        return null;
    }

    private static string ConfirmationId(string conflictId, string previewToken)
    {
        string safeToken = new(previewToken
            .Where(character => char.IsLetterOrDigit(character) || character == '-' || character == '_')
            .Take(24)
            .ToArray());
        return $"S4-X-09-C4-21-{conflictId}-{safeToken}";
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
