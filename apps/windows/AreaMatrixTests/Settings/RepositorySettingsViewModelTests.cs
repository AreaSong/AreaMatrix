using AreaMatrix.Features.Help;
using AreaMatrix.Features.Onboarding;
using AreaMatrix.Features.Settings;
using AreaMatrixTests.ChooseRepository;

namespace AreaMatrixTests.Settings;

public static class RepositorySettingsViewModelTests
{
    public static async Task RunAllAsync()
    {
        await LoadsRepositoryConfigCapabilitiesAndCoreVersion();
        await SavesRepositoryConfigThroughUpdateConfig();
        await ExportsDiagnosticsFromLoadedSnapshot();
        await EmptyRepositoryShowsNoConnectedState();
        WindowsSettingsPageDeclaresC417AndC420Closure();
    }

    private static async Task LoadsRepositoryConfigCapabilitiesAndCoreVersion()
    {
        RecordingRepositorySettingsBridge bridge = new();
        RepositorySettingsViewModel model = new(bridge, @"C:\Repos\AreaMatrix");

        await model.LoadAsync();

        TestAssert.Equal(RepositorySettingsStatus.Loaded, model.Status, nameof(model.Status));
        TestAssert.SequenceEqual([@"C:\Repos\AreaMatrix"], bridge.LoadedConfigPaths, nameof(bridge.LoadedConfigPaths));
        TestAssert.SequenceEqual(["Windows:1"], bridge.CapabilityRequests, nameof(bridge.CapabilityRequests));
        TestAssert.Equal("AreaMatrix", model.Snapshot?.Name, "repository name");
        TestAssert.Equal("Local folder", model.Snapshot?.LocationType, "location type");
        TestAssert.Equal("test-core", model.Snapshot?.CoreVersion, "core version");
        TestAssert.Equal("Available", model.Snapshot?.Access, "access state");
        TestAssert.True(model.CanExportDiagnostics, nameof(model.CanExportDiagnostics));
    }

    private static async Task SavesRepositoryConfigThroughUpdateConfig()
    {
        RecordingRepositorySettingsBridge bridge = new();
        RepositorySettingsViewModel model = new(bridge, @"C:\Repos\AreaMatrix");

        await model.LoadAsync();
        await model.SaveFallbackToInboxAsync(false);

        TestAssert.Equal(1, bridge.UpdateRequests.Count, "update request count");
        TestAssert.Equal(@"C:\Repos\AreaMatrix", bridge.UpdateRequests[0].repoPath, "update repo path");
        TestAssert.False(bridge.UpdateRequests[0].config.FallbackToInbox, "fallback flag");
        TestAssert.SequenceEqual(
            [@"C:\Repos\AreaMatrix", @"C:\Repos\AreaMatrix"],
            bridge.LoadedConfigPaths,
            nameof(bridge.LoadedConfigPaths));
    }

    private static async Task ExportsDiagnosticsFromLoadedSnapshot()
    {
        RecordingRepositorySettingsBridge bridge = new();
        RecordingWindowsSettingsDiagnosticsExporter diagnostics = new(@"C:\Repos\AreaMatrix\.areamatrix\generated\diagnostics\repository-settings.txt");
        RepositorySettingsViewModel model = new(
            bridge,
            @"C:\Repos\AreaMatrix",
            diagnosticsExporter: diagnostics);

        await model.LoadAsync();
        bool exported = await model.ExportDiagnosticsAsync();

        TestAssert.True(exported, nameof(exported));
        TestAssert.Equal(
            @"C:\Repos\AreaMatrix\.areamatrix\generated\diagnostics\repository-settings.txt",
            model.LastDiagnosticsExportPath,
            nameof(model.LastDiagnosticsExportPath));
        TestAssert.SequenceEqual([@"C:\Repos\AreaMatrix"], diagnostics.ExportedLocations, "diagnostics locations");
        TestAssert.True(model.CanExportDiagnostics, nameof(model.CanExportDiagnostics));
    }

    private static async Task EmptyRepositoryShowsNoConnectedState()
    {
        RecordingRepositorySettingsBridge bridge = new();
        RepositorySettingsViewModel model = new(bridge);

        await model.LoadAsync();

        TestAssert.Equal(RepositorySettingsStatus.Empty, model.Status, nameof(model.Status));
        TestAssert.False(model.CanExportDiagnostics, nameof(model.CanExportDiagnostics));
        TestAssert.Empty(bridge.LoadedConfigPaths, nameof(bridge.LoadedConfigPaths));
    }

