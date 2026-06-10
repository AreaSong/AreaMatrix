using AreaMatrix.Features.Help;
using AreaMatrixTests.ChooseRepository;

namespace AreaMatrixTests.Help;

public static class PlatformDifferencesTests
{
    public static async Task RunAllAsync()
    {
        await WindowsHelpPageChecksC401BindingContract();
        await WindowsHelpPageLoadsC417PlatformCapabilities();
        WindowsCapabilityRowsCoverS4X02PageSpecMatrix();
        await CapabilityFailureShowsUnknownRowsWithoutStaticAvailability();
        await ContractFailureShowsRecoveryWithoutStaticSuccess();
        WindowsRepositorySettingsActionIsAvailable();
        PlatformDifferencesPageIsReachableFromWindowsMainWindow();
        NativeClientExportsPlatformDifferenceCoreCalls();
    }

    private static async Task WindowsHelpPageChecksC401BindingContract()
    {
        FakePlatformDifferencesCoreBridge bridge = new(ContractReport(PlatformDifferencesBindingTarget.Kotlin));
        PlatformDifferencesViewModel model = new(bridge);

        await model.LoadAsync();

        TestAssert.Equal(PlatformDifferencesPlatformId.Windows, model.HostPlatform, nameof(model.HostPlatform));
        TestAssert.Equal(PlatformDifferencesContractStatus.Loaded, model.Status, nameof(model.Status));
        TestAssert.Equal(PlatformDifferencesBindingTarget.Kotlin, model.Report?.TargetPlatform, "target");
        TestAssert.SequenceEqual(
            [PlatformDifferencesBindingTarget.Kotlin],
            bridge.Targets,
            "requested targets");
        TestAssert.SequenceEqual([1L], bridge.BindingVersions, "requested versions");
    }

    private static async Task WindowsHelpPageLoadsC417PlatformCapabilities()
    {
        FakePlatformDifferencesCoreBridge bridge = new(ContractReport(PlatformDifferencesBindingTarget.Kotlin))
        {
            Capabilities = CapabilityReport()
        };
        PlatformDifferencesViewModel model = new(bridge, appVersion: "1.2.3");

        await model.LoadAsync();

        TestAssert.Equal(PlatformDifferencesPlatformId.Windows, model.Capabilities?.Platform, "platform");
        TestAssert.Equal(PlatformDifferencesCapabilityStatus.Available, model.Capabilities?.Watcher.Status, "watcher");
        TestAssert.SequenceEqual([PlatformDifferencesPlatformId.Windows], bridge.Platforms, "requested platforms");
        TestAssert.SequenceEqual(["1.2.3"], bridge.AppVersions, "requested app versions");
        TestAssert.True(
            model.CapabilityRows.Any(row => row.Contains("File watcher - Available", StringComparison.Ordinal)),
            "capability row");
    }

