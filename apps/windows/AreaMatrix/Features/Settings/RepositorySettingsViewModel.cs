using System.ComponentModel;
using System.IO;
using System.Runtime.CompilerServices;
using AreaMatrix.Features.Help;
using AreaMatrix.Features.Onboarding;

namespace AreaMatrix.Features.Settings;

public enum RepositorySettingsStatus
{
    Loading,
    Empty,
    Loaded,
    Failed
}

public sealed record RepositorySettingsFailure(string Message, string Recovery);

public sealed record RepositorySettingsSnapshot(
    string Name,
    string Location,
    string LocationType,
    string LastOpened,
    string CoreVersion,
    string Access,
    string Watcher,
    string Cloud,
    WindowsRepositoryConfig Config,
    PlatformDifferencesCapabilities Capabilities);

public interface IWindowsRepositorySettingsDiagnosticsExporter
{
    Task<string> ExportAsync(
        RepositorySettingsSnapshot snapshot,
        CancellationToken cancellationToken = default);
}

public sealed class WindowsRepositorySettingsDiagnosticsExporter : IWindowsRepositorySettingsDiagnosticsExporter
{
    public async Task<string> ExportAsync(
        RepositorySettingsSnapshot snapshot,
        CancellationToken cancellationToken = default)
    {
        cancellationToken.ThrowIfCancellationRequested();
        if (string.IsNullOrWhiteSpace(snapshot.Location) || !Directory.Exists(snapshot.Location))
        {
            throw new WindowsRepositoryCoreException(
                WindowsRepositoryErrorKind.FileNotFound,
                "Repository folder was not found.",
                snapshot.Location);
        }

        string diagnosticsDirectory = Path.Combine(
            snapshot.Location,
            ".areamatrix",
            "generated",
            "diagnostics");
        Directory.CreateDirectory(diagnosticsDirectory);
        string outputPath = Path.Combine(
            diagnosticsDirectory,
            $"repository-settings-{DateTimeOffset.UtcNow.ToUnixTimeMilliseconds()}.txt");
        await File.WriteAllLinesAsync(
            outputPath,
            DiagnosticLines(snapshot),
            cancellationToken).ConfigureAwait(false);
        return outputPath;
    }

    private static IEnumerable<string> DiagnosticLines(RepositorySettingsSnapshot snapshot)
    {
        yield return "AreaMatrix repository settings diagnostics";
        yield return "No user file contents are included.";
        yield return $"Name: {snapshot.Name}";
        yield return $"Location: {snapshot.Location}";
        yield return $"Type: {snapshot.LocationType}";
        yield return $"Last opened: {snapshot.LastOpened}";
        yield return $"Core version: {snapshot.CoreVersion}";
        yield return $"Access: {snapshot.Access}";
        yield return $"Watcher: {snapshot.Watcher}";
        yield return $"Cloud: {snapshot.Cloud}";
        yield return $"Locale: {snapshot.Config.Locale}";
        yield return $"Fallback to Inbox: {snapshot.Config.FallbackToInbox}";
        yield return $"Platform: {snapshot.Capabilities.Platform}";
        yield return $"App version: {snapshot.Capabilities.AppVersion}";
    }
}

public interface IWindowsRepositorySettingsBridge
{
    Task<string> GetCoreVersionAsync(CancellationToken cancellationToken = default);

    Task<WindowsRepositoryConfig> LoadConfigAsync(
        string repoPath,
        CancellationToken cancellationToken = default);

    Task UpdateConfigAsync(
        string repoPath,
        WindowsRepositoryConfig newConfig,
        CancellationToken cancellationToken = default);

    Task<PlatformDifferencesCapabilities> GetPlatformCapabilitiesAsync(
        PlatformDifferencesPlatformId platform,
        string appVersion,
        CancellationToken cancellationToken = default);
}

public sealed class WindowsRepositorySettingsBridge : IWindowsRepositorySettingsBridge
{
    private readonly IWindowsRepositoryCoreBridge repositoryBridge;
    private readonly IPlatformDifferencesCoreBridge capabilityBridge;
    private readonly Func<CancellationToken, Task<string>> coreVersionLoader;

    public WindowsRepositorySettingsBridge(
        IWindowsRepositoryCoreBridge repositoryBridge,
        IPlatformDifferencesCoreBridge capabilityBridge,
        Func<CancellationToken, Task<string>> coreVersionLoader)
    {
        this.repositoryBridge = repositoryBridge;
        this.capabilityBridge = capabilityBridge;
        this.coreVersionLoader = coreVersionLoader;
    }

    public Task<string> GetCoreVersionAsync(CancellationToken cancellationToken = default)
    {
        cancellationToken.ThrowIfCancellationRequested();
        return coreVersionLoader(cancellationToken);
    }

