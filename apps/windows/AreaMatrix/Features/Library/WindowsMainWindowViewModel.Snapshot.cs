using System;
using System.Collections.Generic;
using System.Linq;
using System.Threading;
using System.Threading.Tasks;

namespace AreaMatrix.Features.Library;

public sealed partial class WindowsMainWindowViewModel
{
    private async Task LoadSnapshotAsync(
        bool isInitialLoad,
        CancellationToken cancellationToken,
        long? selectedFileId = null,
        long? generation = null,
        string? repositoryPath = null,
        string? category = null)
    {
        string loadPath = repositoryPath ?? RepoPath;
        string? loadCategory = category ?? SelectedCategory;
        if (string.IsNullOrWhiteSpace(loadPath))
        {
            return;
        }

        SetBusy(isInitialLoad, true);
        Error = null;
        try
        {
            IReadOnlyList<DesktopCategoryNode> categories = await coreBridge
                .ListCategoriesAsync(loadPath, locale, cancellationToken);
            cancellationToken.ThrowIfCancellationRequested();
            IReadOnlyList<DesktopFileEntry> files = await coreBridge.ListFilesAsync(
                loadPath,
                DesktopFileFilter.FirstPage(loadCategory),
                cancellationToken);
            cancellationToken.ThrowIfCancellationRequested();
            (bool hasSelectionOverride, DesktopFileEntry? selected) = await SelectedFileForSnapshotAsync(
                files,
                selectedFileId,
                loadPath,
                cancellationToken);
            cancellationToken.ThrowIfCancellationRequested();
            if (generation is { } loadGeneration
                && !IsCurrentRepositoryLoad(loadGeneration))
            {
                return;
            }

            ApplySnapshot(
                files,
                categories,
                files.Count,
                string.Empty,
                null,
                hasSelectionOverride,
                selected);
        }
        catch (Exception exception) when (exception is not OperationCanceledException)
        {
            if (generation is not { } loadGeneration
                || IsCurrentRepositoryLoad(loadGeneration))
            {
                Error = ErrorFromException(exception);
            }
        }
        finally
        {
            if (generation is not { } loadGeneration
                || IsCurrentRepositoryLoad(loadGeneration))
            {
                SetBusy(isInitialLoad, false);
            }
        }
    }

    private void ApplySnapshot(
        IReadOnlyList<DesktopFileEntry> files,
        IReadOnlyList<DesktopCategoryNode> categories,
        long totalCount,
        string query,
        DesktopSearchIndexStatus? searchIndexStatus,
        bool hasSelectionOverride = false,
        DesktopFileEntry? selectedFileOverride = null)
    {
        DesktopFileEntry? retainedSelection = hasSelectionOverride
            ? selectedFileOverride
            : SelectedFile is { } current
            ? files.FirstOrDefault(file => file.Id == current.Id)
            : null;

        SelectedFile = retainedSelection;
        Snapshot = new DesktopMainQuerySnapshot(
            files,
            categories,
            retainedSelection,
            totalCount,
            query,
            searchIndexStatus);
    }

    private async Task<(bool HasSelectionOverride, DesktopFileEntry? SelectedFile)> SelectedFileForSnapshotAsync(
        IReadOnlyList<DesktopFileEntry> files,
        long? selectedFileId,
        string repositoryPath,
        CancellationToken cancellationToken)
    {
        if (selectedFileId is not > 0)
        {
            return (false, null);
        }

        DesktopFileEntry? listedFile = files.FirstOrDefault(file => file.Id == selectedFileId.Value);
        if (listedFile is not null)
        {
            return (true, await coreBridge.GetFileAsync(repositoryPath, listedFile.Id, cancellationToken));
        }

        return (true, await coreBridge.GetFileAsync(repositoryPath, selectedFileId.Value, cancellationToken));
    }
}
