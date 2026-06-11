using AreaMatrix.Linux.Features.Onboarding;
using AreaMatrix.Linux.Features.Settings;
using AreaMatrix.Linux.Tests.ChooseRepository;

namespace AreaMatrix.Linux.Tests.Settings;

public static class RepositorySettingsViewModelTests
{
    public static async Task RunAllAsync()
    {
        await LoadsRepositoryConfigAndCapabilities();
        await AccessStateFollowsSecurityBookmarkCapabilities();
        await PageSaveActionTriggersUpdateConfig();
        await SavesRepositoryConfigThroughUpdateConfig();
        await PageExportDiagnosticsUsesRepositorySettingsSnapshot();
        await EmptyRepositoryShowsNoConnectedState();
        LinuxSettingsPageDeclaresC417AndC420Closure();
    }

    private static async Task LoadsRepositoryConfigAndCapabilities()
    {
        FakeLinuxRepositoryCoreBridge bridge = new(
            LinuxRepositoryValidationSamples.Initialized("/home/as/AreaMatrixRepo"),
            LinuxPlatformCapabilitySamples.LinuxDefault());
        RepositorySettingsViewModel model = new(
            bridge,
            bridge,
            "/home/as/AreaMatrixRepo");

        await model.LoadAsync();

        TestAssert.Equal(RepositorySettingsStatus.Loaded, model.Status, nameof(model.Status));
        TestAssert.SequenceEqual(["/home/as/AreaMatrixRepo"], bridge.LoadedConfigPaths, nameof(bridge.LoadedConfigPaths));
        TestAssert.Equal("AreaMatrixRepo", model.Snapshot?.Name, "repository name");
        TestAssert.Equal("Local folder", model.Snapshot?.LocationType, "location type");
        TestAssert.Equal("test-core", model.Snapshot?.CoreVersion, "core version");
        TestAssert.Equal(1, bridge.CoreVersionRequestCount, "core version request count");
        TestAssert.Equal(
            "Permission denied: Linux uses POSIX permissions instead of security-scoped bookmarks",
            model.Snapshot?.Access,
            "access state");
        TestAssert.False(model.CanExportDiagnostics, nameof(model.CanExportDiagnostics));
    }

    private static async Task AccessStateFollowsSecurityBookmarkCapabilities()
    {
        await AssertAccessState(
            new LinuxPlatformCapabilitySupport(
                LinuxPlatformCapabilityStatus.Available,
                UiEnabled: true,
                RequiresPermission: false,
                Reason: null),
            "Available",
            canExportDiagnostics: true);
        await AssertAccessState(
            new LinuxPlatformCapabilitySupport(
                LinuxPlatformCapabilityStatus.Limited,
                UiEnabled: false,
                RequiresPermission: true,
                Reason: "Stored repository permission expired"),
            "Expired: Stored repository permission expired",
            canExportDiagnostics: false);
        await AssertAccessState(
            new LinuxPlatformCapabilitySupport(
                LinuxPlatformCapabilityStatus.NotAvailable,
                UiEnabled: false,
                RequiresPermission: false,
                Reason: "POSIX permission check failed"),
            "Permission denied: POSIX permission check failed",
            canExportDiagnostics: false);
        await AssertAccessState(
            new LinuxPlatformCapabilitySupport(
                LinuxPlatformCapabilityStatus.Unknown,
                UiEnabled: false,
                RequiresPermission: false,
                Reason: null),
            "Unknown",
            canExportDiagnostics: false);
    }

    private static async Task PageSaveActionTriggersUpdateConfig()
    {
        FakeLinuxRepositoryCoreBridge bridge = new(
            LinuxRepositoryValidationSamples.Initialized("/home/as/AreaMatrixRepo"),
            LinuxPlatformCapabilitySamples.LinuxDefault());
        RepositorySettingsView view = new(new RepositorySettingsViewModel(
            bridge,
            bridge,
            "/home/as/AreaMatrixRepo"));

        await view.OpenAsync();
        await view.SaveFallbackToInboxAsync(false);

        TestAssert.Equal(1, bridge.UpdatedConfigs.Count, "page update request count");
        TestAssert.False(bridge.UpdatedConfigs[0].Config.FallbackToInbox, "page fallback flag");
    }

