using System.ComponentModel;
using System.Runtime.CompilerServices;
using AreaMatrix.Linux.Features.Onboarding;

namespace AreaMatrix.Linux.Features.Settings;

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
    LinuxRepositoryConfig Config,
    LinuxPlatformCapabilities Capabilities);

public interface ILinuxRepositorySettingsDiagnosticsExporter
{
    Task<string> ExportAsync(
        RepositorySettingsSnapshot snapshot,
        CancellationToken cancellationToken = default);
}

public sealed class LinuxRepositorySettingsDiagnosticsExporter : ILinuxRepositorySettingsDiagnosticsExporter
{
    public async Task<string> ExportAsync(
        RepositorySettingsSnapshot snapshot,
        CancellationToken cancellationToken = default)
    {
        cancellationToken.ThrowIfCancellationRequested();
        if (string.IsNullOrWhiteSpace(snapshot.Location) || !Directory.Exists(snapshot.Location))
        {
            throw new LinuxRepositoryCoreException(
                LinuxRepositoryErrorKind.FileNotFound,
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
        yield return "AreaMatrix Linux repository settings diagnostics";
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

public sealed class RepositorySettingsViewModel : INotifyPropertyChanged
{
    private readonly ILinuxRepositoryCoreBridge repositoryBridge;
    private readonly ILinuxPlatformCapabilitiesCoreBridge capabilityBridge;
    private readonly ILinuxRepositorySettingsDiagnosticsExporter diagnosticsExporter;
    private RepositorySettingsSnapshot? snapshot;
    private RepositorySettingsFailure? failure;
    private RepositorySettingsFailure? saveFailure;
    private RepositorySettingsFailure? diagnosticsFailure;
    private string? lastDiagnosticsExportPath;
    private bool isSaving;
    private bool isExportingDiagnostics;

    public RepositorySettingsViewModel(
        ILinuxRepositoryCoreBridge repositoryBridge,
        ILinuxPlatformCapabilitiesCoreBridge capabilityBridge,
        string? repositoryPath = null,
        string appVersion = "1",
        ILinuxRepositorySettingsDiagnosticsExporter? diagnosticsExporter = null)
    {
        this.repositoryBridge = repositoryBridge;
        this.capabilityBridge = capabilityBridge;
        this.diagnosticsExporter = diagnosticsExporter ?? new LinuxRepositorySettingsDiagnosticsExporter();
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
            NotifyStateChanged();
            return;
        }

        Status = RepositorySettingsStatus.Loading;
        Failure = null;
        SaveFailure = null;
        DiagnosticsFailure = null;
        NotifyStateChanged();

        try
        {
            Task<LinuxRepositoryConfig> configTask = repositoryBridge.LoadConfigAsync(RepositoryPath!, cancellationToken);
            Task<LinuxPlatformCapabilities> capabilitiesTask = capabilityBridge.GetPlatformCapabilitiesAsync(
                LinuxPlatformId.Linux,
                AppVersion,
                cancellationToken);
            Task<string> versionTask = repositoryBridge.GetCoreVersionAsync(cancellationToken);
            await Task.WhenAll(configTask, capabilitiesTask, versionTask).ConfigureAwait(false);
            LinuxRepositoryConfig config = await configTask.ConfigureAwait(false);
            LinuxPlatformCapabilities capabilities = await capabilitiesTask.ConfigureAwait(false);
            Snapshot = BuildSnapshot(
                RepositoryPath!,
                config,
                capabilities,
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
            NotifyStateChanged();
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
            LinuxRepositoryConfig updated = Snapshot.Config with { FallbackToInbox = enabled };
            await repositoryBridge.UpdateConfigAsync(RepositoryPath!, updated, cancellationToken).ConfigureAwait(false);
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
        LinuxRepositoryConfig config,
        LinuxPlatformCapabilities capabilities,
        string coreVersion)
    {
        return new RepositorySettingsSnapshot(
            Path.GetFileName(repoPath.TrimEnd(Path.DirectorySeparatorChar)),
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

    private static string LocationType(string repoPath)
    {
        string normalized = repoPath.Trim().ToLowerInvariant();
        if (normalized.StartsWith("/media/", StringComparison.Ordinal)
            || normalized.StartsWith("/run/media/", StringComparison.Ordinal))
        {
            return "External drive";
        }
        if (normalized.StartsWith("/mnt/", StringComparison.Ordinal))
        {
            return "Network mount";
        }
        return "Local folder";
    }

    private static string AccessText(LinuxPlatformCapabilitySupport support)
    {
        if (support.UiEnabled)
        {
            return support.RequiresPermission ? "Available, permission required" : "Available";
        }

        return support.Status switch
        {
            LinuxPlatformCapabilityStatus.Limited => AccessStateText("Expired", support.Reason),
            LinuxPlatformCapabilityStatus.NotAvailable => AccessStateText("Permission denied", support.Reason),
            LinuxPlatformCapabilityStatus.Unknown => AccessStateText("Unknown", support.Reason),
            LinuxPlatformCapabilityStatus.Available => AccessStateText("Unknown", support.Reason),
            _ => "Unknown"
        };
    }

    private static string AccessStateText(string state, string? reason)
    {
        return string.IsNullOrWhiteSpace(reason) ? state : $"{state}: {reason}";
    }

    private static string SupportText(LinuxPlatformCapabilitySupport support)
    {
        return string.IsNullOrWhiteSpace(support.Reason) ? support.Status.ToString() : support.Reason;
    }

    private static string CloudText(LinuxPlatformCapabilitySupport support)
    {
        return support.Status == LinuxPlatformCapabilityStatus.NotAvailable ? "None" : SupportText(support);
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
            error is LinuxRepositoryCoreException repositoryError
                ? repositoryError.Message
                : "Retry after repository permissions are available.");
    }

    private void NotifyStateChanged()
    {
        OnPropertyChanged(nameof(Status));
        OnPropertyChanged(nameof(CanExportDiagnostics));
    }

    private void OnPropertyChanged([CallerMemberName] string? propertyName = null)
    {
        PropertyChanged?.Invoke(this, new PropertyChangedEventArgs(propertyName));
    }
}
