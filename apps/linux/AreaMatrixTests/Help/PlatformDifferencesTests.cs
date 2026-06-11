using AreaMatrix.Linux.Features.Help;
using AreaMatrix.Linux.Features.Library;
using AreaMatrix.Linux.Features.Onboarding;
using AreaMatrix.Linux.Tests.ChooseRepository;

namespace AreaMatrix.Linux.Tests.Help;

public static class PlatformDifferencesTests
{
    public static async Task RunAllAsync()
    {
        await LinuxHelpPageChecksC401BindingContract();
        await LinuxHelpPageLoadsC417PlatformCapabilities();
        LinuxCapabilityRowsCoverS4X02PageSpecMatrix();
        await CapabilityFailureShowsUnknownRowsWithoutStaticAvailability();
        await ContractFailureShowsRecoveryWithoutStaticSuccess();
        await OpenRepositorySettingsActionRoutesToS4X08();
        await ShellOpensPlatformDifferencesHelpPage();
        PlatformDifferencesUiDeclaresC401AndC417Only();
        NativeClientExportsInspectBindingContract();
    }

    private static async Task LinuxHelpPageChecksC401BindingContract()
    {
        FakePlatformDifferencesCoreBridge bridge = new(ContractReport(PlatformDifferencesBindingTarget.Python));
        PlatformDifferencesViewModel model = new(bridge);

        await model.LoadAsync();

        TestAssert.Equal(LinuxPlatformId.Linux, model.HostPlatform, nameof(model.HostPlatform));
        TestAssert.Equal(PlatformDifferencesContractStatus.Loaded, model.Status, nameof(model.Status));
        TestAssert.Equal(PlatformDifferencesBindingTarget.Python, model.Report?.TargetPlatform, "target");
        TestAssert.SequenceEqual(
            [PlatformDifferencesBindingTarget.Python],
            bridge.Targets,
            "requested targets");
        TestAssert.SequenceEqual([1L], bridge.BindingVersions, "requested versions");
    }

    private static async Task LinuxHelpPageLoadsC417PlatformCapabilities()
    {
        FakePlatformDifferencesCoreBridge bridge = new(ContractReport(PlatformDifferencesBindingTarget.Python))
        {
            Capabilities = CapabilityReport()
        };
        PlatformDifferencesViewModel model = new(bridge, appVersion: "1.2.3");

        await model.LoadAsync();

        TestAssert.Equal(LinuxPlatformId.Linux, model.Capabilities?.Platform, "platform");
        TestAssert.Equal(LinuxPlatformCapabilityStatus.Available, model.Capabilities?.Watcher.Status, "watcher");
        TestAssert.SequenceEqual([LinuxPlatformId.Linux], bridge.Platforms, "requested platforms");
        TestAssert.SequenceEqual(["1.2.3"], bridge.AppVersions, "requested app versions");
        TestAssert.True(
            model.CapabilityRows.Any(row => row.Contains("File watcher - Available", StringComparison.Ordinal)),
            "capability row");
    }

    private static void LinuxCapabilityRowsCoverS4X02PageSpecMatrix()
    {
        IReadOnlyList<string> rows = PlatformDifferencesCapabilitiesDisplay.RowsFor(CapabilityReport());

        TestAssert.Contains("Repository access - Available", rows[0], "repository access row");
        TestAssert.Contains("File import - Limited", rows[1], "file import row");
        TestAssert.Contains("File watcher - Available", rows[2], "file watcher row");
        TestAssert.Contains("Cloud provider - Limited", rows[3], "cloud provider row");
        TestAssert.Contains("Trash / Recycle Bin - Available", rows[4], "trash row");
        TestAssert.Contains("Share integration - Limited", rows[5], "share row");
        TestAssert.Contains("Camera import - Limited", rows[6], "camera row");
        TestAssert.Contains("preflight", rows[1], "import preflight copy");
    }

    private static async Task CapabilityFailureShowsUnknownRowsWithoutStaticAvailability()
    {
        FakePlatformDifferencesCoreBridge bridge = new(ContractReport(PlatformDifferencesBindingTarget.Python))
        {
            CapabilityError = new InvalidOperationException("platform unavailable")
        };
        PlatformDifferencesViewModel model = new(bridge);

        await model.LoadCapabilitiesAsync();

        TestAssert.Equal("Capability snapshot unavailable", model.CapabilityErrorMessage, "capability error");
        TestAssert.Equal(LinuxPlatformCapabilityStatus.Unknown, model.Capabilities?.Watcher.Status, "watcher");
        TestAssert.Contains("platform capability bridge", model.CapabilityRecoveryText ?? "", "capability recovery");
    }

