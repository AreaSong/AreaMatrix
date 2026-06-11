using AreaMatrix.Linux.Features.Onboarding;

namespace AreaMatrix.Linux.Tests.ChooseRepository;

public static class LinuxChooseRepositorySmokeTests
{
    public static void RunAll()
    {
        LinuxChooseRepositoryPageExposesRequiredUserActions();
        LinuxChooseRepositoryUsesOnlyC410CoreBridge();
        RecentRepositoryStatusReasonsMatchPageSpec();
    }

    private static void LinuxChooseRepositoryPageExposesRequiredUserActions()
    {
        string ui = File.ReadAllText(RepositoryPath(
            "apps/linux/AreaMatrix/Features/Onboarding/ChooseRepositoryView.ui"));
        string view = File.ReadAllText(RepositoryPath(
            "apps/linux/AreaMatrix/Features/Onboarding/LinuxChooseRepositoryView.cs"));
        string picker = File.ReadAllText(RepositoryPath(
            "apps/linux/AreaMatrix/Features/Onboarding/LinuxFolderPickerAdapter.cs"));

        foreach (string fragment in new[]
        {
            "page_id: S4-LNX-01",
            "Choose AreaMatrix Repository",
            "Repository folder",
            "Browse...",
            "Use default: ~/AreaMatrix",
            "Checking folder...",
            "Network or removable path detected",
            "S4-LNX-03",
            "The page calls validate_repo_path through LinuxRepositoryCoreBridge.",
            "The page does not suggest sudo or chmod."
        })
        {
            TestAssert.Contains(fragment, ui, $"UI fragment {fragment}");
        }

        TestAssert.Contains("PickFolderAsync", view, "folder picker adapter");
        TestAssert.Contains("LinuxSystemFolderPickerAdapter", picker, "system folder picker adapter");
        TestAssert.Contains("zenity", picker, "GTK folder picker command");
        TestAssert.Contains("kdialog", picker, "Qt folder picker command");
        TestAssert.NotContains("LinuxNoopFolderPickerAdapter", picker, "no noop folder picker");
        TestAssert.Contains("UseDefaultPathAsync", view, "default path action");
        TestAssert.Contains("SelectRecentRepositoryAsync", view, "recent repository action");
        TestAssert.Contains("ContinueAsync", view, "continue action");
    }

    private static void LinuxChooseRepositoryUsesOnlyC410CoreBridge()
    {
        string nativeClient = File.ReadAllText(RepositoryPath(
            "apps/linux/AreaMatrix/Core/AreaMatrixNativeCoreClient.cs"));
        string nativeLibrary = File.ReadAllText(RepositoryPath(
            "apps/linux/AreaMatrix/Core/NativeCoreLibrary.cs"));
        string viewModel = File.ReadAllText(RepositoryPath(
            "apps/linux/AreaMatrix/Features/Onboarding/LinuxChooseRepositoryViewModel.cs"));

        TestAssert.Contains("uniffi_area_matrix_core_fn_func_validate_repo_path", nativeLibrary, "validate symbol");
        TestAssert.Contains("uniffi_area_matrix_core_fn_func_init_repo", nativeLibrary, "init symbol");
        TestAssert.Contains(
            "uniffi_area_matrix_core_fn_func_get_platform_capabilities",
            nativeLibrary,
            "platform capability symbol");
        TestAssert.Contains("ValidateRepoPathChecksum = 43498", nativeClient, "validate checksum");
        TestAssert.Contains("InitRepoChecksum = 29414", nativeClient, "init checksum");
        TestAssert.Contains("GetPlatformCapabilitiesChecksum = 42907", nativeClient, "platform checksum");
        TestAssert.Contains("ValidateRepoPathAsync", viewModel, "view model bridge call");
        TestAssert.NotContains("DetectCloudStorageStateAsync", nativeClient, "out-of-scope cloud capability");
        TestAssert.NotContains("LoadConfigAsync", viewModel, "out-of-scope config load");
        TestAssert.NotContains("sudo", viewModel, "no sudo suggestion");
        TestAssert.NotContains("chmod", viewModel, "no chmod suggestion");
    }

    private static void RecentRepositoryStatusReasonsMatchPageSpec()
    {
        TestAssert.Equal("Missing", Recent(LinuxRecentRepositoryStatus.Missing).StatusReason, "missing");
        TestAssert.Equal(
            "Permission denied",
            Recent(LinuxRecentRepositoryStatus.PermissionDenied).StatusReason,
            "permission");
        TestAssert.Equal(
            "Disk unavailable",
            Recent(LinuxRecentRepositoryStatus.DiskUnavailable).StatusReason,
            "disk");
    }

    private static LinuxRecentRepository Recent(LinuxRecentRepositoryStatus status)
    {
        return new LinuxRecentRepository(
            "AreaMatrix",
            "/home/me/AreaMatrix",
            "Opened today",
            status);
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