    public Task<WindowsRepositoryConfig> LoadConfigAsync(
        string repoPath,
        CancellationToken cancellationToken = default)
    {
        return repositoryBridge.LoadConfigAsync(repoPath, cancellationToken);
    }

    public Task UpdateConfigAsync(
        string repoPath,
        WindowsRepositoryConfig newConfig,
        CancellationToken cancellationToken = default)
    {
        return repositoryBridge.UpdateConfigAsync(repoPath, newConfig, cancellationToken);
    }

    public Task<PlatformDifferencesCapabilities> GetPlatformCapabilitiesAsync(
        PlatformDifferencesPlatformId platform,
        string appVersion,
        CancellationToken cancellationToken = default)
    {
        return capabilityBridge.GetPlatformCapabilitiesAsync(platform, appVersion, cancellationToken);
    }
}

public sealed class RepositorySettingsViewModel : INotifyPropertyChanged
{
    private readonly IWindowsRepositorySettingsBridge bridge;
    private readonly IWindowsRepositorySettingsDiagnosticsExporter diagnosticsExporter;
    private RepositorySettingsSnapshot? snapshot;
    private RepositorySettingsFailure? failure;
    private RepositorySettingsFailure? saveFailure;
    private RepositorySettingsFailure? diagnosticsFailure;
    private string? lastDiagnosticsExportPath;
    private bool isSaving;
    private bool isExportingDiagnostics;

    public RepositorySettingsViewModel(
        IWindowsRepositorySettingsBridge bridge,
        string? repositoryPath = null,
        string appVersion = "1",
        IWindowsRepositorySettingsDiagnosticsExporter? diagnosticsExporter = null)
    {
        this.bridge = bridge;
        this.diagnosticsExporter = diagnosticsExporter ?? new WindowsRepositorySettingsDiagnosticsExporter();
        RepositoryPath = repositoryPath;
        AppVersion = appVersion;
    }

    public event PropertyChangedEventHandler? PropertyChanged;

    public string? RepositoryPath { get; }

    public string AppVersion { get; }

    public RepositorySettingsStatus Status { get; private set; } = RepositorySettingsStatus.Loading;

    public RepositorySettingsSnapshot? Snapshot
    {
        get => snapshot;
        private set
        {
            snapshot = value;
            OnPropertyChanged();
        }
    }

    public RepositorySettingsFailure? Failure
    {
        get => failure;
        private set
        {
            failure = value;
            OnPropertyChanged();
        }
    }

    public RepositorySettingsFailure? SaveFailure
    {
        get => saveFailure;
        private set
        {
            saveFailure = value;
            OnPropertyChanged();
        }
    }

    public RepositorySettingsFailure? DiagnosticsFailure
    {
        get => diagnosticsFailure;
        private set
        {
            diagnosticsFailure = value;
            OnPropertyChanged();
        }
    }

    public string? LastDiagnosticsExportPath
    {
        get => lastDiagnosticsExportPath;
        private set
        {
            lastDiagnosticsExportPath = value;
            OnPropertyChanged();
        }
    }

    public bool IsSaving
    {
        get => isSaving;
        private set
        {
            isSaving = value;
            OnPropertyChanged();
        }
    }

    public bool IsExportingDiagnostics
    {
        get => isExportingDiagnostics;
        private set
        {
            isExportingDiagnostics = value;
            OnPropertyChanged();
            OnPropertyChanged(nameof(CanExportDiagnostics));
        }
    }

    public bool HasConnectedRepository => !string.IsNullOrWhiteSpace(RepositoryPath);

    public bool CanExportDiagnostics => Snapshot?.Capabilities.SecurityBookmark.UiEnabled == true
        && !IsExportingDiagnostics;

    public async Task LoadAsync(CancellationToken cancellationToken = default)
    {
        if (!HasConnectedRepository)
        {
            Snapshot = null;
            Failure = null;
            DiagnosticsFailure = null;
            LastDiagnosticsExportPath = null;
            Status = RepositorySettingsStatus.Empty;
            OnPropertyChanged(nameof(Status));
            OnPropertyChanged(nameof(CanExportDiagnostics));
            return;
        }

        Status = RepositorySettingsStatus.Loading;
        Failure = null;
        SaveFailure = null;
        DiagnosticsFailure = null;
        OnPropertyChanged(nameof(Status));

        try
        {
            Task<WindowsRepositoryConfig> configTask = bridge.LoadConfigAsync(RepositoryPath!, cancellationToken);
            Task<PlatformDifferencesCapabilities> capabilitiesTask = bridge.GetPlatformCapabilitiesAsync(
                PlatformDifferencesPlatformId.Windows,
                AppVersion,
                cancellationToken);
            Task<string> versionTask = bridge.GetCoreVersionAsync(cancellationToken);
            await Task.WhenAll(configTask, capabilitiesTask, versionTask).ConfigureAwait(false);

            Snapshot = BuildSnapshot(
                RepositoryPath!,
                await configTask.ConfigureAwait(false),
                await capabilitiesTask.ConfigureAwait(false),
                await versionTask.ConfigureAwait(false));
            Status = RepositorySettingsStatus.Loaded;
        }
        catch (Exception error)
        {
            Snapshot = null;
            Failure = FailureFor(error);
            Status = RepositorySettingsStatus.Failed;
        }
        finally
        {
            OnPropertyChanged(nameof(Status));
            OnPropertyChanged(nameof(CanExportDiagnostics));
        }
    }