    private static async Task ContractFailureShowsRecoveryWithoutStaticSuccess()
    {
        FakePlatformDifferencesCoreBridge bridge = new(new InvalidOperationException("ffi unavailable"));
        PlatformDifferencesViewModel model = new(bridge);

        await model.LoadAsync();

        TestAssert.Equal(PlatformDifferencesContractStatus.Failed, model.Status, nameof(model.Status));
        TestAssert.Equal("Binding contract unavailable", model.ErrorMessage, nameof(model.ErrorMessage));
        TestAssert.Contains("Core bridge", model.RecoveryText ?? string.Empty, nameof(model.RecoveryText));
        TestAssert.Null(model.Report, nameof(model.Report));
    }

    private static async Task OpenRepositorySettingsActionRoutesToS4X08()
    {
        FakePlatformDifferencesCoreBridge bridge = new(ContractReport(PlatformDifferencesBindingTarget.Python));
        PlatformDifferencesView view = new(new PlatformDifferencesViewModel(bridge));
        var didRequestRepositorySettings = false;
        view.OpenRepositorySettingsRequested += () => didRequestRepositorySettings = true;

        bool didOpen = await view.OpenRepositorySettingsAsync();

        TestAssert.True(didOpen, "S4-X-08 repository settings action");
        TestAssert.True(didRequestRepositorySettings, "S4-X-08 repository settings route");
    }

    private static async Task ShellOpensPlatformDifferencesHelpPage()
    {
        FakePlatformDifferencesCoreBridge bridge = new(ContractReport(PlatformDifferencesBindingTarget.Python));
        FakePlatformDifferencesViewFactory factory = new(bridge);
        LinuxDesktopShell shell = new(
            new LinuxChooseRepositoryView(
                new LinuxChooseRepositoryViewModel(new FakeLinuxRepositoryCoreBridge(
                    LinuxRepositoryValidationSamples.Initialized("/home/you/AreaMatrix"))),
                new FakeLinuxFolderPickerAdapter(null)),
            new LinuxMainWindowFactory(new FakeDesktopMainQueryCoreBridge()),
            platformDifferencesViewFactory: factory);

        await shell.OpenPlatformDifferencesAsync();

        TestAssert.NotNull(shell.PlatformDifferencesView, "platform differences view");
        TestAssert.SequenceEqual([PlatformDifferencesBindingTarget.Python], bridge.Targets, "shell target");
    }

    private static void PlatformDifferencesUiDeclaresC401AndC417Only()
    {
        string ui = File.ReadAllText(RepositoryPath(
            "apps/linux/AreaMatrix/Features/Help/PlatformDifferencesView.ui"));
        string shell = File.ReadAllText(RepositoryPath(
            "apps/linux/AreaMatrix/Features/Library/LinuxDesktopShell.cs"));

        TestAssert.Contains("page_id: S4-X-02", ui, "page id");
        TestAssert.Contains(
            "open_repository_settings: PlatformDifferencesView.OpenRepositorySettingsAsync",
            ui,
            "repository settings action");
        TestAssert.Contains("export_diagnostics: disabled", ui, "diagnostics action");
        TestAssert.Contains(
            "check_capabilities: PlatformDifferencesView.CheckCapabilitiesAsync",
            ui,
            "capability action");
        TestAssert.Contains("check_contract: PlatformDifferencesView.CheckContractAsync", ui, "check action");
        TestAssert.Contains("get_platform_capabilities", ui, "C4-17 Core call");
        TestAssert.Contains("inspect_binding_contract", ui, "C4-01 Core call");
        TestAssert.Contains("does not call watcher health", ui, "same-page capability exclusion");
        TestAssert.Contains("OpenPlatformDifferencesAsync", shell, "shell route");
        TestAssert.Contains("new PlatformDifferencesCoreBridge(nativeCoreClient)", shell, "real Core bridge");
    }

    private static void NativeClientExportsInspectBindingContract()
    {
        string nativeLibrary = File.ReadAllText(RepositoryPath(
            "apps/linux/AreaMatrix/Core/NativeCoreLibrary.cs"));
        string nativeClient = File.ReadAllText(RepositoryPath(
            "apps/linux/AreaMatrix/Core/AreaMatrixNativeCoreClient.BindingContract.cs"));
        string contract = File.ReadAllText(RepositoryPath(
            "apps/linux/AreaMatrix/Core/AreaMatrixNativeCoreClient.cs"));

        TestAssert.Contains(
            "uniffi_area_matrix_core_fn_func_inspect_binding_contract",
            nativeLibrary,
            "inspect_binding_contract native binding");
        TestAssert.Contains("InspectBindingContractAsync", nativeClient, "C4-01 native client method");
        TestAssert.Contains("InspectBindingContractChecksum = 34434", contract, "C4-01 checksum");
        TestAssert.NotContains(
            "Get" + "Platform" + "CapabilitiesAsync",
            nativeClient,
            "no same-page capability bridge in C4-01 client");
    }

