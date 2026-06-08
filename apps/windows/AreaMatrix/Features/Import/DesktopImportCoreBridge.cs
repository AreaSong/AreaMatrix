using System.Threading;
using System.Threading.Tasks;
using AreaMatrix.Features.Library;

namespace AreaMatrix.Features.Import;

public interface IDesktopImportCoreBridge
{
    Task<DesktopImportPreviewItem> PredictImportAsync(
        string repoPath,
        string sourcePath,
        CancellationToken cancellationToken = default);

    Task<DesktopImportResult> ImportFileWithResultAsync(
        string repoPath,
        string sourcePath,
        DesktopImportRequest request,
        CancellationToken cancellationToken = default);

    Task<DesktopImportConflictBatchPreviewReport> PreviewReplaceConflictAsync(
        string repoPath,
        DesktopImportConflictBatchPreviewRequest request,
        CancellationToken cancellationToken = default);

    Task<DesktopImportConflictBatchApplyReport> ApplyReplaceConflictAsync(
        string repoPath,
        DesktopImportConflictBatchApplyRequest request,
        string previewToken,
        CancellationToken cancellationToken = default);

    DesktopImportMovePreflight CheckMovePreflight(
        string repoPath,
        IReadOnlyList<DesktopImportPreviewItem> previewItems);
}

public interface IAreaMatrixDesktopImportCoreClient
{
    Task<CoreDesktopClassifyResult> PredictCategoryAsync(
        string repoPath,
        string filename,
        CancellationToken cancellationToken = default);

    Task<CoreDesktopImportResult> ImportFileWithResultAsync(
        string repoPath,
        string sourcePath,
        CoreDesktopImportOptions options,
        CancellationToken cancellationToken = default);

    Task<CoreDesktopImportConflictBatchPreviewReport> PreviewImportConflictBatchAsync(
        string repoPath,
        CoreDesktopImportConflictBatchPreviewRequest request,
        CancellationToken cancellationToken = default);

    Task<CoreDesktopImportConflictBatchApplyReport> ApplyImportConflictBatchAsync(
        string repoPath,
        CoreDesktopImportConflictBatchApplyRequest request,
        string previewToken,
        CancellationToken cancellationToken = default);
}

public sealed class DesktopImportCoreBridge : IDesktopImportCoreBridge
{
    private readonly IAreaMatrixDesktopImportCoreClient coreClient;
    private readonly IWindowsImportFileProbe fileProbe;

    public DesktopImportCoreBridge(
        IAreaMatrixDesktopImportCoreClient coreClient,
        IWindowsImportFileProbe fileProbe)
    {
        this.coreClient = coreClient;
        this.fileProbe = fileProbe;
    }

    public async Task<DesktopImportPreviewItem> PredictImportAsync(
        string repoPath,
        string sourcePath,
        CancellationToken cancellationToken = default)
    {
        WindowsImportFileProbeResult probe = fileProbe.Probe(sourcePath);
        if (!probe.IsReadable)
        {
            return new DesktopImportPreviewItem(
                sourcePath,
                probe.FileName,
                probe.TypeText,
                probe.SizeText,
                string.Empty,
                probe.FileName,
                DesktopImportPreviewStatus.Unreadable);
        }

        CoreDesktopClassifyResult result = await coreClient
            .PredictCategoryAsync(repoPath, probe.FileName, cancellationToken)
            .ConfigureAwait(false);

        DesktopImportPreviewStatus status = fileProbe.ResolvePreviewStatus(
            repoPath,
            probe,
            result.Category,
            result.SuggestedName);
        WindowsImportFileProbeResult replacePreflight = status == DesktopImportPreviewStatus.NameConflict
            ? fileProbe.ResolveReplacePreflight(repoPath, probe, result.Category, result.SuggestedName)
            : probe;

        return new DesktopImportPreviewItem(
            sourcePath,
            probe.FileName,
            probe.TypeText,
            probe.SizeText,
            result.Category,
            result.SuggestedName,
            status,
            ExistingPath: replacePreflight.ExistingConflictPath,
            TargetPath: replacePreflight.TargetPath,
            ReplacePreflightAvailable: replacePreflight.ReplacePreflightAvailable,
            ReplaceBlockedReason: replacePreflight.ReplaceBlockedReason);
    }

    public async Task<DesktopImportResult> ImportFileWithResultAsync(
        string repoPath,
        string sourcePath,
        DesktopImportRequest request,
        CancellationToken cancellationToken = default)
    {
        CoreDesktopImportResult result = await coreClient
            .ImportFileWithResultAsync(repoPath, sourcePath, request.ToCoreOptions(), cancellationToken)
            .ConfigureAwait(false);
        return result.ToDesktopResult();
    }

