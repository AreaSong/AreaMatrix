using AreaMatrix.Linux.Features.Library;
using AreaMatrix.Linux.Features.Conflicts;
using AreaMatrix.Linux.Features.Onboarding;
using AreaMatrix.Linux.Tests.ChooseRepository;

namespace AreaMatrix.Linux.Tests.Library;

public static class LinuxMainWindowViewModelTests
{
    public static async Task RunAllAsync()
    {
        await RepositoryRouteOpensMainWindowThroughProductionShell();
        await LocalFolderNoticeRouteIsHostedBeforeContinuing();
        await OpenRepositoryLoadsTreeAndFirstPageFromCoreBridge();
        await LoadMoreAdvancesListOffsetThroughCoreBridge();
        await SearchUsesCoreSearchWithoutScanningRepository();
        await LoadMoreAdvancesSearchPaginationThroughCoreBridge();
        await SelectingFileUsesCoreDetailQuery();
        await RefreshKeepsCachedListOnDbError();
    }

    private static async Task RepositoryRouteOpensMainWindowThroughProductionShell()
    {
        FakeDesktopMainQueryCoreBridge queryBridge = new();
        FakeLinuxMainWindowFactory factory = new(queryBridge);
        LinuxChooseRepositoryViewModel chooseModel = new(
            new FakeLinuxRepositoryCoreBridge(
                LinuxRepositoryValidationSamples.Initialized("/home/me/AreaMatrix")));
        LinuxChooseRepositoryView chooseView = new(
            chooseModel,
            new FakeLinuxFolderPickerAdapter("/home/me/AreaMatrix"));
        LinuxDesktopShell shell = new(chooseView, factory);

        await chooseView.TypeRepositoryPathAsync("/home/me/AreaMatrix");
        await shell.ContinueFromRepositorySelectionAsync();

        TestAssert.Equal(1, factory.CreatedRoutes.Count, "created main windows");
        TestAssert.NotNull(shell.MainWindow, nameof(shell.MainWindow));
        TestAssert.Equal("AreaMatrix", shell.MainWindow?.ViewModel.RepoName, "main repo name");
        TestAssert.SequenceEqual(["/home/me/AreaMatrix"], queryBridge.ListRequests, "list requests");
        TestAssert.Equal(LinuxRepositoryRouteKind.None, chooseModel.Route.Kind, "consumed route");
    }

    private static async Task LocalFolderNoticeRouteIsHostedBeforeContinuing()
    {
        const string path = "//server/share/AreaMatrix";
        FakeDesktopMainQueryCoreBridge queryBridge = new();
        FakeLinuxRepositoryCoreBridge repositoryBridge = new(LinuxRepositoryValidationSamples.NetworkShare(path));
        FakeLinuxMainWindowFactory mainWindowFactory = new(queryBridge);
        FakeLocalFolderNoticeFactory noticeFactory = new(repositoryBridge);
        LinuxChooseRepositoryViewModel chooseModel = new(repositoryBridge);
        LinuxChooseRepositoryView chooseView = new(chooseModel, new FakeLinuxFolderPickerAdapter(path));
        LinuxDesktopShell shell = new(chooseView, mainWindowFactory, noticeFactory);

        await chooseView.TypeRepositoryPathAsync(path);
        await shell.ContinueFromRepositorySelectionAsync();

        TestAssert.NotNull(shell.LocalFolderNoticeView, nameof(shell.LocalFolderNoticeView));
        TestAssert.Equal(LinuxRepositoryRouteKind.None, chooseModel.Route.Kind, "choose route consumed");
        TestAssert.Empty(mainWindowFactory.CreatedRoutes, "main window before notice confirmation");
        TestAssert.SequenceEqual([path], noticeFactory.CreatedRoutes.Select(route => route.RepoPath).ToArray(), "notice route");

        shell.LocalFolderNoticeView!.ViewModel.IsRiskNoticeConfirmed = true;
        await shell.ContinueFromLocalFolderNoticeAsync();

        TestAssert.Equal(LinuxRepositoryRouteKind.RepositoryAdoptConfirm, shell.LocalFolderNoticeView.ViewModel.Route.Kind, "next route");
        TestAssert.Empty(queryBridge.ListRequests, "no main query before adopt confirmation");
        TestAssert.Empty(repositoryBridge.InitializedPaths, nameof(repositoryBridge.InitializedPaths));
        TestAssert.Empty(repositoryBridge.AdoptedPaths, nameof(repositoryBridge.AdoptedPaths));
    }

