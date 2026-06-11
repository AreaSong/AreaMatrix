using AreaMatrix.Linux.Features.Library;

namespace AreaMatrix.Linux.Features.Import;

public sealed partial class LinuxImportViewModel
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
                OnPropertyChanged(nameof(CanPrepare));
                OnPropertyChanged(nameof(CanImport));
                OnPropertyChanged(nameof(CanPreviewReplace));
                OnPropertyChanged(nameof(CanApplyReplace));
                OnPropertyChanged(nameof(StatusText));
            }
        }
    }

    public bool HasPendingReplaceConfirmation => PendingReplaceConfirmation is not null;

    public bool CanPreviewReplace => !IsPreparing
        && !IsImporting
        && !IsReplacing
        && PendingReplaceConfirmation is null
        && ReplaceResult is null
        && Results.Count == 0
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
                return "Replace requires second confirmation before the existing file moves to Trash.";
            }

            return FirstReplaceBlockedReason()
                ?? "Replace is unavailable until Core can prove a recoverable replace path.";
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
            PendingReplaceConfirmation = await PreviewReplaceConfirmationAsync(item, cancellationToken)
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
            await ApplyCoreSessionReplaceAsync(
                confirmation,
                confirmation.Preview,
                cancellationToken)
                .ConfigureAwait(false);

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

    private string? FirstReplaceBlockedReason()
    {
        return PreviewItems
            .Where(item => item.Status == DesktopImportPreviewStatus.NameConflict)
            .Select(item => item.ReplaceBlockedReason ?? item.BlockedReason)
            .FirstOrDefault(reason => !string.IsNullOrWhiteSpace(reason));
    }

    private DesktopImportPreviewItem FirstReplaceConflict()
    {
        return PreviewItems.First(item => item.CanPreviewReplace);
    }

    private async Task<DesktopImportReplaceConfirmation> PreviewReplaceConfirmationAsync(
        DesktopImportPreviewItem item,
        CancellationToken cancellationToken)
    {
        if (item.HasCoreReplaceConflict)
        {
            return await PreviewCoreSessionReplaceAsync(item, cancellationToken).ConfigureAwait(false);
        }

        return new DesktopImportReplaceConfirmation(item, null);
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

    private async Task ApplyCoreSessionReplaceAsync(
        DesktopImportReplaceConfirmation confirmation,
        DesktopImportConflictBatchPreviewReport? preview,
        CancellationToken cancellationToken)
    {
        if (preview is null)
        {
            throw new DesktopImportCoreException(
                DesktopImportErrorKind.Conflict,
                "Replace requires Core preview token and Linux Trash availability.",
                confirmation.Item.SourcePath);
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
    }

    private void ReplacePreviewItem(DesktopImportPreviewItem replacement)
    {
        PreviewItems = PreviewItems
            .Select(item => string.Equals(item.SourcePath, replacement.SourcePath, StringComparison.Ordinal)
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
            item.SourcePath,
            DesktopImportSourceRemovalStatus.NotRequested,
            null,
            report,
            true)];
    }
}
