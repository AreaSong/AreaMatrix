using System;
using System.Collections.Generic;
using System.Linq;
using System.Threading;
using System.Threading.Tasks;
using AreaMatrix.Features.Library;

namespace AreaMatrix.Features.Import;

public sealed partial class WindowsImportViewModel
{
    private DesktopImportReplaceConfirmation? pendingReplaceConfirmation;
    private DesktopImportConflictBatchApplyReport? replaceResult;
    private bool replaceConfirmed;
    private bool isReplacing;

    public DesktopImportReplaceConfirmation? PendingReplaceConfirmation
    {
        get => pendingReplaceConfirmation;
        private set
        {
            if (SetProperty(ref pendingReplaceConfirmation, value))
            {
                OnPropertyChanged(nameof(HasPendingReplaceConfirmation));
                OnPropertyChanged(nameof(ReplaceStatusText));
                OnPropertyChanged(nameof(CanApplyReplace));
            }
        }
    }

    public DesktopImportConflictBatchApplyReport? ReplaceResult
    {
        get => replaceResult;
        private set
        {
            if (SetProperty(ref replaceResult, value))
            {
                OnPropertyChanged(nameof(ResultSummaryText));
                OnPropertyChanged(nameof(StatusText));
            }
        }
    }

    public bool ReplaceConfirmed
    {
        get => replaceConfirmed;
        set
        {
            if (SetProperty(ref replaceConfirmed, value))
            {
                OnPropertyChanged(nameof(CanApplyReplace));
            }
        }
    }

    public bool IsReplacing
    {
        get => isReplacing;
        private set
        {
            if (SetProperty(ref isReplacing, value))
            {
                OnPropertyChanged(nameof(CanPreviewReplace));
                OnPropertyChanged(nameof(CanApplyReplace));
                OnPropertyChanged(nameof(StatusText));
            }
        }
    }

    public bool HasNameConflicts => PreviewItems.Any(item => item.Status == DesktopImportPreviewStatus.NameConflict);

    public bool HasPendingReplaceConfirmation => PendingReplaceConfirmation is not null;

    public bool CanPreviewReplace => !IsPreparing
        && !IsImporting
        && !IsReplacing
        && PendingReplaceConfirmation is null
        && ReplaceResult is null
        && !string.IsNullOrWhiteSpace(RepoPath)
        && PreviewItems.Any(item => item.CanPreviewReplace);

    public bool CanApplyReplace => !IsPreparing
        && !IsImporting
        && !IsReplacing
        && ReplaceConfirmed
        && PendingReplaceConfirmation?.CanConfirm == true
        && (!RequiresMoveConfirmation || MoveConfirmed && MovePreflight.CanMove);

    public string ReplaceStatusText
    {
        get
        {
            if (ReplaceResult is { } result)
            {
                return result.SummaryText;
            }

            if (PendingReplaceConfirmation is { } confirmation)
            {
                return confirmation.CanConfirm
                    ? confirmation.Summary
                    : confirmation.BlockedReason;
            }

            if (!HasNameConflicts)
            {
                return "No name conflicts require Replace.";
            }

            if (CanPreviewReplace)
            {
                return "Replace requires second confirmation before the existing file moves to Recycle Bin.";
            }

            return FirstReplaceBlockedReason()
                ?? "Replace is unavailable until Core provides an import session and conflict id.";
        }
    }

    public async Task PreviewReplaceAsync(CancellationToken cancellationToken = default)
    {
        if (!CanPreviewReplace)
        {
            return;
        }

        IsReplacing = true;
        Error = null;
        ReplaceResult = null;
        ReplaceConfirmed = false;
        try
        {
            DesktopImportPreviewItem item = FirstReplaceConflict();
            PendingReplaceConfirmation = await PreviewCoreSessionReplaceAsync(item, cancellationToken)
                .ConfigureAwait(false);
        }
        catch (Exception exception) when (exception is not OperationCanceledException)
        {
            Error = DesktopImportError.FromException(exception);
            PendingReplaceConfirmation = null;
        }
        finally
        {
            IsReplacing = false;
        }
    }

    public async Task ApplyReplaceAsync(CancellationToken cancellationToken = default)
    {
        if (!CanApplyReplace || PendingReplaceConfirmation is not { } confirmation)
        {
            return;
        }

        IsReplacing = true;
        Error = null;
        try
        {
            if (confirmation.Preview is not { } preview)
            {
                Error = new DesktopImportError(
                    DesktopImportErrorKind.Conflict,
                    "Replace requires Core import conflict preview before applying.");
                return;
            }

            DesktopImportConflictBatchApplyReport report = await coreBridge
                .ApplyReplaceConflictAsync(
                    RepoPath,
                    ReplaceApplyRequest(confirmation.Item),
                    preview.PreviewToken,
                    cancellationToken)
                .ConfigureAwait(false);
            ReplaceResult = report;
            Results = ResultsFromReplaceReport(report, confirmation.Item);

            PendingReplaceConfirmation = null;
            ReplaceConfirmed = false;
        }
        catch (Exception exception) when (exception is not OperationCanceledException)
        {
            Error = DesktopImportError.FromException(exception);
        }
        finally
        {
            IsReplacing = false;
        }
    }

