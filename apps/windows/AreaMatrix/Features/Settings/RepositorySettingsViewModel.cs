using System.ComponentModel;
using System.IO;
using System.Runtime.CompilerServices;
using System.Runtime.InteropServices;
using System.Text;
using Microsoft.Win32.SafeHandles;
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
        try
        {
            return await WindowsRepositoryMetadataFileSafety.WriteDiagnosticsAsync(
                snapshot.Location,
                "repository-settings",
                DiagnosticLines(snapshot),
                cancellationToken).ConfigureAwait(false);
        }
        catch (WindowsRepositoryCoreException)
        {
            throw;
        }
        catch (Exception error) when (error is IOException or UnauthorizedAccessException)
        {
            throw new WindowsRepositoryCoreException(
                WindowsRepositoryErrorKind.PermissionDenied,
                "Repository metadata path is unavailable or unsafe.",
                snapshot.Location);
        }
    }

    private static IEnumerable<string> DiagnosticLines(RepositorySettingsSnapshot snapshot)
    {
        yield return "AreaMatrix repository settings diagnostics";
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

internal static class WindowsRepositoryMetadataFileSafety
{
    private const int MaxDiagnosticsBytes = 128 * 1024;
    private const uint GenericRead = 0x80000000;
    private const uint FileShareRead = 0x00000001;
    private const uint FileShareWrite = 0x00000002;
    private const uint OpenExisting = 3;
    private const uint FileFlagBackupSemantics = 0x02000000;
    private const uint FileFlagOpenReparsePoint = 0x00200000;
    private const uint FileAttributeReparsePoint = 0x00000400;
    private const uint FileAttributeDirectory = 0x00000010;
    private const int FileAttributeTagInfo = 9;

    public static async Task<string> WriteDiagnosticsAsync(
        string repoPath,
        string prefix,
        IEnumerable<string> lines,
        CancellationToken cancellationToken)
    {
        cancellationToken.ThrowIfCancellationRequested();
        if (string.IsNullOrWhiteSpace(repoPath))
        {
            throw new WindowsRepositoryCoreException(
                WindowsRepositoryErrorKind.InvalidPath,
                "Repository path is required before exporting diagnostics.",
                repoPath);
        }

        using SafeDirectoryChain directoryChain = OpenDirectoryChain(
            repoPath,
            [".areamatrix", "generated", "diagnostics"],
            create: true);
        string diagnostics = directoryChain.FinalPath;
        string fileName = $"{prefix}-{DateTimeOffset.UtcNow:yyyyMMdd-HHmmss-fff}-{Guid.NewGuid():N}.txt";
        string outputPath = Path.Combine(diagnostics, fileName);
        byte[] bytes = Encoding.UTF8.GetBytes(string.Join("\n", lines) + "\n");
        if (bytes.Length > MaxDiagnosticsBytes)
        {
            throw new IOException("Diagnostics output exceeds the bounded size limit.");
        }

        bool createdOutput = false;
        bool completed = false;
        try
        {
            await using FileStream stream = new(
                outputPath,
                FileMode.CreateNew,
                FileAccess.Write,
                FileShare.None,
                bufferSize: 4096,
                options: FileOptions.WriteThrough | FileOptions.SequentialScan);
            createdOutput = true;
            await stream.WriteAsync(bytes, cancellationToken).ConfigureAwait(false);
            await stream.FlushAsync(cancellationToken).ConfigureAwait(false);
            completed = true;
        }
        finally
        {
            if (!completed && createdOutput)
            {
                try
                {
                    File.Delete(outputPath);
                }
                catch (IOException)
                {
                    // Leave an uncertain path untouched rather than risking an
                    // external file after a parent replacement.
                }
                catch (UnauthorizedAccessException)
                {
                    // Same fail-closed cleanup policy as above.
                }
            }
        }

        // Keep the UI result relative; an absolute repository path is sensitive
        // and is not needed to confirm that the export succeeded.
        return Path.Combine(".areamatrix", "generated", "diagnostics", fileName);
    }

    private static SafeDirectoryChain OpenDirectoryChain(
        string path,
        IReadOnlyList<string> children,
        bool create)
    {
        string fullPath;
        try
        {
            fullPath = Path.GetFullPath(path);
        }
        catch (Exception error) when (error is ArgumentException or NotSupportedException)
        {
            throw new WindowsRepositoryCoreException(
                WindowsRepositoryErrorKind.InvalidPath,
                "Repository path is invalid.",
                path);
        }

        return SafeDirectoryChain.Open(fullPath, children, create);
    }

    private sealed class SafeDirectoryChain : IDisposable
    {
        private readonly List<SafeFileHandle> handles;

        private SafeDirectoryChain(string finalPath, List<SafeFileHandle> handles)
        {
            FinalPath = finalPath;
            this.handles = handles;
        }

        public string FinalPath { get; }

        public static SafeDirectoryChain Open(
            string fullPath,
            IReadOnlyList<string> children,
            bool create)
        {
            string? current = Path.GetPathRoot(fullPath);
            if (string.IsNullOrWhiteSpace(current))
            {
                throw new IOException("Repository path has no stable root.");
            }

            List<SafeFileHandle> handles = [];
            try
            {
                handles.Add(OpenDirectoryHandle(current));
                string remainder = fullPath[current.Length..];
                foreach (string component in remainder.Split(
                    [Path.DirectorySeparatorChar, Path.AltDirectorySeparatorChar],
                    StringSplitOptions.RemoveEmptyEntries))
                {
                    current = Path.Combine(current, component);
                    handles.Add(OpenOrCreateChild(handles[^1], current, component, create));
                }

                foreach (string child in children)
                {
                    current = Path.Combine(current, child);
                    handles.Add(OpenOrCreateChild(handles[^1], current, child, create));
                }

                return new SafeDirectoryChain(current, handles);
            }
            catch
            {
                foreach (SafeFileHandle handle in handles.AsEnumerable().Reverse())
                {
                    handle.Dispose();
                }

                throw;
            }
        }

        private static SafeFileHandle OpenOrCreateChild(
            SafeFileHandle parent,
            string path,
            string component,
            bool create)
        {
            SafeFileHandle handle = TryOpenDirectoryHandle(path, out int error);
            if (!handle.IsInvalid)
            {
                return handle;
            }

            handle.Dispose();
            if (!create || error != 2)
            {
                throw new IOException($"Repository metadata path is unavailable or unsafe (errno {error}).");
            }

            Directory.CreateDirectory(path);
            return OpenDirectoryHandle(path);
        }

        private static SafeFileHandle OpenDirectoryHandle(string path)
        {
            SafeFileHandle handle = TryOpenDirectoryHandle(path, out int error);
            if (handle.IsInvalid)
            {
                handle.Dispose();
                throw new IOException($"Repository directory is unavailable or unsafe (errno {error}).");
            }

            return handle;
        }

        private static SafeFileHandle TryOpenDirectoryHandle(string path, out int error)
        {
            SafeFileHandle handle = CreateFileW(
                path,
                GenericRead,
                FileShareRead | FileShareWrite,
                IntPtr.Zero,
                OpenExisting,
                FileFlagBackupSemantics | FileFlagOpenReparsePoint,
                IntPtr.Zero);
            if (handle.IsInvalid)
            {
                error = Marshal.GetLastWin32Error();
                return handle;
            }

            if (!GetFileInformationByHandleEx(
                    handle,
                    FileAttributeTagInfo,
                    out FileAttributeTagInfoData info,
                    (uint)Marshal.SizeOf<FileAttributeTagInfoData>())
                || (info.FileAttributes & FileAttributeDirectory) == 0
                || (info.FileAttributes & FileAttributeReparsePoint) != 0)
            {
                handle.Dispose();
                throw new IOException("Repository metadata path contains a reparse point or is not a directory.");
            }

            error = 0;
            return handle;
        }

        public void Dispose()
        {
            foreach (SafeFileHandle handle in handles.AsEnumerable().Reverse())
            {
                handle.Dispose();
            }
        }
    }

    [StructLayout(LayoutKind.Sequential)]
    private struct FileAttributeTagInfoData
    {
        public uint FileAttributes;
        public uint ReparseTag;
    }

    [DllImport("kernel32.dll", CharSet = CharSet.Unicode, SetLastError = true)]
    private static extern SafeFileHandle CreateFileW(
        string fileName,
        uint desiredAccess,
        uint shareMode,
        IntPtr securityAttributes,
        uint creationDisposition,
        uint flagsAndAttributes,
        IntPtr templateFile);

    [DllImport("kernel32.dll", SetLastError = true)]
    private static extern bool GetFileInformationByHandleEx(
        SafeFileHandle file,
        int fileInformationClass,
        out FileAttributeTagInfoData fileInformation,
        uint bufferSize);
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
            await Task.WhenAll(configTask, capabilitiesTask, versionTask);

            Snapshot = BuildSnapshot(
                RepositoryPath!,
                await configTask,
                await capabilitiesTask,
                await versionTask);
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
            await bridge.UpdateConfigAsync(RepositoryPath!, updated, cancellationToken);
            await LoadAsync(cancellationToken);
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
                .ExportAsync(Snapshot, cancellationToken);
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
