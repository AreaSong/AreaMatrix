using AreaMatrix.Linux.Tests.ChooseRepository;

namespace AreaMatrix.Linux.Tests.Library;

public static class LinuxMainWindowSmokeTests
{
    public static void RunAll()
    {
        LinuxMainWindowPageExposesC411UserTriggers();
        LinuxDesktopShellWiresRouteToRealCoreBridge();
        NativeClientBindsOnlyC411QueryFunctions();
    }

    private static void LinuxMainWindowPageExposesC411UserTriggers()
    {
        string ui = File.ReadAllText(RepositoryPath(
            "apps/linux/AreaMatrix/Features/Library/MainWindow.ui"));
        string view = File.ReadAllText(RepositoryPath(
            "apps/linux/AreaMatrix/Features/Library/LinuxMainWindow.cs"));
        string viewModel = File.ReadAllText(RepositoryPath(
            "apps/linux/AreaMatrix/Features/Library/LinuxMainWindowViewModel.cs"));
        string snapshotModel = File.ReadAllText(RepositoryPath(
            "apps/linux/AreaMatrix/Features/Library/LinuxMainWindowViewModel.Snapshot.cs"));
        string models = File.ReadAllText(RepositoryPath(
            "apps/linux/AreaMatrix/Features/Library/DesktopMainQueryModels.cs"));

        foreach (string fragment in new[]
        {
            "page_id: S4-LNX-02",
            "AreaMatrix Library",
            "Search",
            "Refresh",
            "Categories from list_tree_json",
            "Local folder",
            "Watcher: platform status",
            "DB: ready",
            "The page calls list_files through DesktopMainQueryCoreBridge.",
            "The page calls get_file through DesktopMainQueryCoreBridge.",
            "The page calls list_tree_json through DesktopMainQueryCoreBridge.",
            "The page calls search_files through DesktopMainQueryCoreBridge.",
            "Load more advances FileFilter/SearchPagination offset through DesktopMainQueryCoreBridge.",
            "Refresh only reloads the current snapshot and never runs reindex or rescan.",
            "The Linux UI does not scan the repository filesystem to build the list."
        })
        {
            TestAssert.Contains(fragment, ui, $"UI fragment {fragment}");
        }

        TestAssert.Contains("RefreshAsync", view, "refresh action");
        TestAssert.Contains("RunSearchAsync", viewModel, "search trigger");
        TestAssert.Contains("LoadMoreAsync", view, "load more action");
        TestAssert.Contains("LoadMoreAsync", viewModel, "load more trigger");
        TestAssert.Contains("SelectCategoryAsync", viewModel, "category trigger");
        TestAssert.Contains("SelectFileAsync", viewModel, "detail trigger");
        TestAssert.Contains("ListFilesAsync", snapshotModel, "list_files bridge call");
        TestAssert.Contains("ListCategoriesAsync", snapshotModel, "list_tree_json bridge call");
        TestAssert.Contains("SearchFilesAsync", viewModel, "search_files bridge call");
        TestAssert.Contains("DesktopFileFilter.Page", snapshotModel, "list_files page filter");
        TestAssert.Contains("DesktopSearchPagination(PageSize, Snapshot.NextOffset)", snapshotModel, "search page offset");
        TestAssert.Contains("CanLoadMore", viewModel, "load more visible state");
        TestAssert.Contains("PageText", models, "pagination visible text");
        TestAssert.NotContains("EnumerateFiles", viewModel, "no filesystem list scan");
        TestAssert.NotContains("GetFiles", viewModel, "no filesystem list scan");
    }

    private static void LinuxDesktopShellWiresRouteToRealCoreBridge()
    {
        string shell = File.ReadAllText(RepositoryPath(
            "apps/linux/AreaMatrix/Features/Library/LinuxDesktopShell.cs"));

        TestAssert.Contains("ConsumeRouteAsync", shell, "route consumer");
        TestAssert.Contains("LinuxRepositoryRouteKind.LocalFolderNotice", shell, "local folder notice route");
        TestAssert.Contains("LinuxRepositoryRouteKind.MainWindow", shell, "main window route");
        TestAssert.Contains("CreateDefault", shell, "default production shell");
        TestAssert.Contains("AreaMatrixNativeCoreClient nativeCoreClient = new()", shell, "real native core client");
        TestAssert.Contains("LinuxRepositoryCoreBridge repositoryBridge = new(nativeCoreClient)", shell, "repository bridge");
        TestAssert.Contains("new LinuxLocalFolderNoticeFactory(repositoryBridge)", shell, "local notice bridge");
        TestAssert.Contains("DesktopMainQueryCoreBridge queryBridge = new(nativeCoreClient)", shell, "query bridge");
        TestAssert.Contains("new LocalFolderNoticeViewModel(coreBridge)", shell, "local notice view model");
        TestAssert.Contains("new LinuxMainWindowViewModel(coreBridge", shell, "main window view model");
        TestAssert.NotContains("FakeDesktopMainQueryCoreBridge", shell, "no fake bridge in production shell");
    }

    private static void NativeClientBindsOnlyC411QueryFunctions()
    {
        string nativeLibrary = File.ReadAllText(RepositoryPath(
            "apps/linux/AreaMatrix/Core/NativeCoreLibrary.cs"));
        string queryClient = File.ReadAllText(RepositoryPath(
            "apps/linux/AreaMatrix/Core/AreaMatrixNativeCoreClient.DesktopMainQuery.cs"));

        TestAssert.Contains(
            "uniffi_area_matrix_core_fn_func_list_files",
            nativeLibrary,
            "list_files native binding");
        TestAssert.Contains(
            "uniffi_area_matrix_core_fn_func_get_file",
            nativeLibrary,
            "get_file native binding");
        TestAssert.Contains(
            "uniffi_area_matrix_core_fn_func_list_tree_json",
            nativeLibrary,
            "list_tree_json native binding");
        TestAssert.Contains(
            "uniffi_area_matrix_core_fn_func_search_files",
            nativeLibrary,
            "search_files native binding");
        TestAssert.Contains("LowerFileFilter", queryClient, "file filter lowering");
        TestAssert.Contains("LowerSearchFilter", queryClient, "search filter lowering");
        TestAssert.Contains("ReadSearchResultPage", queryClient, "search result reading");
        TestAssert.Contains("ReadFileAvailabilityStatus", queryClient, "missing badge reading");
        TestAssert.NotContains("reindex_from_filesystem", nativeLibrary, "out-of-scope rescan binding");
        TestAssert.NotContains("record_watcher_health", nativeLibrary, "out-of-scope watcher binding");
    }

    private static string RepositoryPath(string relativePath)
    {
        string? current = AppContext.BaseDirectory;
        while (!string.IsNullOrWhiteSpace(current))
        {
            string candidate = Path.Combine(current, relativePath);
            if (File.Exists(candidate))
            {
                return candidate;
            }

            current = Directory.GetParent(current)?.FullName;
        }

        throw new InvalidOperationException($"Repository file `{relativePath}` was not found.");
    }
}