    private static void WindowsCapabilityRowsCoverS4X02PageSpecMatrix()
    {
        IReadOnlyList<string> rows = CapabilityReport().DisplayRows();

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
        FakePlatformDifferencesCoreBridge bridge = new(ContractReport(PlatformDifferencesBindingTarget.Kotlin))
        {
            CapabilityError = new InvalidOperationException("platform unavailable")
        };
        PlatformDifferencesViewModel model = new(bridge);

        await model.LoadCapabilitiesAsync();

        TestAssert.Equal("Capability snapshot unavailable", model.CapabilityErrorMessage, "capability error");
        TestAssert.Equal(PlatformDifferencesCapabilityStatus.Unknown, model.Capabilities?.Watcher.Status, "watcher");
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

    private static void WindowsRepositorySettingsActionIsAvailable()
    {
        FakePlatformDifferencesCoreBridge bridge = new(ContractReport(PlatformDifferencesBindingTarget.Kotlin));
        PlatformDifferencesViewModel model = new(bridge);

        TestAssert.True(model.CanOpenRepositorySettings, "S4-X-08 repository settings action");
        TestAssert.Equal(string.Empty, model.RepositorySettingsUnavailableText, "repository settings unavailable text");
    }

    private static void PlatformDifferencesPageIsReachableFromWindowsMainWindow()
    {
        string mainWindow = File.ReadAllText(RepositoryPath("apps/windows/AreaMatrix/MainWindow.xaml"));
        string mainCode = File.ReadAllText(RepositoryPath("apps/windows/AreaMatrix/MainWindow.xaml.cs"));
        string mainView = File.ReadAllText(RepositoryPath(
            "apps/windows/AreaMatrix/Features/Library/WindowsMainWindow.xaml"));
        string mainViewCode = File.ReadAllText(RepositoryPath(
            "apps/windows/AreaMatrix/Features/Library/WindowsMainWindow.xaml.cs"));
        string page = File.ReadAllText(RepositoryPath(
            "apps/windows/AreaMatrix/Features/Help/PlatformDifferencesView.xaml"));

        TestAssert.Contains("help:PlatformDifferencesView", mainWindow, "S4-X-02 page host");
        TestAssert.Contains("OpenPlatformDifferencesRequested", mainCode, "main window route");
        TestAssert.Contains("new PlatformDifferencesCoreBridge(coreClient)", mainCode, "real Core bridge");
        TestAssert.Contains("Label=\"Platform capabilities\"", mainView, "visible help action");
        TestAssert.Contains("PlatformDifferencesButton_Click", mainViewCode, "help action handler");
        TestAssert.Contains("Check contract", page, "contract trigger");
        TestAssert.Contains("Check capabilities", page, "capability trigger");
        TestAssert.Contains("Open repository settings", page, "repository settings action");
        TestAssert.Contains("Export diagnostics", page, "diagnostics action");
        TestAssert.Contains("Read-only capability and binding contract checks", page, "read-only safety copy");
    }

    private static void NativeClientExportsPlatformDifferenceCoreCalls()
    {
        string nativeLibrary = File.ReadAllText(RepositoryPath(
            "apps/windows/AreaMatrix/Core/NativeCoreLibrary.cs"));
        string nativeClient = File.ReadAllText(RepositoryPath(
            "apps/windows/AreaMatrix/Core/AreaMatrixNativeCoreClient.BindingContract.cs"));
        string capabilityClient = File.ReadAllText(RepositoryPath(
            "apps/windows/AreaMatrix/Core/AreaMatrixNativeCoreClient.PlatformCapabilities.cs"));
        string contract = File.ReadAllText(RepositoryPath(
            "apps/windows/AreaMatrix/Core/AreaMatrixNativeCoreClient.Contract.cs"));

        TestAssert.Contains(
            "uniffi_area_matrix_core_fn_func_inspect_binding_contract",
            nativeLibrary,
            "inspect_binding_contract native binding");
        TestAssert.Contains("InspectBindingContractAsync", nativeClient, "C4-01 native client method");
        TestAssert.Contains("InspectBindingContractChecksum = 34434", contract, "C4-01 checksum");
        TestAssert.Contains(
            "uniffi_area_matrix_core_fn_func_get_platform_capabilities",
            nativeLibrary,
            "get_platform_capabilities native binding");
        TestAssert.Contains("GetPlatformCapabilitiesAsync", capabilityClient, "C4-17 native client method");
        TestAssert.Contains("GetPlatformCapabilitiesChecksum = 42907", contract, "C4-17 checksum");
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

    private static PlatformDifferencesCapabilities CapabilityReport()
    {
        PlatformDifferencesCapabilitySupport available = new(
            PlatformDifferencesCapabilityStatus.Available,
            true,
            false,
            null);
        PlatformDifferencesCapabilitySupport limited = new(
            PlatformDifferencesCapabilityStatus.Limited,
            false,
            true,
            "Only for local folders.");
        return new PlatformDifferencesCapabilities(
            PlatformDifferencesPlatformId.Windows,
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

    public List<PlatformDifferencesPlatformId> Platforms { get; } = [];

    public List<string> AppVersions { get; } = [];

    public PlatformDifferencesCapabilities? Capabilities { get; init; }

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

    public Task<PlatformDifferencesCapabilities> GetPlatformCapabilitiesAsync(
        PlatformDifferencesPlatformId platform,
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