    public async Task<DesktopImportConflictBatchPreviewReport> PreviewReplaceConflictAsync(
        string repoPath,
        DesktopImportConflictBatchPreviewRequest request,
        CancellationToken cancellationToken = default)
    {
        CoreDesktopImportConflictBatchPreviewReport result = await coreClient
            .PreviewImportConflictBatchAsync(repoPath, request.ToCoreRequest(), cancellationToken)
            .ConfigureAwait(false);
        return result.ToDesktopReport();
    }

    public async Task<DesktopImportConflictBatchApplyReport> ApplyReplaceConflictAsync(
        string repoPath,
        DesktopImportConflictBatchApplyRequest request,
        string previewToken,
        CancellationToken cancellationToken = default)
    {
        CoreDesktopImportConflictBatchApplyReport result = await coreClient
            .ApplyImportConflictBatchAsync(repoPath, request.ToCoreRequest(), previewToken, cancellationToken)
            .ConfigureAwait(false);
        return result.ToDesktopReport();
    }

    public DesktopImportMovePreflight CheckMovePreflight(
        string repoPath,
        IReadOnlyList<DesktopImportPreviewItem> previewItems)
    {
        return fileProbe.CheckMovePreflight(repoPath, previewItems);
    }
}

public sealed record CoreDesktopClassifyResult(
    string Category,
    string SuggestedName,
    string Reason,
    float Confidence);

public sealed record CoreDesktopImportOptions(
    string Mode,
    string Destination,
    string? TargetDirectory,
    string? OverrideCategory,
    string? OverrideFilename,
    string DuplicateStrategy);

public sealed record CoreDesktopImportResult(
    CoreDesktopFileEntry Entry,
    string SourceRemovalStatus,
    string? SourceRemovalFailure);

public sealed record CoreDesktopImportConflictBatchPreviewRequest(
    string ImportSessionId,
    IReadOnlyList<string> ConflictIds,
    string DuplicateStrategy,
    string SameNameStrategy,
    bool ApplyToAllSimilarConflicts);

public sealed record CoreDesktopImportConflictBatchApplyRequest(
    string ImportSessionId,
    IReadOnlyList<string> ConflictIds,
    string DuplicateStrategy,
    string SameNameStrategy,
    bool ApplyToAllSimilarConflicts,
    bool ReplaceConfirmed);

public sealed record CoreDesktopImportConflictBatchPreviewItem(
    string ConflictId,
    string ConflictType,
    long? ExistingFileId,
    string? ExistingPath,
    string IncomingPath,
    string? TargetPath,
    string SelectedStrategy,
    string Status,
    bool WillReplace,
    bool WillKeepBoth,
    bool WillSkip,
    bool WillAskPerItem,
    bool IndexOnly,
    string RiskSummary,
    string? Reason);

public sealed record CoreDesktopImportConflictBatchPreviewReport(
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
    IReadOnlyList<CoreDesktopImportConflictBatchPreviewItem> Items);

public sealed record CoreDesktopImportConflictBatchItemResult(
    string ConflictId,
    string ConflictType,
    string AppliedStrategy,
    string Status,
    long? FileId,
    string? FinalPath,
    string? Error);

public sealed record CoreDesktopImportConflictBatchApplyReport(
    string ImportSessionId,
    long RequestedConflictCount,
    long ResolvedCount,
    long SkippedCount,
    long KeptBothCount,
    long ReplacedCount,
    long QueuedForPerItemCount,
    long PendingCount,
    long FailedCount,
    IReadOnlyList<CoreDesktopImportConflictBatchItemResult> ItemResults,
    IReadOnlyList<long> AffectedFileIds,
    string? UndoToken,
    IReadOnlyList<string> ChangeLogActions,
    string? FailureSummary);

internal static class DesktopImportCoreMapping
{
    public static CoreDesktopImportOptions ToCoreOptions(this DesktopImportRequest request)
    {
        return new CoreDesktopImportOptions(
            request.Mode.ToCoreMode(),
            request.Destination.ToCoreDestination(),
            NormalizeOptional(request.TargetDirectory),
            NormalizeOptional(request.OverrideCategory),
            NormalizeOptional(request.OverrideFilename),
            request.DuplicateStrategy.ToCoreDuplicateStrategy());
    }

