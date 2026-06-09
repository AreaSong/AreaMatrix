using AreaMatrix.Features.Help;
using AreaMatrixTests.ChooseRepository;

namespace AreaMatrixTests.Help;

public static class PlatformDifferencesTests
{
    public static async Task RunAllAsync()
    {
        await WindowsHelpPageChecksC401BindingContract();
        await ContractFailureShowsRecoveryWithoutStaticSuccess();
        PlatformDifferencesPageIsReachableFromWindowsMainWindow();
        NativeClientExportsInspectBindingContract();
    }

    private static async Task WindowsHelpPageChecksC401BindingContract()
    {
        FakePlatformDifferencesCoreBridge bridge = new(ContractReport(PlatformDifferencesBindingTarget.Kotlin));
        PlatformDifferencesViewModel model = new(bridge);

        await model.LoadAsync();

        TestAssert.Equal("Windows", model.HostPlatform, nameof(model.HostPlatform));
        TestAssert.Equal(PlatformDifferencesContractStatus.Loaded, model.Status, nameof(model.Status));
        TestAssert.Equal(PlatformDifferencesBindingTarget.Kotlin, model.Report?.TargetPlatform, "target");
        TestAssert.SequenceEqual(
            [PlatformDifferencesBindingTarget.Kotlin],
            bridge.Targets,
            "requested targets");
        TestAssert.SequenceEqual([1L], bridge.BindingVersions, "requested versions");
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
        TestAssert.Contains("Read-only binding contract check", page, "read-only safety copy");
    }

    private static void NativeClientExportsInspectBindingContract()
    {
        string nativeLibrary = File.ReadAllText(RepositoryPath(
            "apps/windows/AreaMatrix/Core/NativeCoreLibrary.cs"));
        string nativeClient = File.ReadAllText(RepositoryPath(
            "apps/windows/AreaMatrix/Core/AreaMatrixNativeCoreClient.BindingContract.cs"));
        string contract = File.ReadAllText(RepositoryPath(
            "apps/windows/AreaMatrix/Core/AreaMatrixNativeCoreClient.Contract.cs"));

        TestAssert.Contains(
            "uniffi_area_matrix_core_fn_func_inspect_binding_contract",
            nativeLibrary,
            "inspect_binding_contract native binding");
        TestAssert.Contains("InspectBindingContractAsync", nativeClient, "C4-01 native client method");
        TestAssert.Contains("InspectBindingContractChecksum = 34434", contract, "C4-01 checksum");
        TestAssert.DoesNotContain(
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
}
