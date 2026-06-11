namespace AreaMatrix.Linux.Features.Import;

public enum DesktopImportConflictBatchStrategy
{
    Skip,
    KeepBoth,
    Replace,
    AskPerItem
}

public enum DesktopImportConflictBatchPreviewStatus
{
    Ready,
    Pending,
    NeedsConfirmation,
    Blocked,
    Failed
}

public enum DesktopImportConflictBatchResultStatus
{
    Skipped,
    KeptBoth,
    Replaced,
    QueuedForPerItem,
    Pending,
    Failed
}

public sealed record DesktopImportConflictBatchPreviewRequest(
    string ImportSessionId,
    IReadOnlyList<string> ConflictIds,
    DesktopImportConflictBatchStrategy DuplicateStrategy,
    DesktopImportConflictBatchStrategy SameNameStrategy,
    bool ApplyToAllSimilarConflicts);

public sealed record DesktopImportConflictBatchApplyRequest(
    string ImportSessionId,
    IReadOnlyList<string> ConflictIds,
    DesktopImportConflictBatchStrategy DuplicateStrategy,
    DesktopImportConflictBatchStrategy SameNameStrategy,
    bool ApplyToAllSimilarConflicts,
    bool ReplaceConfirmed);

public sealed record DesktopImportConflictBatchPreviewItem(
    string ConflictId,
    string ConflictType,
    long? ExistingFileId,
    string? ExistingPath,
    string IncomingPath,
    string? TargetPath,
    DesktopImportConflictBatchStrategy SelectedStrategy,
    DesktopImportConflictBatchPreviewStatus Status,
    bool WillReplace,
    bool WillKeepBoth,
    bool WillSkip,
    bool WillAskPerItem,
    bool IndexOnly,
    string RiskSummary,
    string? Reason)
{
    public bool CanReplace => SelectedStrategy == DesktopImportConflictBatchStrategy.Replace
        && Status == DesktopImportConflictBatchPreviewStatus.NeedsConfirmation
        && WillReplace
        && !IndexOnly;

    public string ReplaceStatusText => CanReplace
        ? "Replace requires second confirmation before Core can apply it."
        : Reason ?? "Replace is not available for this conflict.";
}

public sealed record DesktopImportConflictBatchPreviewReport(
    string ImportSessionId,
    string PreviewToken,
    bool ApplyToAllSimilarConflicts,
    long RequestedConflictCount,
    long DuplicateConflictCount,
    long SameNameConflictCount,
    long IncludedCount,
    long PendingCount,
    long BlockedCount,
    long ReplaceCount,
    long SkipCount,
    long KeepBothCount,
    long AskPerItemCount,
    bool TrashAvailable,
    bool UndoAvailable,
    bool CanApply,
    string? ApplyBlockedReason,
    bool ReplaceConfirmationRequired,
    string? ReplaceConfirmationSummary,
    IReadOnlyList<DesktopImportConflictBatchPreviewItem> Items);

public sealed record DesktopImportConflictBatchItemResult(
    string ConflictId,
    string ConflictType,
    DesktopImportConflictBatchStrategy AppliedStrategy,
    DesktopImportConflictBatchResultStatus Status,
    long? FileId,
    string? FinalPath,
    string? Error);

public sealed record DesktopImportConflictBatchApplyReport(
    string ImportSessionId,
    long RequestedConflictCount,
    long ResolvedCount,
    long SkippedCount,
    long KeptBothCount,
    long ReplacedCount,
    long QueuedForPerItemCount,
    long PendingCount,
    long FailedCount,
    IReadOnlyList<DesktopImportConflictBatchItemResult> ItemResults,
    IReadOnlyList<long> AffectedFileIds,
    string? UndoToken,
    IReadOnlyList<string> ChangeLogActions,
    string? FailureSummary)
{
    public string SummaryText => FailedCount > 0
        ? $"Replace finished with {FailedCount} failed item(s)."
        : $"Replaced {ReplacedCount} item(s).";
}

public sealed record DesktopImportReplaceConfirmation(
    DesktopImportPreviewItem Item,
    DesktopImportConflictBatchPreviewReport? Preview)
{
    public bool CanConfirm
    {
        get
        {
            return Preview is { } preview
                && preview.CanApply
                && preview.TrashAvailable
                && preview.ReplaceConfirmationRequired
                && Item.ReplacePreview?.CanReplace == true
                && !string.IsNullOrWhiteSpace(preview.PreviewToken);
        }
    }

    public string Title => "Replace existing file?";

    public string Summary => Preview?.ReplaceConfirmationSummary
        ?? Item.ReplacePreview?.RiskSummary
        ?? "The existing repository file will be moved to Trash before replacement.";

    public string ExistingPath => Item.ReplacePreview?.ExistingPath
        ?? Item.ExistingPath
        ?? "Unknown existing file";

    public string IncomingPath => Item.ReplacePreview?.IncomingPath ?? Item.SourcePath;

    public string TargetPath => Item.ReplacePreview?.TargetPath
        ?? Item.TargetPath
        ?? Item.SuggestedName;

    public string BlockedReason => Preview?.ApplyBlockedReason
        ?? TrashBlockedReason
        ?? Item.ReplacePreview?.Reason
        ?? Item.ReplaceBlockedReason
        ?? Item.BlockedReason
        ?? "Replace is not available.";

    private string? TrashBlockedReason => Preview is { TrashAvailable: false }
        ? "Replace requires Linux Trash availability."
        : null;
}