    public static DesktopImportResult ToDesktopResult(this CoreDesktopImportResult result)
    {
        return new DesktopImportResult(
            result.Entry.ToDesktopEntry(),
            ParseSourceRemovalStatus(result.SourceRemovalStatus),
            result.SourceRemovalFailure);
    }

    public static CoreDesktopImportConflictBatchPreviewRequest ToCoreRequest(
        this DesktopImportConflictBatchPreviewRequest request)
    {
        return new CoreDesktopImportConflictBatchPreviewRequest(
            request.ImportSessionId,
            request.ConflictIds,
            request.DuplicateStrategy.ToCoreConflictBatchStrategy(),
            request.SameNameStrategy.ToCoreConflictBatchStrategy(),
            request.ApplyToAllSimilarConflicts);
    }

    public static CoreDesktopImportConflictBatchApplyRequest ToCoreRequest(
        this DesktopImportConflictBatchApplyRequest request)
    {
        return new CoreDesktopImportConflictBatchApplyRequest(
            request.ImportSessionId,
            request.ConflictIds,
            request.DuplicateStrategy.ToCoreConflictBatchStrategy(),
            request.SameNameStrategy.ToCoreConflictBatchStrategy(),
            request.ApplyToAllSimilarConflicts,
            request.ReplaceConfirmed);
    }

    public static DesktopImportConflictBatchPreviewReport ToDesktopReport(
        this CoreDesktopImportConflictBatchPreviewReport report)
    {
        return new DesktopImportConflictBatchPreviewReport(
            report.ImportSessionId,
            report.PreviewToken,
            report.ApplyToAllSimilarConflicts,
            report.RequestedConflictCount,
            report.DuplicateConflictCount,
            report.SameNameConflictCount,
            report.IncludedCount,
            report.PendingCount,
            report.BlockedCount,
            report.ReplaceCount,
            report.SkipCount,
            report.KeepBothCount,
            report.AskPerItemCount,
            report.TrashAvailable,
            report.UndoAvailable,
            report.CanApply,
            report.ApplyBlockedReason,
            report.ReplaceConfirmationRequired,
            report.ReplaceConfirmationSummary,
            report.Items.Select(item => item.ToDesktopItem()).ToArray());
    }

    public static DesktopImportConflictBatchApplyReport ToDesktopReport(
        this CoreDesktopImportConflictBatchApplyReport report)
    {
        return new DesktopImportConflictBatchApplyReport(
            report.ImportSessionId,
            report.RequestedConflictCount,
            report.ResolvedCount,
            report.SkippedCount,
            report.KeptBothCount,
            report.ReplacedCount,
            report.QueuedForPerItemCount,
            report.PendingCount,
            report.FailedCount,
            report.ItemResults.Select(item => item.ToDesktopItem()).ToArray(),
            report.AffectedFileIds,
            report.UndoToken,
            report.ChangeLogActions,
            report.FailureSummary);
    }

    private static string ToCoreMode(this DesktopImportMode mode)
    {
        return mode switch
        {
            DesktopImportMode.Copy => "Copied",
            DesktopImportMode.Move => "Moved",
            _ => throw new DesktopImportCoreException(
                DesktopImportErrorKind.Config,
                $"Unsupported desktop import mode `{mode}`.")
        };
    }

    private static string ToCoreDestination(this DesktopImportDestination destination)
    {
        return destination switch
        {
            DesktopImportDestination.AutoClassify => "AutoClassify",
            DesktopImportDestination.SelectedDirectory => "SelectedDirectory",
            DesktopImportDestination.Category => "Category",
            _ => throw new DesktopImportCoreException(
                DesktopImportErrorKind.Config,
                $"Unsupported desktop import destination `{destination}`.")
        };
    }

    private static string ToCoreDuplicateStrategy(this DesktopImportDuplicateStrategy strategy)
    {
        return strategy switch
        {
            DesktopImportDuplicateStrategy.Skip => "Skip",
            DesktopImportDuplicateStrategy.Overwrite => "Overwrite",
            DesktopImportDuplicateStrategy.KeepBoth => "KeepBoth",
            DesktopImportDuplicateStrategy.Ask => "Ask",
            _ => throw new DesktopImportCoreException(
                DesktopImportErrorKind.Config,
                $"Unsupported desktop import duplicate strategy `{strategy}`.")
        };
    }

