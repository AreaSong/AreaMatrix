using System.ComponentModel;
using System.Text;
using System.Runtime.CompilerServices;
using Microsoft.Win32.SafeHandles;
using System.Runtime.InteropServices;
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
        try
        {
            return await LinuxRepositoryMetadataFileSafety.WriteDiagnosticsAsync(
                snapshot.Location,
                "repository-settings",
                DiagnosticLines(snapshot),
                cancellationToken).ConfigureAwait(false);
        }
        catch (LinuxRepositoryCoreException)
        {
            throw;
        }
        catch (Exception error) when (error is IOException or UnauthorizedAccessException)
        {
            throw new LinuxRepositoryCoreException(
                LinuxRepositoryErrorKind.PermissionDenied,
                "Repository metadata path is unavailable or unsafe.",
                snapshot.Location);
        }
    }

    private static IEnumerable<string> DiagnosticLines(RepositorySettingsSnapshot snapshot)
    {
        yield return "AreaMatrix Linux repository settings diagnostics";
        yield return "No user file contents are included.";
        yield return "Name: [redacted]";
        yield return "Location: [redacted]";
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

internal static class LinuxRepositoryMetadataFileSafety
{
    private const int O_RDONLY = 0;
    private const int O_WRONLY = 1;
    private const int O_CREAT = 64;
    private const int O_EXCL = 128;
    private const int O_CLOEXEC = 524288;
    private const int O_DIRECTORY = 65536;
    private const int O_NOFOLLOW = 131072;
    // POSIX modes are decimal in C# (0o600 == 384, 0o700 == 448).
    private const int UserReadWriteFileMode = 384;
    private const int UserDirectoryMode = 448;

    public static async Task<string> WriteDiagnosticsAsync(
        string repoPath,
        string prefix,
        IEnumerable<string> lines,
        CancellationToken cancellationToken)
    {
        cancellationToken.ThrowIfCancellationRequested();
        if (string.IsNullOrWhiteSpace(repoPath))
        {
            throw new LinuxRepositoryCoreException(
                LinuxRepositoryErrorKind.InvalidPath,
                "Repository path is required before exporting diagnostics.",
                repoPath);
        }

        using SafeFileHandle repository = OpenDirectory(repoPath, create: false);
        using SafeFileHandle metadata = OpenChild(repository, ".areamatrix", create: true);
        using SafeFileHandle generated = OpenChild(metadata, "generated", create: true);
        using SafeFileHandle diagnostics = OpenChild(generated, "diagnostics", create: true);

        string fileName = $"{prefix}-{DateTimeOffset.UtcNow:yyyyMMdd-HHmmss-fff}-{Guid.NewGuid():N}.txt";
        int fd = OpenAt(
            diagnostics,
            fileName,
            O_WRONLY | O_CREAT | O_EXCL | O_NOFOLLOW | O_CLOEXEC,
            UserReadWriteFileMode);
        if (fd < 0)
        {
            throw new IOException($"Could not create diagnostics file (errno {Marshal.GetLastWin32Error()}).");
        }

        using SafeFileHandle output = new((IntPtr)fd, ownsHandle: true);
        bool completed = false;
        try
        {
            string content = string.Join("\n", lines) + "\n";
            byte[] bytes = Encoding.UTF8.GetBytes(content);
            if (bytes.Length > 128 * 1024)
            {
                throw new IOException("Diagnostics output exceeds the bounded size limit.");
            }

            await using FileStream stream = new(output, FileAccess.Write, 4096, isAsync: true);
            await stream.WriteAsync(bytes, cancellationToken).ConfigureAwait(false);
            await stream.FlushAsync(cancellationToken).ConfigureAwait(false);
            stream.Flush(flushToDisk: true);
            completed = true;
        }
        finally
        {
            if (!completed)
            {
                // unlinkat is relative to the already-open, no-follow directory
                // descriptor; it cannot follow a replaced parent or escape repo.
                _ = UnlinkAt(diagnostics, fileName);
            }
        }

        // The caller only needs a stable display token. Returning the absolute
        // repository path would turn a local text export into a path disclosure.
        return Path.Combine(".areamatrix", "generated", "diagnostics", fileName);
    }

    private static SafeFileHandle OpenDirectory(string path, bool create)
    {
        string fullPath = Path.GetFullPath(path);
        int fd = Open(fullPath, O_RDONLY | O_DIRECTORY | O_NOFOLLOW | O_CLOEXEC, 0);
        if (fd < 0 && create && Marshal.GetLastWin32Error() == 2)
        {
            throw new DirectoryNotFoundException("Repository directory is missing.");
        }

        if (fd < 0)
        {
            throw new IOException($"Repository directory is unavailable or unsafe (errno {Marshal.GetLastWin32Error()}).");
        }

        return new SafeFileHandle((IntPtr)fd, ownsHandle: true);
    }

    private static SafeFileHandle OpenChild(SafeFileHandle parent, string name, bool create)
    {
        int fd = OpenAt(parent, name, O_RDONLY | O_DIRECTORY | O_NOFOLLOW | O_CLOEXEC, 0);
        if (fd < 0 && create && Marshal.GetLastWin32Error() == 2)
        {
            if (MkdirAt(parent, name, UserDirectoryMode) != 0 && Marshal.GetLastWin32Error() != 17)
            {
                throw new IOException($"Could not create metadata directory (errno {Marshal.GetLastWin32Error()}).");
            }

            fd = OpenAt(parent, name, O_RDONLY | O_DIRECTORY | O_NOFOLLOW | O_CLOEXEC, 0);
        }

        if (fd < 0)
        {
            throw new IOException($"Metadata directory is unavailable or unsafe (errno {Marshal.GetLastWin32Error()}).");
        }

        return new SafeFileHandle((IntPtr)fd, ownsHandle: true);
    }

    private static int Open(string path, int flags, int mode)
    {
        return open(path, flags, mode);
    }

    private static int OpenAt(SafeFileHandle parent, string name, int flags, int mode)
    {
        return openat(parent.DangerousGetHandle().ToInt32(), name, flags, mode);
    }

    private static int MkdirAt(SafeFileHandle parent, string name, int mode)
    {
        return mkdirat(parent.DangerousGetHandle().ToInt32(), name, mode);
    }

    private static int UnlinkAt(SafeFileHandle parent, string name)
    {
        return unlinkat(parent.DangerousGetHandle().ToInt32(), name, 0);
    }

    [DllImport("libc", SetLastError = true, EntryPoint = "open")]
    private static extern int open(string path, int flags, int mode);

    [DllImport("libc", SetLastError = true, EntryPoint = "openat")]
    private static extern int openat(int directoryFD, string path, int flags, int mode);

    [DllImport("libc", SetLastError = true, EntryPoint = "mkdirat")]
    private static extern int mkdirat(int directoryFD, string path, int mode);

    [DllImport("libc", SetLastError = true, EntryPoint = "unlinkat")]
    private static extern int unlinkat(int directoryFD, string path, int flags);
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