    private static async Task SavesRepositoryConfigThroughUpdateConfig()
    {
        FakeLinuxRepositoryCoreBridge bridge = new(
            LinuxRepositoryValidationSamples.Initialized("/home/as/AreaMatrixRepo"),
            LinuxPlatformCapabilitySamples.LinuxDefault());
        RepositorySettingsViewModel model = new(
            bridge,
            bridge,
            "/home/as/AreaMatrixRepo");

        await model.LoadAsync();
        await model.SaveFallbackToInboxAsync(false);

        TestAssert.Equal(1, bridge.UpdatedConfigs.Count, "updated config count");
        TestAssert.Equal("/home/as/AreaMatrixRepo", bridge.UpdatedConfigs[0].RepoPath, "updated repo path");
        TestAssert.False(bridge.UpdatedConfigs[0].Config.FallbackToInbox, "fallback flag");
        TestAssert.SequenceEqual(
            ["/home/as/AreaMatrixRepo", "/home/as/AreaMatrixRepo"],
            bridge.LoadedConfigPaths,
            nameof(bridge.LoadedConfigPaths));
    }

    private static async Task PageExportDiagnosticsUsesRepositorySettingsSnapshot()
    {
        FakeLinuxRepositoryCoreBridge bridge = new(
            LinuxRepositoryValidationSamples.Initialized("/home/as/AreaMatrixRepo"),
            LinuxDiagnosticsCapabilities());
        RecordingLinuxSettingsDiagnosticsExporter diagnostics = new(
            "/home/as/AreaMatrixRepo/.areamatrix/generated/diagnostics/repository-settings.txt");
        RepositorySettingsView view = new(new RepositorySettingsViewModel(
            bridge,
            bridge,
            "/home/as/AreaMatrixRepo",
            diagnosticsExporter: diagnostics));

        await view.OpenAsync();
        bool exported = await view.ExportDiagnosticsAsync();

        TestAssert.True(exported, nameof(exported));
        TestAssert.SequenceEqual(["/home/as/AreaMatrixRepo"], diagnostics.ExportedLocations, "diagnostics locations");
        TestAssert.Equal(
            "/home/as/AreaMatrixRepo/.areamatrix/generated/diagnostics/repository-settings.txt",
            view.ViewModel.LastDiagnosticsExportPath,
            nameof(view.ViewModel.LastDiagnosticsExportPath));
        TestAssert.True(view.ViewModel.CanExportDiagnostics, nameof(view.ViewModel.CanExportDiagnostics));
    }

    private static async Task EmptyRepositoryShowsNoConnectedState()
    {
        FakeLinuxRepositoryCoreBridge bridge = new(
            LinuxRepositoryValidationSamples.Initialized("/home/as/AreaMatrixRepo"),
            LinuxPlatformCapabilitySamples.LinuxDefault());
        RepositorySettingsViewModel model = new(bridge, bridge);

        await model.LoadAsync();

        TestAssert.Equal(RepositorySettingsStatus.Empty, model.Status, nameof(model.Status));
        TestAssert.False(model.CanExportDiagnostics, nameof(model.CanExportDiagnostics));
        TestAssert.Empty(bridge.LoadedConfigPaths, nameof(bridge.LoadedConfigPaths));
    }