    private static async Task OpenRepositoryLoadsTreeAndFirstPageFromCoreBridge()
    {
        FakeDesktopMainQueryCoreBridge bridge = new();
        LinuxMainWindowViewModel model = new(bridge);

        await model.OpenRepositoryAsync(Route("/home/me/AreaMatrix"));

        TestAssert.SequenceEqual(["/home/me/AreaMatrix"], bridge.TreeRequests, "tree requests");
        TestAssert.SequenceEqual(["/home/me/AreaMatrix"], bridge.ListRequests, "list requests");
        TestAssert.Empty(bridge.SearchRequests, nameof(bridge.SearchRequests));
        TestAssert.Equal("AreaMatrix", model.RepoName, nameof(model.RepoName));
        TestAssert.Equal(2, model.Files.Count, "visible files");
        TestAssert.Null(model.Error, nameof(model.Error));
        TestAssert.False(model.CanLoadMore, nameof(model.CanLoadMore));
        TestAssert.Equal(50, bridge.ListFilters.Single().Limit, "first page limit");
        TestAssert.Equal(0, bridge.ListFilters.Single().Offset, "first page offset");
    }

    private static async Task LoadMoreAdvancesListOffsetThroughCoreBridge()
    {
        FakeDesktopMainQueryCoreBridge bridge = new(fileCount: 120);
        LinuxMainWindowViewModel model = new(bridge);

        await model.OpenRepositoryAsync(Route("/home/me/AreaMatrix"));
        bridge.ClearRequests();
        await model.LoadMoreAsync();

        TestAssert.Equal(100, model.Files.Count, "loaded files");
        TestAssert.Equal(50, bridge.ListFilters.Single().Limit, "next page limit");
        TestAssert.Equal(50, bridge.ListFilters.Single().Offset, "next page offset");
        TestAssert.True(model.CanLoadMore, nameof(model.CanLoadMore));
    }

    private static async Task SearchUsesCoreSearchWithoutScanningRepository()
    {
        FakeDesktopMainQueryCoreBridge bridge = new();
        LinuxMainWindowViewModel model = new(bridge);

        await model.OpenRepositoryAsync(Route("/home/me/AreaMatrix"));
        bridge.ClearRequests();
        model.SearchQuery = "contract";
        await model.RunSearchAsync();

        TestAssert.SequenceEqual(["/home/me/AreaMatrix"], bridge.TreeRequests, "tree requests");
        TestAssert.Empty(bridge.ListRequests, nameof(bridge.ListRequests));
        TestAssert.SequenceEqual(["contract"], bridge.SearchRequests, "search requests");
        TestAssert.Equal("contract", model.Snapshot.Query, "snapshot query");
        TestAssert.Equal(DesktopSearchIndexStatus.Ready, model.Snapshot.SearchIndexStatus, "index status");
        TestAssert.Equal(0, bridge.SearchPaginations.Single().Offset, "search first page offset");
        TestAssert.False(model.CanLoadMore, nameof(model.CanLoadMore));
    }

    private static async Task LoadMoreAdvancesSearchPaginationThroughCoreBridge()
    {
        FakeDesktopMainQueryCoreBridge bridge = new(fileCount: 75);
        LinuxMainWindowViewModel model = new(bridge);

        await model.OpenRepositoryAsync(Route("/home/me/AreaMatrix"));
        model.SearchQuery = "contract";
        await model.RunSearchAsync();
        bridge.ClearRequests();
        await model.LoadMoreAsync();

        TestAssert.SequenceEqual(["contract"], bridge.SearchRequests, "search requests");
        TestAssert.Equal(75, model.Files.Count, "search files");
        TestAssert.Equal(50, bridge.SearchPaginations.Single().Offset, "search next offset");
        TestAssert.False(model.CanLoadMore, nameof(model.CanLoadMore));
    }

    private static async Task SelectingFileUsesCoreDetailQuery()
    {
        FakeDesktopMainQueryCoreBridge bridge = new();
        LinuxMainWindowViewModel model = new(bridge);

        await model.OpenRepositoryAsync(Route("/home/me/AreaMatrix"));
        DesktopFileEntry selected = model.Files[0];
        await model.SelectFileAsync(selected);

        TestAssert.SequenceEqual([selected.Id], bridge.DetailRequests, "detail requests");
        TestAssert.Equal(selected.Id, model.SelectedFile?.Id, "selected file id");
        TestAssert.Contains(selected.DisplayName, model.SelectedFileTitle, nameof(model.SelectedFileTitle));
    }