    public void CancelReplace()
    {
        PendingReplaceConfirmation = null;
        ReplaceConfirmed = false;
    }

    private void ClearReplaceState()
    {
        ReplaceResult = null;
        PendingReplaceConfirmation = null;
        ReplaceConfirmed = false;
    }

    private void NotifyReplacePreviewStateChanged()
    {
        OnPropertyChanged(nameof(HasNameConflicts));
        OnPropertyChanged(nameof(CanPreviewReplace));
        OnPropertyChanged(nameof(ReplaceStatusText));
    }

    private IReadOnlyList<DesktopImportSource> SourcesForPreview()
    {
        if (sources.Count > 0)
        {
            return sources;
        }

        return SourcePaths().Select(path => new DesktopImportSource(path)).ToArray();
    }

    private string? FirstReplaceBlockedReason()
    {
        return PreviewItems
            .Where(item => item.Status == DesktopImportPreviewStatus.NameConflict)
            .Select(item => item.ReplaceBlockedReason)
            .FirstOrDefault(reason => !string.IsNullOrWhiteSpace(reason));
    }

    private DesktopImportPreviewItem FirstReplaceConflict()
    {
        return PreviewItems.First(item => item.CanPreviewReplace);
    }

    private async Task<DesktopImportReplaceConfirmation> PreviewCoreSessionReplaceAsync(
        DesktopImportPreviewItem item,
        CancellationToken cancellationToken)
    {
        DesktopImportConflictBatchPreviewReport preview = await coreBridge
            .PreviewReplaceConflictAsync(RepoPath, ReplacePreviewRequest(item), cancellationToken)
            .ConfigureAwait(false);
        DesktopImportPreviewItem updatedItem = item with
        {
            ReplacePreview = preview.Items.FirstOrDefault(previewItem =>
                string.Equals(previewItem.ConflictId, item.ConflictId, StringComparison.Ordinal))
        };
        ReplacePreviewItem(updatedItem);
        return new DesktopImportReplaceConfirmation(updatedItem, preview);
    }

    private DesktopImportConflictBatchPreviewRequest ReplacePreviewRequest(DesktopImportPreviewItem item)
    {
        return new DesktopImportConflictBatchPreviewRequest(
            item.ImportSessionId ?? string.Empty,
            [item.ConflictId ?? string.Empty],
            DesktopImportConflictBatchStrategy.Skip,
            DesktopImportConflictBatchStrategy.Replace,
            false);
    }

    private DesktopImportConflictBatchApplyRequest ReplaceApplyRequest(DesktopImportPreviewItem item)
    {
        return new DesktopImportConflictBatchApplyRequest(
            item.ImportSessionId ?? string.Empty,
            [item.ConflictId ?? string.Empty],
            DesktopImportConflictBatchStrategy.Skip,
            DesktopImportConflictBatchStrategy.Replace,
            false,
            true);
    }

    private void ReplacePreviewItem(DesktopImportPreviewItem replacement)
    {
        PreviewItems = PreviewItems
            .Select(item => string.Equals(item.SourcePath, replacement.SourcePath, StringComparison.OrdinalIgnoreCase)
                ? replacement
                : item)
            .ToArray();
    }

    private IReadOnlyList<DesktopImportResult> ResultsFromReplaceReport(
        DesktopImportConflictBatchApplyReport report,
        DesktopImportPreviewItem item)
    {
        DesktopImportConflictBatchItemResult? replaced = report.ItemResults.FirstOrDefault(result =>
            result.Status == DesktopImportConflictBatchResultStatus.Replaced);
        DesktopFileEntry entry = new(
            replaced?.FileId ?? 0,
            replaced?.FinalPath ?? item.SuggestedName,
            item.FileName,
            item.SuggestedName,
            item.SuggestedCategory,
            0,
            string.Empty,
            DesktopStorageMode.Copied,
            DesktopFileOrigin.Imported,
            item.SourcePath,
            DesktopFileAvailabilityStatus.Available,
            0,
            0);
        return [new DesktopImportResult(
            entry,
            DesktopImportSourceRemovalStatus.NotRequested,
            null,
            report)];
    }
}