    private static string ToCoreConflictBatchStrategy(this DesktopImportConflictBatchStrategy strategy)
    {
        return strategy switch
        {
            DesktopImportConflictBatchStrategy.Skip => "Skip",
            DesktopImportConflictBatchStrategy.KeepBoth => "KeepBoth",
            DesktopImportConflictBatchStrategy.Replace => "Replace",
            DesktopImportConflictBatchStrategy.AskPerItem => "AskPerItem",
            _ => throw new DesktopImportCoreException(
                DesktopImportErrorKind.Config,
                $"Unsupported desktop import conflict strategy `{strategy}`.")
        };
    }

    private static DesktopImportConflictBatchPreviewItem ToDesktopItem(
        this CoreDesktopImportConflictBatchPreviewItem item)
    {
        return new DesktopImportConflictBatchPreviewItem(
            item.ConflictId,
            item.ConflictType,
            item.ExistingFileId,
            item.ExistingPath,
            item.IncomingPath,
            item.TargetPath,
            ParseConflictBatchStrategy(item.SelectedStrategy),
            ParseConflictBatchPreviewStatus(item.Status),
            item.WillReplace,
            item.WillKeepBoth,
            item.WillSkip,
            item.WillAskPerItem,
            item.IndexOnly,
            item.RiskSummary,
            item.Reason);
    }

    private static DesktopImportConflictBatchItemResult ToDesktopItem(
        this CoreDesktopImportConflictBatchItemResult item)
    {
        return new DesktopImportConflictBatchItemResult(
            item.ConflictId,
            item.ConflictType,
            ParseConflictBatchStrategy(item.AppliedStrategy),
            ParseConflictBatchResultStatus(item.Status),
            item.FileId,
            item.FinalPath,
            item.Error);
    }

    private static DesktopImportSourceRemovalStatus ParseSourceRemovalStatus(string value)
    {
        return value switch
        {
            "NotRequested" => DesktopImportSourceRemovalStatus.NotRequested,
            "Removed" => DesktopImportSourceRemovalStatus.Removed,
            "Retained" => DesktopImportSourceRemovalStatus.Retained,
            _ => throw new DesktopImportCoreException(
                DesktopImportErrorKind.Config,
                $"AreaMatrix Core returned unsupported source removal status `{value}`.")
        };
    }

    private static DesktopImportConflictBatchStrategy ParseConflictBatchStrategy(string value)
    {
        return value switch
        {
            "Skip" => DesktopImportConflictBatchStrategy.Skip,
            "KeepBoth" => DesktopImportConflictBatchStrategy.KeepBoth,
            "Replace" => DesktopImportConflictBatchStrategy.Replace,
            "AskPerItem" => DesktopImportConflictBatchStrategy.AskPerItem,
            _ => throw new DesktopImportCoreException(
                DesktopImportErrorKind.Config,
                $"AreaMatrix Core returned unsupported import conflict strategy `{value}`.")
        };
    }

    private static DesktopImportConflictBatchPreviewStatus ParseConflictBatchPreviewStatus(string value)
    {
        return value switch
        {
            "Ready" => DesktopImportConflictBatchPreviewStatus.Ready,
            "Pending" => DesktopImportConflictBatchPreviewStatus.Pending,
            "NeedsConfirmation" => DesktopImportConflictBatchPreviewStatus.NeedsConfirmation,
            "Blocked" => DesktopImportConflictBatchPreviewStatus.Blocked,
            "Failed" => DesktopImportConflictBatchPreviewStatus.Failed,
            _ => throw new DesktopImportCoreException(
                DesktopImportErrorKind.Config,
                $"AreaMatrix Core returned unsupported import conflict preview status `{value}`.")
        };
    }

    private static DesktopImportConflictBatchResultStatus ParseConflictBatchResultStatus(string value)
    {
        return value switch
        {
            "Skipped" => DesktopImportConflictBatchResultStatus.Skipped,
            "KeptBoth" => DesktopImportConflictBatchResultStatus.KeptBoth,
            "Replaced" => DesktopImportConflictBatchResultStatus.Replaced,
            "QueuedForPerItem" => DesktopImportConflictBatchResultStatus.QueuedForPerItem,
            "Pending" => DesktopImportConflictBatchResultStatus.Pending,
            "Failed" => DesktopImportConflictBatchResultStatus.Failed,
            _ => throw new DesktopImportCoreException(
                DesktopImportErrorKind.Config,
                $"AreaMatrix Core returned unsupported import conflict result status `{value}`.")
        };
    }

    private static string? NormalizeOptional(string? value)
    {
        return string.IsNullOrWhiteSpace(value) ? null : value.Trim();
    }
}
