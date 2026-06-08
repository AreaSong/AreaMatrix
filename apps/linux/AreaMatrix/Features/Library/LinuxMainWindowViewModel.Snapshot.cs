namespace AreaMatrix.Linux.Features.Library;

public sealed partial class LinuxMainWindowViewModel
{
    private const long PageSize = 50;

    private async Task LoadSnapshotAsync(
        bool isInitialLoad,
        CancellationToken cancellationToken)
    {
        if (string.IsNullOrWhiteSpace(RepoPath))
        {
            return;
        }

        SetBusy(isInitialLoad, true);
        Error = null;
        try
        {
            IReadOnlyList<DesktopCategoryNode> categories = await coreBridge
                .ListCategoriesAsync(RepoPath, locale, cancellationToken)
                .ConfigureAwait(false);
            IReadOnlyList<DesktopFileEntry> files = await coreBridge.ListFilesAsync(
                RepoPath,
                DesktopFileFilter.FirstPage(SelectedCategory),
                cancellationToken).ConfigureAwait(false);
            ApplySnapshot(
                files,
                categories,
                files.Count,
                string.Empty,
                null,
                offset: 0,
                hasMore: files.Count == PageSize);
        }
        catch (Exception exception) when (exception is not OperationCanceledException)
        {
            Error = ErrorFromException(exception);
        }
        finally
        {
            SetBusy(isInitialLoad, false);
        }
    }

    private void ApplySnapshot(
        IReadOnlyList<DesktopFileEntry> files,
        IReadOnlyList<DesktopCategoryNode> categories,
        long totalCount,
        string query,
        DesktopSearchIndexStatus? searchIndexStatus,
        long offset,
        bool hasMore)
    {
        DesktopFileEntry? retainedSelection = SelectedFile is { } current
            ? files.FirstOrDefault(file => file.Id == current.Id)
            : null;

        SelectedFile = retainedSelection;
        Snapshot = new DesktopMainQuerySnapshot(
            files,
            categories,
            retainedSelection,
            totalCount,
            query,
            searchIndexStatus,
            PageSize,
            offset,
            hasMore);
    }

    private async Task LoadMoreListAsync(CancellationToken cancellationToken)
    {
        IReadOnlyList<DesktopFileEntry> page = await coreBridge.ListFilesAsync(
            RepoPath,
            DesktopFileFilter.Page(SelectedCategory, PageSize, Snapshot.NextOffset),
            cancellationToken).ConfigureAwait(false);
        IReadOnlyList<DesktopFileEntry> files = Snapshot.Files.Concat(page).ToArray();
        ApplySnapshot(
            files,
            Snapshot.Categories,
            files.Count,
            string.Empty,
            null,
            offset: 0,
            page.Count == PageSize);
    }

    private async Task LoadMoreSearchAsync(CancellationToken cancellationToken)
    {
        DesktopSearchResultPage page = await coreBridge.SearchFilesAsync(
            RepoPath,
            Snapshot.Query,
            DesktopSearchFilter.AllRepository(SelectedCategory),
            DesktopSearchSort.Relevance,
            new DesktopSearchPagination(PageSize, Snapshot.NextOffset),
            cancellationToken).ConfigureAwait(false);
        IReadOnlyList<DesktopFileEntry> files = Snapshot.Files
            .Concat(page.Results.Select(result => result.Entry))
            .ToArray();
        ApplySnapshot(
            files,
            Snapshot.Categories,
            page.TotalCount,
            page.Query,
            page.IndexStatus,
            offset: 0,
            files.Count < page.TotalCount);
    }

    private void SetBusy(bool isInitialLoad, bool value)
    {
        if (isInitialLoad)
        {
            IsLoading = value;
            return;
        }

        IsRefreshing = value;
    }
}
