using AreaMatrix.Linux.Tests.ChooseRepository;

namespace AreaMatrix.Linux.Tests.System;

public static class LinuxWatcherStatusSmokeTests
{
    public static void RunAll()
    {
        WatcherStatusPageExposesC419ManualRescanHandoff();
        RescanConfirmPageExecutesOnlyC419AfterConfirmation();
        LinuxDesktopShellWiresWatcherStatusToRealCoreBridge();
        NativeClientBindsC419ManualRescanCoreContracts();
    }

    private static void WatcherStatusPageExposesC419ManualRescanHandoff()
    {
        string ui = File.ReadAllText(RepositoryPath(
            "apps/linux/AreaMatrix/Features/System/WatcherStatusView.ui"));
        string view = File.ReadAllText(RepositoryPath(
            "apps/linux/AreaMatrix/Features/System/LinuxWatcherStatusView.cs"));
        string viewModel = File.ReadAllText(RepositoryPath(
            "apps/linux/AreaMatrix/Features/System/LinuxWatcherStatusViewModel.cs"));
        string rescanViewModel = File.ReadAllText(RepositoryPath(
            "apps/linux/AreaMatrix/Features/System/LinuxWatcherStatusViewModel.Rescan.cs"));
        string diagnostics = File.ReadAllText(RepositoryPath(
            "apps/linux/AreaMatrix/Features/System/LinuxWatcherDiagnostics.cs"));

        foreach (string fragment in new[]
        {
            "page_id: S4-LNX-04",
            "File watcher status",
            "Backend: inotify",
            "Watches: 128",
            "Checking watcher status...",
            "Linux has reached the inotify watch limit.",
            "AreaMatrix cannot watch this folder because of permissions.",
            "This location may not report all file changes.",
            "restart_watcher: LinuxWatcherStatusViewModel.RestartWatcherAsync",
            "run_rescan_now: LinuxWatcherStatusView.RunRescanNow",
            "export_diagnostics: LinuxWatcherStatusViewModel.ExportDiagnosticsAsync",
            "The page calls record_watcher_health through LinuxWatcherStatusCoreBridge.",
            "Run rescan now calls get_latest_scan_session and preview_manual_rescan before raising S4-X-07.",
            "Run rescan now raises OpenRescanConfirmRequested with LinuxRescanConfirmRequest for S4-X-07 and never calls reindex directly.",
            "The page does not call sync_external_changes, set_fs_event_cursor, reindex_from_filesystem, or resume_scan_session.",
            "The page never runs sudo, chmod, or modifies system inotify settings."
        })
        {
            TestAssert.Contains(fragment, ui, $"UI fragment {fragment}");
        }

        TestAssert.Contains("OpenRouteAsync", view, "watcher status route load");
        TestAssert.Contains("RestartWatcherAsync", view, "restart watcher trigger");
        TestAssert.Contains("OpenRescanConfirmRequested", view, "rescan confirmation handoff");
        TestAssert.Contains("LinuxRescanConfirmRequest", view, "rescan request includes preview");
        TestAssert.Contains("CanRequestRescanConfirm", view, "rescan handoff guard");
        TestAssert.Contains("RecordWatcherHealthAsync", viewModel, "C4-12 CoreBridge call");
        TestAssert.Contains("PrepareRescanConfirmAsync", rescanViewModel, "C4-19 preview preparation");
        TestAssert.Contains("PreviewManualRescanAsync", rescanViewModel, "C4-19 preview call");
        TestAssert.Contains("GetLatestScanSessionAsync", rescanViewModel, "C4-19 latest session call");
        TestAssert.Contains("CaptureSnapshotAsync", viewModel, "platform snapshot capture");
        TestAssert.Contains("RestartWatcherAsync", diagnostics, "explicit watcher restart");
        TestAssert.Contains("ExportDiagnosticsAsync", diagnostics, "diagnostics export");
        TestAssert.Contains(".areamatrix", diagnostics, "generated diagnostics path");
        TestAssert.Contains("Recent events are relative paths only; file contents are not exported.", diagnostics, "redaction note");
        TestAssert.NotContains("sudo", diagnostics, "no sudo");
        TestAssert.NotContains("chmod", diagnostics, "no chmod");
        TestAssert.NotContains("sync_external_changes", viewModel, "C4-12 must not sync events");
        TestAssert.NotContains("set_fs_event_cursor", viewModel, "C4-12 must not advance cursor");
        TestAssert.NotContains("ReindexFromFilesystemAsync", view, "watcher handoff must not run rescan");
        TestAssert.NotContains("ResumeScanSessionAsync", view, "watcher handoff must not resume rescan");
    }

