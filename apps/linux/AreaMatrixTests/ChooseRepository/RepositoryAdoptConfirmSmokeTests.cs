namespace AreaMatrix.Linux.Tests.ChooseRepository;

public static class RepositoryAdoptConfirmSmokeTests
{
    public static void RunAll()
    {
        RepositoryAdoptConfirmPageExposesRequiredActions();
        RepositoryAdoptConfirmUsesOnlyC410CoreBridge();
    }

    private static void RepositoryAdoptConfirmPageExposesRequiredActions()
    {
        string ui = File.ReadAllText(RepositoryPath(
            "apps/linux/AreaMatrix/Features/Onboarding/RepositoryAdoptConfirmView.ui"));
        string view = File.ReadAllText(RepositoryPath(
            "apps/linux/AreaMatrix/Features/Onboarding/RepositoryAdoptConfirmView.cs"));
        string shell = File.ReadAllText(RepositoryPath(
            "apps/linux/AreaMatrix/Features/Library/LinuxDesktopShell.cs"));

        foreach (string fragment in new[]
        {
            "page_id: S4-X-05",
            "platform_slice: Linux C4-10 linux-repo-connect",
            "Use Existing Folder",
            "Folder: /home/you/Existing",
            "Estimated items: Existing files detected by Core validation.",
            "Writable: Yes/No",
            "Existing .areamatrix: Yes/No",
            "Location type: Local folder",
            "Location type: External drive",
            "Location type: Network mount",
            "Location type: Sync folder",
            "Location type: Unknown",
            "AreaMatrix will not move, delete, rename, or overwrite existing files.",
            "It will create a .areamatrix folder for metadata and scan this folder.",
            "Removing .areamatrix metadata later must not remove user files.",
            "I understand AreaMatrix will add metadata to this folder.",
            "I understand this location may sync or report changes differently.",
            "Use This Folder",
            "Try Again",
            "Choose Another Folder",
            "Cancel",
            "The page calls validate_repo_path through LinuxRepositoryCoreBridge when opened.",
            "The page calls init_repo with AdoptExisting through LinuxRepositoryCoreBridge only after Use This Folder.",
            "The page revalidates after init_repo and requires Core to detect .areamatrix metadata.",
            "The page does not suggest sudo or chmod."
        })
        {
            TestAssert.Contains(fragment, ui, $"UI fragment {fragment}");
        }

        TestAssert.Contains("UseThisFolderAsync", view, "use folder action");
        TestAssert.Contains("ChooseAnotherFolder", view, "choose another action");
        TestAssert.Contains("LinuxRepositoryRouteKind.RepositoryAdoptConfirm", shell, "shell route");
        TestAssert.Contains("ContinueFromRepositoryAdoptConfirmAsync", shell, "shell adopt handoff");
        TestAssert.Contains("new LinuxRepositoryAdoptConfirmFactory(repositoryBridge)", shell, "real bridge factory");
    }

    private static void RepositoryAdoptConfirmUsesOnlyC410CoreBridge()
    {
        string viewModel = File.ReadAllText(RepositoryPath(
            "apps/linux/AreaMatrix/Features/Onboarding/RepositoryAdoptConfirmViewModel.cs"));
        string bridge = File.ReadAllText(RepositoryPath(
            "apps/linux/AreaMatrix/Features/Onboarding/LinuxRepositoryCoreBridge.cs"));

        TestAssert.Contains("ValidateRepoPathAsync", viewModel, "validate_repo_path call");
        TestAssert.Contains("AdoptExistingRepositoryAsync", viewModel, "adopt init_repo call");
        TestAssert.Contains("AdoptExistingRepositoryAsync", bridge, "CoreBridge adopt init_repo");
        TestAssert.Contains("CoreRepoInitOptions.AdoptExistingGeneratedOnly", bridge, "AdoptExisting options");
        TestAssert.NotContains("InitializeEmptyRepositoryAsync(RepositoryPath", viewModel, "no create on adopt confirm");
        TestAssert.NotContains("GetPlatformCapabilitiesAsync", viewModel, "no C4-17 platform call");
        TestAssert.NotContains("DetectCloudStorageStateAsync", viewModel, "no cloud state call");
        TestAssert.NotContains("ReindexFromFilesystemAsync", viewModel, "no manual rescan call");
        TestAssert.NotContains("ImportFile", viewModel, "no import call");
        TestAssert.NotContains("sudo", viewModel, "no sudo suggestion");
        TestAssert.NotContains("chmod", viewModel, "no chmod suggestion");
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
