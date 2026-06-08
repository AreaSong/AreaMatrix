using AreaMatrix.Features.Library;
using AreaMatrix.Features.Onboarding;
using AreaMatrixTests.ChooseRepository;

namespace AreaMatrixTests.DesktopMainQuery;

public static class DesktopMainQueryViewModelTests
{
    public static async Task RunAllAsync()
    {
        await OpenRepositoryLoadsTreeAndFirstPageFromCoreBridge();
        await SearchUsesCoreSearchWithoutScanningRepository();
        await SelectingFileUsesCoreDetailQuery();
        await RefreshKeepsCachedListOnDbError();
        await RefreshAfterImportSelectsImportedFile();
        await OneDriveRepositoryExposesConnectedNoticeRoute();
        await MainWindowRouteExposesWatcherStatusEntry();
    }

    private static async Task OpenRepositoryLoadsTreeAndFirstPageFromCoreBridge()
    {
        FakeDesktopMainQueryCoreBridge bridge = new();
        WindowsMainWindowViewModel model = new(bridge);

        await model.OpenRepositoryAsync(Route(@"C:\Repos\AreaMatrix"));

        TestAssert.SequenceEqual([@"C:\Repos\AreaMatrix"], bridge.TreeRequests, "tree requests");
        TestAssert.SequenceEqual([@"C:\Repos\AreaMatrix"], bridge.ListRequests, "list requests");
        TestAssert.Empty(bridge.SearchRequests, nameof(bridge.SearchRequests));
        TestAssert.Equal("AreaMatrix", model.RepoName, nameof(model.RepoName));
        TestAssert.Equal(2, model.Files.Count, "visible files");
        TestAssert.Null(model.Error, nameof(model.Error));
    }

    private static async Task SearchUsesCoreSearchWithoutScanningRepository()
    {
        FakeDesktopMainQueryCoreBridge bridge = new();
        WindowsMainWindowViewModel model = new(bridge);

        await model.OpenRepositoryAsync(Route(@"C:\Repos\AreaMatrix"));
        bridge.ClearRequests();
        model.SearchQuery = "contract";
        await model.RunSearchAsync();

        TestAssert.SequenceEqual([@"C:\Repos\AreaMatrix"], bridge.TreeRequests, "tree requests");
        TestAssert.Empty(bridge.ListRequests, nameof(bridge.ListRequests));
        TestAssert.SequenceEqual(["contract"], bridge.SearchRequests, "search requests");
        TestAssert.Equal("contract", model.Snapshot.Query, "snapshot query");
        TestAssert.Equal(DesktopSearchIndexStatus.Ready, model.Snapshot.SearchIndexStatus, "index status");
    }

    private static async Task SelectingFileUsesCoreDetailQuery()
    {
        FakeDesktopMainQueryCoreBridge bridge = new();
        WindowsMainWindowViewModel model = new(bridge);

        await model.OpenRepositoryAsync(Route(@"C:\Repos\AreaMatrix"));
        DesktopFileEntry selected = model.Files[0];
        await model.SelectFileAsync(selected);

        TestAssert.SequenceEqual([selected.Id], bridge.DetailRequests, "detail requests");
        TestAssert.Equal(selected.Id, model.SelectedFile?.Id, "selected file id");
        TestAssert.Contains(selected.DisplayName, model.SelectedFileTitle, nameof(model.SelectedFileTitle));
    }

    private static async Task RefreshKeepsCachedListOnDbError()
    {
        FakeDesktopMainQueryCoreBridge bridge = new();
        WindowsMainWindowViewModel model = new(bridge);
        await model.OpenRepositoryAsync(Route(@"C:\Repos\AreaMatrix"));
        int previousCount = model.Files.Count;

        bridge.ThrowOnList = new DesktopQueryCoreException(
            DesktopQueryErrorKind.Db,
            "Repository database could not be read.");
        await model.RefreshAsync();

        TestAssert.Equal(previousCount, model.Files.Count, "cached file count");
        TestAssert.Equal(WindowsRepositoryErrorKind.Db, model.Error?.Kind, "error kind");
        TestAssert.Contains("database", model.StatusText, nameof(model.StatusText));
    }

    private static async Task RefreshAfterImportSelectsImportedFile()
    {
        FakeDesktopMainQueryCoreBridge bridge = new();
        WindowsMainWindowViewModel model = new(bridge);
        await model.OpenRepositoryAsync(Route(@"C:\Repos\AreaMatrix"));
        bridge.ClearRequests();

        await model.RefreshAndSelectFileAsync(2);

        TestAssert.SequenceEqual([@"C:\Repos\AreaMatrix"], bridge.ListRequests, "list requests");
        TestAssert.SequenceEqual([@"C:\Repos\AreaMatrix"], bridge.TreeRequests, "tree requests");
        TestAssert.SequenceEqual([2L], bridge.DetailRequests, "detail requests");
        TestAssert.Equal(2, model.SelectedFile?.Id, "selected imported file id");
    }