    private static void RescanConfirmPageExecutesOnlyC419AfterConfirmation()
    {
        string ui = File.ReadAllText(RepositoryPath(
            "apps/linux/AreaMatrix/Features/System/RescanConfirmView.ui"));
        string view = File.ReadAllText(RepositoryPath(
            "apps/linux/AreaMatrix/Features/System/LinuxRescanConfirmView.cs"));
        string viewModel = File.ReadAllText(RepositoryPath(
            "apps/linux/AreaMatrix/Features/System/LinuxRescanConfirmViewModel.cs"));

        foreach (string fragment in new[]
        {
            "page_id: S4-X-07",
            "capability: C4-19 manual-rescan",
            "Run repository rescan?",
            "Preview only. No database records or files will be changed until you confirm.",
            "It will not move, delete, rename, or overwrite user files.",
            "Missing, unreadable, conflict, or unknown items will stay in Needs Review.",
            "I understand AreaMatrix will update its index from the current file system state.",
            "Run Rescan",
            "Success result shows added, updated, missing, conflicts, unreadable, unknown, and skipped counts."
        })
        {
            TestAssert.Contains(fragment, ui, $"S4-X-07 UI fragment {fragment}");
        }

        TestAssert.Contains("SetConfirmation", view, "confirmation setter");
        TestAssert.Contains("RunRescanAsync", view, "run action");
        TestAssert.Contains("UserConfirmed", viewModel, "explicit confirmation state");
        TestAssert.Contains("Preview?.CanRunRescan", viewModel, "stale preview disables run");
        TestAssert.Contains("ReindexFromFilesystemAsync", viewModel, "S4-X-07 executes C4-19 reindex");
        TestAssert.Contains("ErrorMessageFor", viewModel, "S4-X-07 error mapping");
        TestAssert.NotContains("ResumeScanSessionAsync", viewModel, "S4-X-07 does not resume adjacent flow");
        TestAssert.NotContains("SyncExternalChanges", viewModel, "S4-X-07 must not sync C4-12");
        TestAssert.NotContains("sudo", ui + viewModel, "S4-X-07 does not change system settings");
        TestAssert.NotContains("chmod", ui + viewModel, "S4-X-07 does not change permissions");
    }

    private static void LinuxDesktopShellWiresWatcherStatusToRealCoreBridge()
    {
        string shell = File.ReadAllText(RepositoryPath(
            "apps/linux/AreaMatrix/Features/Library/LinuxDesktopShell.cs"));
        string factories = File.ReadAllText(RepositoryPath(
            "apps/linux/AreaMatrix/Features/Library/LinuxDesktopShellFactories.cs"));
        string project = File.ReadAllText(RepositoryPath(
            "apps/linux/AreaMatrix/AreaMatrix.Linux.csproj"));

        TestAssert.Contains("OpenWatcherStatusAsync", shell, "watcher status route entry");
        TestAssert.Contains("ILinuxWatcherStatusViewFactory", shell, "watcher view factory");
        TestAssert.Contains("ILinuxRescanConfirmViewFactory", shell, "rescan confirm view factory");
        TestAssert.Contains("WatcherStatusView_OpenRescanConfirmRequested", shell, "watcher handoff handler");
        TestAssert.Contains("rescanConfirmViewFactory.Create(request)", shell, "S4-X-07 view creation");
        TestAssert.Contains("LinuxWatcherStatusCoreBridge watcherBridge = new(nativeCoreClient)", shell, "real watcher bridge");
        TestAssert.Contains("LinuxWatcherDiagnostics watcherDiagnostics = new()", shell, "real Linux diagnostics");
        TestAssert.Contains("new LinuxWatcherStatusViewFactory(watcherBridge, watcherDiagnostics)", shell, "watcher factory wiring");
        TestAssert.Contains("new LinuxRescanConfirmViewFactory(watcherBridge)", shell, "rescan factory wiring");
        TestAssert.Contains("LinuxRescanConfirmViewModel(coreBridge)", factories, "rescan confirm real bridge");
        TestAssert.Contains("WatcherStatusView.ui", project, "watcher status UI resource");
        TestAssert.Contains("RescanConfirmView.ui", project, "rescan confirm UI resource");
        TestAssert.NotContains("FakeLinuxWatcherStatusCoreBridge", shell, "no fake watcher bridge in production shell");
    }