    public async Task SaveFallbackToInboxAsync(
        bool enabled,
        CancellationToken cancellationToken = default)
    {
        if (Snapshot is null || IsSaving || !HasConnectedRepository)
        {
            return;
        }

        IsSaving = true;
        SaveFailure = null;
        try
        {
            WindowsRepositoryConfig updated = Snapshot.Config with { FallbackToInbox = enabled };
            await bridge.UpdateConfigAsync(RepositoryPath!, updated, cancellationToken).ConfigureAwait(false);
            await LoadAsync(cancellationToken).ConfigureAwait(false);
        }
        catch (Exception error)
        {
            SaveFailure = FailureFor(error);
        }
        finally
        {
            IsSaving = false;
        }
    }

    public async Task<bool> ExportDiagnosticsAsync(CancellationToken cancellationToken = default)
    {
        if (!CanExportDiagnostics || Snapshot is null)
        {
            return false;
        }

        IsExportingDiagnostics = true;
        DiagnosticsFailure = null;
        LastDiagnosticsExportPath = null;
        try
        {
            LastDiagnosticsExportPath = await diagnosticsExporter
                .ExportAsync(Snapshot, cancellationToken)
                .ConfigureAwait(false);
            return true;
        }
        catch (Exception error) when (error is not OperationCanceledException)
        {
            DiagnosticsFailure = DiagnosticsFailureFor(error);
            return false;
        }
        finally
        {
            IsExportingDiagnostics = false;
        }
    }

    private static RepositorySettingsSnapshot BuildSnapshot(
        string repoPath,
        WindowsRepositoryConfig config,
        PlatformDifferencesCapabilities capabilities,
        string coreVersion)
    {
        return new RepositorySettingsSnapshot(
            RepositoryName(repoPath),
            repoPath,
            LocationType(repoPath),
            "Unknown",
            string.IsNullOrWhiteSpace(coreVersion) ? "Unknown" : coreVersion,
            AccessText(capabilities.SecurityBookmark),
            SupportText(capabilities.Watcher),
            CloudText(capabilities.CloudPlaceholder),
            config,
            capabilities);
    }

    private static string RepositoryName(string repoPath)
    {
        string trimmed = repoPath.TrimEnd('\\', '/');
        int separatorIndex = trimmed.LastIndexOfAny(['\\', '/']);
        string name = separatorIndex >= 0 ? trimmed[(separatorIndex + 1)..] : trimmed;
        return string.IsNullOrWhiteSpace(name) ? "AreaMatrix" : name;
    }

    private static string LocationType(string repoPath)
    {
        string lower = repoPath.ToLowerInvariant();
        if (lower.Contains("onedrive", StringComparison.Ordinal))
        {
            return "OneDrive";
        }
        if (lower.StartsWith(@"\\", StringComparison.Ordinal))
        {
            return "Network mount";
        }
        return "Local folder";
    }

    private static string AccessText(PlatformDifferencesCapabilitySupport support)
    {
        if (support.UiEnabled)
        {
            return support.RequiresPermission ? "Available, permission required" : "Available";
        }

        return string.IsNullOrWhiteSpace(support.Reason) ? "Unknown" : support.Reason;
    }

    private static string SupportText(PlatformDifferencesCapabilitySupport support)
    {
        return string.IsNullOrWhiteSpace(support.Reason) ? support.Status.ToString() : support.Reason;
    }

    private static string CloudText(PlatformDifferencesCapabilitySupport support)
    {
        return support.Status == PlatformDifferencesCapabilityStatus.NotAvailable
            ? "None"
            : SupportText(support);
    }

    private static RepositorySettingsFailure FailureFor(Exception error)
    {
        return new RepositorySettingsFailure(
            "Could not load repository status",
            error is OperationCanceledException
                ? "Try again."
                : "Reconnect the repository or retry after permissions are available.");
    }

    private static RepositorySettingsFailure DiagnosticsFailureFor(Exception error)
    {
        return new RepositorySettingsFailure(
            "Could not export repository diagnostics",
            error is WindowsRepositoryCoreException repositoryError
                ? repositoryError.Message
                : "Retry after repository permissions are available.");
    }

    private void OnPropertyChanged([CallerMemberName] string? propertyName = null)
    {
        PropertyChanged?.Invoke(this, new PropertyChangedEventArgs(propertyName));
    }
}