    private static PlatformDifferencesBindingContractReport ContractReport(
        PlatformDifferencesBindingTarget target)
    {
        return new PlatformDifferencesBindingContractReport(
            target,
            1,
            "0.1.0",
            [
                new PlatformDifferencesBindingApiContract(
                    "inspect_binding_contract",
                    "C4-01",
                    PlatformDifferencesBindingSupportStatus.Supported,
                    null)
            ],
            [
                new PlatformDifferencesBindingTypeMapping(
                    "BindingContractReport",
                    "dictionary BindingContractReport",
                    $"{target} BindingContractReport",
                    PlatformDifferencesBindingSupportStatus.Supported,
                    null)
            ],
            []);
    }

    private static LinuxPlatformCapabilities CapabilityReport()
    {
        LinuxPlatformCapabilitySupport available = new(
            LinuxPlatformCapabilityStatus.Available,
            UiEnabled: true,
            RequiresPermission: false,
            null);
        LinuxPlatformCapabilitySupport limited = new(
            LinuxPlatformCapabilityStatus.Limited,
            UiEnabled: false,
            RequiresPermission: true,
            "Only for local folders.");
        return new LinuxPlatformCapabilities(
            LinuxPlatformId.Linux,
            "1.2.3",
            available,
            available,
            limited,
            limited,
            available);
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

internal sealed class FakePlatformDifferencesCoreBridge : IPlatformDifferencesCoreBridge
{
    private readonly PlatformDifferencesBindingContractReport? report;
    private readonly Exception? error;

    public FakePlatformDifferencesCoreBridge(PlatformDifferencesBindingContractReport report)
    {
        this.report = report;
    }

    public FakePlatformDifferencesCoreBridge(Exception error)
    {
        this.error = error;
    }

    public List<PlatformDifferencesBindingTarget> Targets { get; } = [];

    public List<long> BindingVersions { get; } = [];

    public List<LinuxPlatformId> Platforms { get; } = [];

    public List<string> AppVersions { get; } = [];

    public LinuxPlatformCapabilities? Capabilities { get; init; }

    public Exception? CapabilityError { get; init; }

    public Task<PlatformDifferencesBindingContractReport> InspectBindingContractAsync(
        PlatformDifferencesBindingTarget targetPlatform,
        long bindingVersion,
        CancellationToken cancellationToken = default)
    {
        cancellationToken.ThrowIfCancellationRequested();
        Targets.Add(targetPlatform);
        BindingVersions.Add(bindingVersion);
        if (error is not null)
        {
            throw error;
        }

        return Task.FromResult(report ?? throw new InvalidOperationException("missing report"));
    }

    public Task<LinuxPlatformCapabilities> GetPlatformCapabilitiesAsync(
        LinuxPlatformId platform,
        string appVersion,
        CancellationToken cancellationToken = default)
    {
        cancellationToken.ThrowIfCancellationRequested();
        Platforms.Add(platform);
        AppVersions.Add(appVersion);
        if (CapabilityError is not null)
        {
            throw CapabilityError;
        }

        return Task.FromResult(Capabilities ?? throw new InvalidOperationException("missing capabilities"));
    }
}

internal sealed class FakePlatformDifferencesViewFactory : ILinuxPlatformDifferencesViewFactory
{
    private readonly IPlatformDifferencesCoreBridge bridge;

    public FakePlatformDifferencesViewFactory(IPlatformDifferencesCoreBridge bridge)
    {
        this.bridge = bridge;
    }

    public PlatformDifferencesView Create(string? repositoryPath = null)
    {
        return new PlatformDifferencesView(new PlatformDifferencesViewModel(
            bridge,
            repositoryPath: repositoryPath));
    }
}

internal sealed class FakeDesktopMainQueryCoreBridge : IDesktopMainQueryCoreBridge
{
    public Task<IReadOnlyList<DesktopFileEntry>> ListFilesAsync(
        string repoPath,
        DesktopFileFilter filter,
        CancellationToken cancellationToken = default)
    {
        return Task.FromResult<IReadOnlyList<DesktopFileEntry>>([]);
    }

    public Task<DesktopFileEntry> GetFileAsync(
        string repoPath,
        long fileId,
        CancellationToken cancellationToken = default)
    {
        return Task.FromResult(new DesktopFileEntry(
            fileId,
            "docs/example.md",
            "example.md",
            "example.md",
            "docs",
            0,
            "",
            DesktopStorageMode.Copied,
            DesktopFileOrigin.Imported,
            null,
            DesktopFileAvailabilityStatus.Available,
            0,
            0));
    }

    public Task<IReadOnlyList<DesktopCategoryNode>> ListCategoriesAsync(
        string repoPath,
        string locale,
        CancellationToken cancellationToken = default)
    {
        return Task.FromResult<IReadOnlyList<DesktopCategoryNode>>([]);
    }

    public Task<DesktopSearchResultPage> SearchFilesAsync(
        string repoPath,
        string query,
        DesktopSearchFilter filter,
        DesktopSearchSort sort,
        DesktopSearchPagination pagination,
        CancellationToken cancellationToken = default)
    {
        return Task.FromResult(new DesktopSearchResultPage(
            query,
            0,
            [],
            [],
            DesktopSearchIndexStatus.Ready));
    }
}