    private static void LinuxSettingsPageDeclaresC417AndC420Closure()
    {
        string ui = File.ReadAllText(RepositoryPath(
            "apps/linux/AreaMatrix/Features/Settings/RepositorySettingsView.ui"));
        string view = File.ReadAllText(RepositoryPath(
            "apps/linux/AreaMatrix/Features/Settings/RepositorySettingsView.cs"));
        string viewModel = File.ReadAllText(RepositoryPath(
            "apps/linux/AreaMatrix/Features/Settings/RepositorySettingsViewModel.cs"));
        string bridge = File.ReadAllText(RepositoryPath(
            "apps/linux/AreaMatrix/Features/Onboarding/LinuxRepositoryCoreBridge.cs"));
        string nativeClient = File.ReadAllText(RepositoryPath(
            "apps/linux/AreaMatrix/Core/AreaMatrixNativeCoreClient.cs"));
        string nativeLibrary = File.ReadAllText(RepositoryPath(
            "apps/linux/AreaMatrix/Core/NativeCoreLibrary.cs"));
        string shell = File.ReadAllText(RepositoryPath(
            "apps/linux/AreaMatrix/Features/Library/LinuxDesktopShell.cs"));
        string factories = File.ReadAllText(RepositoryPath(
            "apps/linux/AreaMatrix/Features/Library/LinuxDesktopShellFactories.cs"));

        TestAssert.Contains("save_fallback_to_inbox", ui, "C4-20 save action");
        TestAssert.Contains("RepositorySettingsView.SaveFallbackToInboxAsync", ui, "visible save trigger");
        TestAssert.Contains("RepositorySettingsView.ExportDiagnosticsAsync", ui, "diagnostics export trigger");
        TestAssert.Contains("SaveFallbackToInboxAsync", view, "page save method");
        TestAssert.Contains("ViewModel.ExportDiagnosticsAsync", view, "page diagnostics method");
        TestAssert.Contains("UpdateConfigAsync", viewModel, "C4-20 update_config call");
        TestAssert.Contains("LinuxRepositorySettingsDiagnosticsExporter", viewModel, "redacted diagnostics exporter");
        TestAssert.Contains("GetCoreVersionAsync", bridge, "Core version bridge");
        TestAssert.Contains("GetVersionAsync", nativeClient, "get_version native client");
        TestAssert.Contains(
            "uniffi_area_matrix_core_fn_func_get_version",
            nativeLibrary,
            "get_version native export");
        TestAssert.Contains("ILinuxRepositorySettingsViewFactory", shell, "S4-X-08 shell factory contract");
        TestAssert.Contains("OpenRepositorySettingsAsync", shell, "S4-X-08 shell route");
        TestAssert.Contains("PlatformCapabilitiesRequested", shell, "settings to platform capabilities route");
        TestAssert.Contains("new LinuxRepositorySettingsViewFactory(repositoryBridge, repositoryBridge)", shell, "real settings factory");
        TestAssert.Contains("LinuxRepositorySettingsViewFactory", factories, "settings factory implementation");
    }

    private static LinuxPlatformCapabilities LinuxDiagnosticsCapabilities()
    {
        LinuxPlatformCapabilities defaults = LinuxPlatformCapabilitySamples.LinuxDefault();
        return defaults with
        {
            SecurityBookmark = new LinuxPlatformCapabilitySupport(
                LinuxPlatformCapabilityStatus.Available,
                UiEnabled: true,
                RequiresPermission: false,
                Reason: null)
        };
    }

    private static async Task AssertAccessState(
        LinuxPlatformCapabilitySupport securityBookmark,
        string expectedAccess,
        bool canExportDiagnostics)
    {
        FakeLinuxRepositoryCoreBridge bridge = new(
            LinuxRepositoryValidationSamples.Initialized("/home/as/AreaMatrixRepo"),
            LinuxSecurityBookmarkCapabilities(securityBookmark));
        RepositorySettingsViewModel model = new(
            bridge,
            bridge,
            "/home/as/AreaMatrixRepo");

        await model.LoadAsync();

        TestAssert.Equal(expectedAccess, model.Snapshot?.Access, $"access state {securityBookmark.Status}");
        TestAssert.Equal(canExportDiagnostics, model.CanExportDiagnostics, $"diagnostics {securityBookmark.Status}");
    }

    private static LinuxPlatformCapabilities LinuxSecurityBookmarkCapabilities(
        LinuxPlatformCapabilitySupport securityBookmark)
    {
        LinuxPlatformCapabilities defaults = LinuxPlatformCapabilitySamples.LinuxDefault();
        return defaults with { SecurityBookmark = securityBookmark };
    }

    private static string RepositoryPath(string relativePath)
    {
        string? current = Directory.GetCurrentDirectory();
        while (!string.IsNullOrEmpty(current))
        {
            string candidate = Path.Combine(current, relativePath);
            if (File.Exists(candidate))
            {
                return candidate;
            }

            current = Directory.GetParent(current)?.FullName;
        }

        throw new FileNotFoundException($"Could not find `{relativePath}` from the current directory.");
    }
}

internal sealed class RecordingLinuxSettingsDiagnosticsExporter : ILinuxRepositorySettingsDiagnosticsExporter
{
    private readonly string outputPath;

    public RecordingLinuxSettingsDiagnosticsExporter(string outputPath)
    {
        this.outputPath = outputPath;
    }

    public List<string> ExportedLocations { get; } = [];

    public Task<string> ExportAsync(
        RepositorySettingsSnapshot snapshot,
        CancellationToken cancellationToken = default)
    {
        cancellationToken.ThrowIfCancellationRequested();
        ExportedLocations.Add(snapshot.Location);
        return Task.FromResult(outputPath);
    }
}
