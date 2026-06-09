namespace AreaMatrix.Linux.Tests.ChooseRepository;

public static class RepositoryInitConfirmSmokeTests
{
    public static void RunAll()
    {
        RepositoryInitConfirmPageExposesRequiredActions();
        RepositoryInitConfirmUsesOnlyC410CoreBridge();
    }

    private static void RepositoryInitConfirmPageExposesRequiredActions()
    {
        string ui = File.ReadAllText(RepositoryPath(
            "apps/linux/AreaMatrix/Features/Onboarding/RepositoryInitConfirmView.ui"));
        string view = File.ReadAllText(RepositoryPath(
            "apps/linux/AreaMatrix/Features/Onboarding/RepositoryInitConfirmView.cs"));
        string shell = File.ReadAllText(RepositoryPath(
            "apps/linux/AreaMatrix/Features/Library/LinuxDesktopShell.cs"));

        foreach (string fragment in new[]
        {
            "page_id: S4-X-04",
            "platform_slice: Linux C4-10 linux-repo-connect",
            "Create AreaMatrix Repository",
            "Folder: /home/you/AreaMatrix",
            "Type: Local folder",
            "Type: External drive",
            "Type: Network mount",
            "Type: Sync folder",
            "Writable: Yes/No",
            "AreaMatrix will create a .areamatrix folder here.",
            "No existing files will be moved, deleted, renamed, or overwritten.",
            "Create Repository",
            "Try Again",
            "Choose Another Folder",
            "Cancel",
            "The page calls validate_repo_path through LinuxRepositoryCoreBridge when opened.",
            "The page calls init_repo through LinuxRepositoryCoreBridge only after Create Repository.",
            "The page revalidates after init_repo and requires Core to detect .areamatrix metadata.",
            "The page does not suggest sudo or chmod."
        })
        {
            TestAssert.Contains(fragment, ui, $"UI fragment {fragment}");
        }

        TestAssert.Contains("CreateRepositoryAsync", view, "create action");
        TestAssert.Contains("ChooseAnotherFolder", view, "choose another action");
        TestAssert.Contains("LinuxRepositoryRouteKind.RepositoryInitConfirm", shell, "shell route");
        TestAssert.Contains("ContinueFromRepositoryInitConfirmAsync", shell, "shell create handoff");
        TestAssert.Contains("new LinuxRepositoryInitConfirmFactory(repositoryBridge)", shell, "real bridge factory");
    }

    private static void RepositoryInitConfirmUsesOnlyC410CoreBridge()
    {
        string viewModel = File.ReadAllText(RepositoryPath(
            "apps/linux/AreaMatrix/Features/Onboarding/RepositoryInitConfirmViewModel.cs"));
        string bridge = File.ReadAllText(RepositoryPath(
            "apps/linux/AreaMatrix/Features/Onboarding/LinuxRepositoryCoreBridge.cs"));

        TestAssert.Contains("ValidateRepoPathAsync", viewModel, "validate_repo_path call");
        TestAssert.Contains("InitializeEmptyRepositoryAsync", viewModel, "init_repo call");
        TestAssert.Contains("InitializeEmptyRepositoryAsync", bridge, "CoreBridge init_repo");
        TestAssert.Contains("CoreRepoInitOptions.CreateEmptyGeneratedOnly", bridge, "CreateEmpty options");
        TestAssert.NotContains("AdoptExistingRepositoryAsync(RepositoryPath", viewModel, "no adopt on init confirm");
        TestAssert.NotContains("GetPlatformCapabilitiesAsync", viewModel, "no C4-17 platform call");
        TestAssert.NotContains("DetectCloudStorageStateAsync", viewModel, "no cloud state call");
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
