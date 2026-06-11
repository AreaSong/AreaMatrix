using System.ComponentModel;
using System.Runtime.CompilerServices;

namespace AreaMatrix.Linux.Features.Import;

public sealed partial class LinuxImportViewModel
{
    private void RefreshMovePreflight()
    {
        if (!RequiresMoveConfirmation || PreviewItems.Count == 0 || string.IsNullOrWhiteSpace(RepoPath))
        {
            MovePreflight = DesktopImportMovePreflight.NotEvaluated;
            return;
        }

        MovePreflight = coreBridge.CheckMovePreflight(RepoPath, PreviewItems.Where(CanImportPreviewItem).ToArray());
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

    private static string ResultSummaryFor(IReadOnlyList<DesktopImportResult> currentResults)
    {
        int failed = currentResults.Count(result => result.IsFailure);
        int succeeded = currentResults.Count(result => result.HasImportedFile);
        if (failed > 0)
        {
            return $"Imported {succeeded} item(s), {failed} failed.";
        }

        int retained = currentResults.Count(result =>
            result.SourceRemovalStatus == DesktopImportSourceRemovalStatus.Retained);
        return retained > 0
            ? $"Imported {currentResults.Count} item(s), {retained} original(s) retained"
            : $"Imported {currentResults.Count} item(s)";
    }

    private static DesktopImportResult ResultForItem(
        DesktopImportPreviewItem item,
        DesktopImportResult result)
    {
        return string.Equals(result.SourcePath, item.SourcePath, StringComparison.Ordinal)
            ? result
            : result with { SourcePath = item.SourcePath };
    }

    private void ReplaceResultForSource(
        string sourcePath,
        DesktopImportResult replacement)
    {
        Results = Results
            .Select(result => string.Equals(result.SourcePath, sourcePath, StringComparison.Ordinal)
                ? replacement
                : result)
            .ToArray();
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
