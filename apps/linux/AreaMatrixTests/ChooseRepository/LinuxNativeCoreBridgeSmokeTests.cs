using AreaMatrix.Linux.Core;
using AreaMatrix.Linux.Features.Library;
using AreaMatrix.Linux.Features.Onboarding;

namespace AreaMatrix.Linux.Tests.ChooseRepository;

public static class LinuxNativeCoreBridgeSmokeTests
{
    public static async Task RunAllAsync()
    {
        await NativeClientLoadsCoreAndValidatesRepositoryPath();
        await NativeClientOpensInitializedRepositoryThroughDesktopMainQueryBridge();
    }

    private static async Task NativeClientLoadsCoreAndValidatesRepositoryPath()
    {
        string libraryPath = ResolveNativeLibraryPath();
        string tempRoot = Path.Combine(Path.GetTempPath(), $"areamatrix-lnx-c410-{Guid.NewGuid():N}");
        Directory.CreateDirectory(tempRoot);
        try
        {
            using AreaMatrixNativeCoreClient client = new(libraryPath);
            CoreRepoPathValidation validation = await client.ValidateRepoPathAsync(tempRoot);

            TestAssert.Equal(tempRoot, validation.RepoPath, nameof(validation.RepoPath));
            TestAssert.True(validation.Exists, nameof(validation.Exists));
            TestAssert.True(validation.IsDirectory, nameof(validation.IsDirectory));
            TestAssert.True(validation.IsReadable, nameof(validation.IsReadable));
            TestAssert.True(validation.IsWritable, nameof(validation.IsWritable));
            TestAssert.True(validation.IsEmpty, nameof(validation.IsEmpty));
            TestAssert.False(validation.IsInitialized, nameof(validation.IsInitialized));
            TestAssert.Equal("CreateEmpty", validation.RecommendedMode, nameof(validation.RecommendedMode));
        }
        finally
        {
            Directory.Delete(tempRoot, recursive: true);
        }
    }

    private static async Task NativeClientOpensInitializedRepositoryThroughDesktopMainQueryBridge()
    {
        string libraryPath = ResolveNativeLibraryPath();
        string tempRoot = Path.Combine(Path.GetTempPath(), $"areamatrix-lnx-c411-{Guid.NewGuid():N}");
        Directory.CreateDirectory(tempRoot);
        try
        {
            using AreaMatrixNativeCoreClient client = new(libraryPath);
            await client.InitRepoAsync(tempRoot, CoreRepoInitOptions.CreateEmptyGeneratedOnly);
            DesktopMainQueryCoreBridge bridge = new(client);

            IReadOnlyList<DesktopFileEntry> files = await bridge.ListFilesAsync(
                tempRoot,
                DesktopFileFilter.FirstPage());
            IReadOnlyList<DesktopCategoryNode> categories = await bridge.ListCategoriesAsync(
                tempRoot,
                "en-US");
            DesktopSearchResultPage searchPage = await bridge.SearchFilesAsync(
                tempRoot,
                "contract",
                DesktopSearchFilter.AllRepository(),
                DesktopSearchSort.Relevance,
                new DesktopSearchPagination(50, 0));

            TestAssert.Empty(files, "empty repo list_files");
            TestAssert.True(categories.Count > 0, "list_tree_json categories");
            TestAssert.Equal("contract", searchPage.Query, "search query echo");
            TestAssert.Equal(0, searchPage.TotalCount, "empty repo search total");
        }
        finally
        {
            Directory.Delete(tempRoot, recursive: true);
        }
    }

    private static string ResolveNativeLibraryPath()
    {
        string? configured = Environment.GetEnvironmentVariable("AREAMATRIX_CORE_LIBRARY");
        if (!string.IsNullOrWhiteSpace(configured) && File.Exists(configured))
        {
            return configured;
        }

        string[] candidates =
        [
            "core/target/debug/deps/libarea_matrix_core.dylib",
            "core/target/debug/libarea_matrix_core.dylib",
            "core/target/release/deps/libarea_matrix_core.dylib",
            "core/target/release/libarea_matrix_core.dylib",
            "core/target/debug/deps/libarea_matrix_core.so",
            "core/target/debug/libarea_matrix_core.so",
            "core/target/release/deps/libarea_matrix_core.so",
            "core/target/release/libarea_matrix_core.so"
        ];

        foreach (string candidate in candidates.Select(RepositoryPath))
        {
            if (File.Exists(candidate))
            {
                return candidate;
            }
        }

        throw new InvalidOperationException(
            "Native AreaMatrix Core library was not found. Set AREAMATRIX_CORE_LIBRARY or build core cdylib first.");
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

        return Path.GetFullPath(relativePath);
    }
}