    private static async Task OneDriveRepositoryExposesConnectedNoticeRoute()
    {
        const string path = @"C:\Users\me\OneDrive\AreaMatrix";
        FakeDesktopMainQueryCoreBridge bridge = new();
        WindowsMainWindowViewModel model = new(bridge);

        await model.OpenRepositoryAsync(OneDriveRoute(path));

        TestAssert.True(model.CanOpenOneDriveStatus, nameof(model.CanOpenOneDriveStatus));
        TestAssert.Equal(
            WindowsRepositoryRouteKind.OneDriveNotice,
            model.OneDriveStatusRoute?.Kind,
            "OneDrive status route kind");
        TestAssert.Equal(
            WindowsCloudStorageProviderKind.OneDrive,
            model.OneDriveStatusRoute?.CloudStorageState?.ProviderKind,
            "OneDrive status cloud state");
    }

    private static async Task MainWindowRouteExposesWatcherStatusEntry()
    {
        const string path = @"C:\Repos\AreaMatrix";
        FakeDesktopMainQueryCoreBridge bridge = new();
        WindowsMainWindowViewModel model = new(bridge);

        await model.OpenRepositoryAsync(Route(path));

        TestAssert.True(model.CanOpenWatcherStatus, nameof(model.CanOpenWatcherStatus));
        TestAssert.Equal(
            WindowsRepositoryRouteKind.WatcherStatus,
            model.WatcherStatusRoute?.Kind,
            "watcher status route kind");
        TestAssert.Equal(path, model.WatcherStatusRoute?.RepoPath, "watcher status route path");
    }

    private static WindowsRepositoryRoute Route(string path)
    {
        return new WindowsRepositoryRoute(
            WindowsRepositoryRouteKind.MainWindow,
            path,
            WindowsRepositoryValidationSamples.Initialized(path),
            new WindowsRepositoryConfig(path, "Copied", "en-US"));
    }

    private static WindowsRepositoryRoute OneDriveRoute(string path)
    {
        return new WindowsRepositoryRoute(
            WindowsRepositoryRouteKind.MainWindow,
            path,
            WindowsRepositoryValidationSamples.OneDriveDirectory(path),
            new WindowsRepositoryConfig(path, "Copied", "en-US"),
            WindowsCloudStorageStateSamples.AcknowledgedOneDrive(path));
    }
}

internal sealed class FakeDesktopMainQueryCoreBridge : IDesktopMainQueryCoreBridge
{
    private readonly IReadOnlyList<DesktopFileEntry> files =
    [
        FileEntry(1, "Contracts", "client-contract.pdf"),
        FileEntry(2, "Notes", "meeting-notes.md")
    ];

    public List<string> ListRequests { get; } = [];

    public List<string> TreeRequests { get; } = [];

    public List<string> SearchRequests { get; } = [];

    public List<long> DetailRequests { get; } = [];

    public Exception? ThrowOnList { get; set; }

    public void ClearRequests()
    {
        ListRequests.Clear();
        TreeRequests.Clear();
        SearchRequests.Clear();
        DetailRequests.Clear();
    }

    public Task<IReadOnlyList<DesktopFileEntry>> ListFilesAsync(
        string repoPath,
        DesktopFileFilter filter,
        CancellationToken cancellationToken = default)
    {
        ListRequests.Add(repoPath);
        if (ThrowOnList is not null)
        {
            throw ThrowOnList;
        }

        return Task.FromResult(files);
    }

    public Task<DesktopFileEntry> GetFileAsync(
        string repoPath,
        long fileId,
        CancellationToken cancellationToken = default)
    {
        DetailRequests.Add(fileId);
        return Task.FromResult(files.First(file => file.Id == fileId));
    }

    public Task<IReadOnlyList<DesktopCategoryNode>> ListCategoriesAsync(
        string repoPath,
        string locale,
        CancellationToken cancellationToken = default)
    {
        TreeRequests.Add(repoPath);
        IReadOnlyList<DesktopCategoryNode> categories =
        [
            new DesktopCategoryNode("__root__", "All Files", "RepositoryRoot", string.Empty, 2, 3072, 0, []),
            new DesktopCategoryNode("Contracts", "Contracts", "SystemCategory", "Contracts", 1, 2048, 1, [])
        ];
        return Task.FromResult(categories);
    }

    public Task<DesktopSearchResultPage> SearchFilesAsync(
        string repoPath,
        string query,
        DesktopSearchFilter filter,
        DesktopSearchSort sort,
        DesktopSearchPagination pagination,
        CancellationToken cancellationToken = default)
    {
        SearchRequests.Add(query);
        DesktopSearchResultPage page = new(
            query,
            1,
            [new DesktopSearchFileResult(files[0], 1, [], null)],
            [],
            DesktopSearchIndexStatus.Ready);
        return Task.FromResult(page);
    }

    private static DesktopFileEntry FileEntry(long id, string category, string name)
    {
        return new DesktopFileEntry(
            id,
            $@"{category}\{name}",
            name,
            name,
            category,
            2048,
            $"hash-{id}",
            DesktopStorageMode.Copied,
            DesktopFileOrigin.Imported,
            null,
            DesktopFileAvailabilityStatus.Available,
            1_700_000_000,
            1_700_000_100);
    }
}