    private static void NativeClientBindsC419ManualRescanCoreContracts()
    {
        string nativeLibrary = File.ReadAllText(RepositoryPath(
            "apps/linux/AreaMatrix/Core/NativeCoreLibrary.cs"));
        string nativeInterop = File.ReadAllText(RepositoryPath(
            "apps/linux/AreaMatrix/Core/NativeCoreInterop.cs"));
        string nativeClient = File.ReadAllText(RepositoryPath(
            "apps/linux/AreaMatrix/Core/AreaMatrixNativeCoreClient.cs"));
        string watcherClient = File.ReadAllText(RepositoryPath(
            "apps/linux/AreaMatrix/Core/AreaMatrixNativeCoreClient.WatcherStatus.cs"));
        string watcherBridge = File.ReadAllText(RepositoryPath(
            "apps/linux/AreaMatrix/Features/System/LinuxWatcherStatusCoreBridge.cs"));

        TestAssert.Contains(
            "uniffi_area_matrix_core_fn_func_record_watcher_health",
            nativeLibrary,
            "record_watcher_health native binding");
        TestAssert.Contains(
            "uniffi_area_matrix_core_checksum_func_record_watcher_health",
            nativeLibrary,
            "record_watcher_health checksum");
        TestAssert.Contains(
            "uniffi_area_matrix_core_fn_func_preview_manual_rescan",
            nativeLibrary,
            "preview_manual_rescan native binding");
        TestAssert.Contains(
            "uniffi_area_matrix_core_fn_func_reindex_from_filesystem",
            nativeLibrary,
            "reindex_from_filesystem native binding");
        TestAssert.Contains(
            "uniffi_area_matrix_core_fn_func_get_latest_scan_session",
            nativeLibrary,
            "get_latest_scan_session native binding");
        TestAssert.Contains(
            "uniffi_area_matrix_core_fn_func_resume_scan_session",
            nativeLibrary,
            "resume_scan_session native binding");
        TestAssert.Contains("RecordWatcherHealthDelegate", nativeInterop, "record watcher delegate");
        TestAssert.Contains("PreviewManualRescanDelegate", nativeInterop, "preview rescan delegate");
        TestAssert.Contains("GetLatestScanSessionDelegate", nativeInterop, "latest scan session delegate");
        TestAssert.Contains("RecordWatcherHealthChecksum = 47455", nativeClient, "record watcher checksum");
        TestAssert.Contains("PreviewManualRescanChecksum = 12140", nativeClient, "preview rescan checksum");
        TestAssert.Contains("GetLatestScanSessionChecksum = 31155", nativeClient, "latest scan session checksum");
        TestAssert.Contains("IAreaMatrixLinuxWatcherStatusCoreClient", nativeClient, "native client interface");
        TestAssert.Contains("RecordWatcherHealthAsync", watcherClient, "CoreBridge watcher call");
        TestAssert.Contains("PreviewManualRescanAsync", watcherClient, "CoreBridge preview call");
        TestAssert.Contains("GetLatestScanSessionAsync", watcherClient, "CoreBridge latest scan session call");
        TestAssert.Contains("ResumeScanSessionAsync", watcherClient, "CoreBridge resume call");
        TestAssert.Contains("LowerWatcherHealthSignal", watcherClient, "watcher signal lowering");
        TestAssert.Contains("ReadWatcherStatusSnapshot", watcherClient, "watcher snapshot reading");
        TestAssert.Contains("ReadManualRescanPreviewReport", watcherClient, "rescan preview reading");
        TestAssert.Contains("ReadScanSession", watcherClient, "scan session reading");
        TestAssert.Contains("LinuxWatcherStatusBackend.Inotify", watcherBridge, "Linux inotify backend mapping");
        TestAssert.NotContains("sync_external_changes", watcherClient, "C4-12 must not consume sync API");
        TestAssert.NotContains("set_fs_event_cursor", watcherClient, "C4-12 must not advance cursor");
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
