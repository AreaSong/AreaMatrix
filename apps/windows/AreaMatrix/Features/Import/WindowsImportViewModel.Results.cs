using System.Collections.Generic;
using System.Linq;
using System;
using System.Threading;
using System.Threading.Tasks;

namespace AreaMatrix.Features.Import;

public sealed partial class WindowsImportViewModel
{
    public bool HasSuccessfulResults => Results.Any(result => result.HasImportedFile);

    public bool HasFailedResults => Results.Any(result => result.IsFailure);

    public IReadOnlyList<long> ImportedFileIds => Results
        .Where(result => result is { Entry.Id: > 0, IsFailure: false })
        .Select(result => result.Entry?.Id ?? 0)
        .Distinct()
        .ToArray();

    public async Task RetryFailedAsync(
        DesktopImportResult failedResult,
        CancellationToken cancellationToken = default)
    {
        if (!failedResult.CanRetry)
        {
            return;
        }

        DesktopImportPreviewItem? item = PreviewItems.FirstOrDefault(candidate =>
            string.Equals(candidate.SourcePath, failedResult.SourcePath, StringComparison.OrdinalIgnoreCase));
        if (item is null || !CanImportPreviewItem(item))
        {
            return;
        }

        IsImporting = true;
        Error = null;
        try
        {
            ReplaceResultForSource(
                item.SourcePath,
                await ImportPreviewItemAsync(item, cancellationToken).ConfigureAwait(false));
            CurrentStep = DesktopImportStep.Done;
        }
        finally
        {
            IsImporting = false;
        }
    }

    public WindowsImportCloseRequest CreateCloseRequest()
    {
        return ImportedFileIds.Count == 0
            ? WindowsImportCloseRequest.None
            : new WindowsImportCloseRequest(ImportedFileIds);
    }

    private static string ResultSummaryFor(IReadOnlyList<DesktopImportResult> currentResults)
    {
        int failed = currentResults.Count(result => result.IsFailure);
        int succeeded = currentResults.Count(result => result.HasImportedFile);
        if (failed > 0)
        {
            return $"Imported {succeeded} item(s), {failed} failed.";
        }

        if (currentResults.Any(result => result.IsReplace))
        {
            return currentResults.Count == 1
                ? currentResults[0].SummaryText
                : $"Replaced {currentResults.Count(result => result.IsReplace)} item(s).";
        }

        int retained = currentResults.Count(result =>
            result.SourceRemovalStatus == DesktopImportSourceRemovalStatus.Retained);
        return retained > 0
            ? $"Imported {currentResults.Count} item(s), {retained} original(s) retained"
            : $"Imported {currentResults.Count} item(s)";
    }

    private async Task<DesktopImportResult> ImportPreviewItemAsync(
        DesktopImportPreviewItem item,
        CancellationToken cancellationToken)
    {
        try
        {
            CurrentStep = DesktopImportStep.Staging;
            DesktopImportRequest request = MakeRequest(item);
            CurrentStep = DesktopImportStep.Hashing;
            DesktopImportResult result = await coreBridge
                .ImportFileWithResultAsync(RepoPath, item.SourcePath, request, cancellationToken)
                .ConfigureAwait(false);
            CurrentStep = DesktopImportStep.UpdatingDatabase;
            return ResultForItem(item, result);
        }
        catch (Exception exception) when (exception is not OperationCanceledException)
        {
            return DesktopImportResult.Failed(item, DesktopImportError.FromException(exception));
        }
    }

    private static DesktopImportResult ResultForItem(
        DesktopImportPreviewItem item,
        DesktopImportResult result)
    {
        return string.Equals(result.SourcePath, item.SourcePath, StringComparison.OrdinalIgnoreCase)
            ? result
            : result with { SourcePath = item.SourcePath };
    }

    private void ReplaceResultForSource(
        string sourcePath,
        DesktopImportResult replacement)
    {
        Results = Results
            .Select(result => string.Equals(result.SourcePath, sourcePath, StringComparison.OrdinalIgnoreCase)
                ? replacement
                : result)
            .ToArray();
    }
}
