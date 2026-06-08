namespace AreaMatrix.Linux.Tests.ChooseRepository;

public static class LocalFolderNoticeSmokeTests
{
    public static void RunAll()
    {
        LocalFolderNoticePageExposesC410Actions();
        LocalFolderNoticeUsesOnlyRepositoryCoreBridge();
    }

    private static void LocalFolderNoticePageExposesC410Actions()
    {
        string ui = File.ReadAllText(RepositoryPath(
            "apps/linux/AreaMatrix/Features/Onboarding/LocalFolderNoticeView.ui"));
        string view = File.ReadAllText(RepositoryPath(
            "apps/linux/AreaMatrix/Features/Onboarding/LocalFolderNoticeView.cs"));
        string opener = File.ReadAllText(RepositoryPath(
            "apps/linux/AreaMatrix/Features/Onboarding/LinuxFolderOpener.cs"));

        foreach (string fragment in new[]
        {
            "page_id: S4-LNX-03",
            "Repository folder on Linux",
            "Folder: /home/you/AreaMatrix",
            "Type: Local folder",
            "Type: External drive",
            "Type: Network mount",
            "Type: Sync folder",
            "Type: Unknown",
            "Writable: Yes/No",
            "Platform capabilities: Watcher available; Cloud placeholders not available.",
            "I understand this location may not report changes reliably.",
            "Continue",
            "Choose Another Folder",
            "Open Folder",
            "The page calls validate_repo_path through LinuxRepositoryCoreBridge.",
            "The page calls get_platform_capabilities through LinuxPlatformCapabilitiesCoreBridge.",
            "Watcher and cloud placeholder rows come from the C4-17 PlatformCapabilities matrix.",
            "The page does not call cloud storage detection or configure sync providers."
        })
        {
            TestAssert.Contains(fragment, ui, $"UI fragment {fragment}");
        }

        TestAssert.Contains("ContinueAsync", view, "continue action");
        TestAssert.Contains("ChooseAnotherFolder", view, "choose another action");
        TestAssert.Contains("OpenFolderAsync", view, "open folder action");
        TestAssert.Contains("xdg-open", opener, "file manager command");
        TestAssert.Contains("gio", opener, "GNOME file manager command");
        TestAssert.NotContains("sudo", opener, "no sudo suggestion");
        TestAssert.NotContains("chmod", opener, "no chmod suggestion");
    }

    private static void LocalFolderNoticeUsesOnlyRepositoryCoreBridge()
    {
        string viewModel = File.ReadAllText(RepositoryPath(
            "apps/linux/AreaMatrix/Features/Onboarding/LocalFolderNoticeViewModel.cs"));
        string bridge = File.ReadAllText(RepositoryPath(
            "apps/linux/AreaMatrix/Features/Onboarding/LinuxRepositoryCoreBridge.cs"));

        TestAssert.Contains("ILinuxRepositoryCoreBridge", viewModel, "repository bridge");
        TestAssert.Contains("ILinuxPlatformCapabilitiesCoreBridge", viewModel, "platform bridge");
        TestAssert.Contains("ValidateRepoPathAsync", viewModel, "validate_repo_path bridge call");
        TestAssert.Contains("GetPlatformCapabilitiesAsync", viewModel, "get_platform_capabilities bridge call");
        TestAssert.Contains("InitializeEmptyRepositoryAsync", bridge, "init_repo bridge available");
        TestAssert.Contains("AdoptExistingRepositoryAsync", bridge, "adopt init_repo bridge available");
        TestAssert.NotContains("DetectCloudStorageStateAsync", viewModel, "out-of-scope C4-17/cloud call");
        TestAssert.NotContains("LoadConfigAsync", viewModel, "out-of-scope config call");
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