    private static async Task RefreshKeepsCachedListOnDbError()
    {
        FakeDesktopMainQueryCoreBridge bridge = new();
        LinuxMainWindowViewModel model = new(bridge);
        await model.OpenRepositoryAsync(Route("/home/me/AreaMatrix"));
        int previousCount = model.Files.Count;

        bridge.ThrowOnList = new DesktopQueryCoreException(
            DesktopQueryErrorKind.Db,
            "Repository database could not be read.");
        await model.RefreshAsync();

        TestAssert.Equal(previousCount, model.Files.Count, "cached file count");
        TestAssert.Equal(LinuxRepositoryErrorKind.Db, model.Error?.Kind, "error kind");
        TestAssert.Contains("database", model.StatusText, nameof(model.StatusText));
    }

    private static LinuxRepositoryRoute Route(string path)
    {
        return new LinuxRepositoryRoute(
            LinuxRepositoryRouteKind.MainWindow,
            path,
            LinuxRepositoryValidationSamples.Initialized(path));
    }
}

internal sealed class FakeDesktopMainQueryCoreBridge : IDesktopMainQueryCoreBridge
{
    private readonly IReadOnlyList<DesktopFileEntry> files;

    public FakeDesktopMainQueryCoreBridge(int fileCount = 2)
    {
        files = Enumerable
            .Range(1, fileCount)
            .Select(index => FileEntry(index))
            .ToArray();
    }

    public List<string> ListRequests { get; } = [];

    public List<string> TreeRequests { get; } = [];

    public List<string> SearchRequests { get; } = [];

    public List<long> DetailRequests { get; } = [];

    public List<DesktopFileFilter> ListFilters { get; } = [];

    public List<DesktopSearchPagination> SearchPaginations { get; } = [];

    public Exception? ThrowOnList { get; set; }

    public void ClearRequests()
    {
        ListRequests.Clear();
        TreeRequests.Clear();
        SearchRequests.Clear();
        DetailRequests.Clear();
        ListFilters.Clear();
        SearchPaginations.Clear();
    }

    public Task<IReadOnlyList<DesktopFileEntry>> ListFilesAsync(
        string repoPath,
        DesktopFileFilter filter,
        CancellationToken cancellationToken = default)
    {
        ListRequests.Add(repoPath);
        ListFilters.Add(filter);
        if (ThrowOnList is not null)
        {
            throw ThrowOnList;
        }

        IReadOnlyList<DesktopFileEntry> page = files
            .Skip(checked((int)filter.Offset))
            .Take(checked((int)filter.Limit))
            .ToArray();
        return Task.FromResult(page);
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
        SearchPaginations.Add(pagination);
        DesktopSearchResultPage page = new(
            query,
            files.Count,
            files
                .Skip(checked((int)pagination.Offset))
                .Take(checked((int)pagination.Limit))
                .Select(file => new DesktopSearchFileResult(file, 1, [], null))
                .ToArray(),
            [],
            DesktopSearchIndexStatus.Ready);
        return Task.FromResult(page);
    }

    private static DesktopFileEntry FileEntry(long id)
    {
        string category = id % 2 == 0 ? "Notes" : "Contracts";
        string name = id % 2 == 0
            ? $"meeting-notes-{id}.md"
            : $"client-contract-{id}.pdf";
        return new DesktopFileEntry(
            id,
            $"{category}/{name}",
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

internal sealed class FakeLinuxMainWindowFactory : ILinuxMainWindowFactory
{
    private readonly IDesktopMainQueryCoreBridge bridge;
    private readonly ISyncConflictEntryCoreBridge? syncConflictBridge;

    public FakeLinuxMainWindowFactory(
        IDesktopMainQueryCoreBridge bridge,
        ISyncConflictEntryCoreBridge? syncConflictBridge = null)
    {
        this.bridge = bridge;
        this.syncConflictBridge = syncConflictBridge;
    }

    public List<LinuxRepositoryRoute> CreatedRoutes { get; } = [];

    public LinuxMainWindow Create(LinuxRepositoryRoute route)
    {
        CreatedRoutes.Add(route);
        return new LinuxMainWindow(new LinuxMainWindowViewModel(bridge, syncConflictBridge));
    }
}

internal sealed class FakeLocalFolderNoticeFactory : ILinuxLocalFolderNoticeFactory
{
    private readonly ILinuxRepositoryCoreBridge bridge;

    public FakeLocalFolderNoticeFactory(ILinuxRepositoryCoreBridge bridge)
    {
        this.bridge = bridge;
    }

    public List<LinuxRepositoryRoute> CreatedRoutes { get; } = [];

    public LocalFolderNoticeView Create(LinuxRepositoryRoute route)
    {
        CreatedRoutes.Add(route);
        return new LocalFolderNoticeView(new LocalFolderNoticeViewModel(bridge));
    }
}