    private static void WindowsSettingsPageDeclaresC417AndC420Closure()
    {
        string view = File.ReadAllText(RepositoryPath(
            "apps/windows/AreaMatrix/Features/Settings/RepositorySettingsView.xaml"));
        string codeBehind = File.ReadAllText(RepositoryPath(
            "apps/windows/AreaMatrix/Features/Settings/RepositorySettingsView.xaml.cs"));
        string viewModel = File.ReadAllText(RepositoryPath(
            "apps/windows/AreaMatrix/Features/Settings/RepositorySettingsViewModel.cs"));
        string mainWindow = File.ReadAllText(RepositoryPath("apps/windows/AreaMatrix/MainWindow.xaml"));
        string mainCode = File.ReadAllText(RepositoryPath("apps/windows/AreaMatrix/MainWindow.xaml.cs"));
        string lazyClient = File.ReadAllText(RepositoryPath(
            "apps/windows/AreaMatrix/Core/LazyAreaMatrixWindowsCoreClient.cs"));

        TestAssert.Contains("FallbackToInboxCheckBox", view, "C4-20 visible save control");
        TestAssert.Contains("FallbackToInboxCheckBox_Click", codeBehind, "C4-20 save handler");
        TestAssert.Contains("SaveFallbackToInboxAsync", codeBehind, "C4-20 save call");
        TestAssert.Contains("coreVersionLoader(cancellationToken)", viewModel, "real Core version loader");
        TestAssert.Contains("Core version: {snapshot.CoreVersion}", codeBehind, "Core version row");
        TestAssert.Contains("settings:RepositorySettingsView", mainWindow, "S4-X-08 page host");
        TestAssert.Contains("OpenRepositorySettingsRequested", mainCode, "S4-X-02 to S4-X-08 route");
        TestAssert.Contains("coreClient.GetVersionAsync", mainCode, "production get_version wiring");
        TestAssert.Contains("RepositorySettingsPage.ExportDiagnosticsRequested +=", mainCode, "diagnostics event subscription");
        TestAssert.Contains("RepositorySettingsPage.ExportDiagnosticsAsync", mainCode, "real diagnostics handler");
        TestAssert.Contains("ExportDiagnosticsAsync", codeBehind, "diagnostics page action");
        TestAssert.Contains("GetVersionAsync", lazyClient, "lazy core version wrapper");
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

internal sealed class RecordingWindowsSettingsDiagnosticsExporter : IWindowsRepositorySettingsDiagnosticsExporter
{
    private readonly string outputPath;

    public RecordingWindowsSettingsDiagnosticsExporter(string outputPath)
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

internal sealed class RecordingRepositorySettingsBridge : IWindowsRepositorySettingsBridge
{
    public RecordingRepositorySettingsBridge() {}

    public List<string> LoadedConfigPaths { get; } = [];

    public List<string> CapabilityRequests { get; } = [];

    public List<(string repoPath, WindowsRepositoryConfig config)> UpdateRequests { get; } = [];

    public Task<string> GetCoreVersionAsync(CancellationToken cancellationToken = default)
    {
        cancellationToken.ThrowIfCancellationRequested();
        return Task.FromResult("test-core");
    }

    public Task<WindowsRepositoryConfig> LoadConfigAsync(
        string repoPath,
        CancellationToken cancellationToken = default)
    {
        cancellationToken.ThrowIfCancellationRequested();
        LoadedConfigPaths.Add(repoPath);
        return Task.FromResult(new WindowsRepositoryConfig(
            repoPath,
            "Copied",
            "en-US",
            FallbackToInbox: true));
    }

    public Task UpdateConfigAsync(
        string repoPath,
        WindowsRepositoryConfig newConfig,
        CancellationToken cancellationToken = default)
    {
        cancellationToken.ThrowIfCancellationRequested();
        UpdateRequests.Add((repoPath, newConfig));
        return Task.CompletedTask;
    }

    public Task<PlatformDifferencesCapabilities> GetPlatformCapabilitiesAsync(
        PlatformDifferencesPlatformId platform,
        string appVersion,
        CancellationToken cancellationToken = default)
    {
        cancellationToken.ThrowIfCancellationRequested();
        CapabilityRequests.Add($"{platform}:{appVersion}");
        return Task.FromResult(RepositorySettingsCapabilitiesFixture(platform, appVersion));
    }

    private static PlatformDifferencesCapabilities RepositorySettingsCapabilitiesFixture(
        PlatformDifferencesPlatformId platform,
        string appVersion)
    {
        PlatformDifferencesCapabilitySupport available = new(
            PlatformDifferencesCapabilityStatus.Available,
            UiEnabled: true,
            RequiresPermission: false,
            Reason: null);
        PlatformDifferencesCapabilitySupport unavailable = new(
            PlatformDifferencesCapabilityStatus.NotAvailable,
            UiEnabled: false,
            RequiresPermission: false,
            Reason: null);
        return new PlatformDifferencesCapabilities(
            platform,
            appVersion,
            available,
            available,
            unavailable,
            unavailable,
            available);
    }
}
