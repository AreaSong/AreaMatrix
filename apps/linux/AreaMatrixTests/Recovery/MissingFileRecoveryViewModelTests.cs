using AreaMatrix.Linux.Features.Library;
using AreaMatrix.Linux.Features.Onboarding;
using AreaMatrix.Linux.Features.Recovery;
using AreaMatrix.Linux.Tests.ChooseRepository;
using AreaMatrix.Linux.Tests.Library;

namespace AreaMatrix.Linux.Tests.Recovery;

public static class MissingFileRecoveryViewModelTests
{
    public static async Task RunAllAsync()
    {
        await OpeningRecoveryLoadsC418State();
        await TryAgainOnlyRefreshesMissingState();
        await LocateFileUsesNativePickerAndDoesNotRelinkOnCancel();
        await RelinkUsesConfirmedCoreRequestAndReportsHashMismatch();
        await RemoveRecordRequiresConfirmationAndDoesNotDeleteFiles();
        await CoreBridgeMapsRecoveryContract();
        await LinuxDesktopShellOpensRecoveryRouteFromMissingSelection();
        S4X06WiresLinuxRecoveryRouteToCoreBridge();
    }

    private static async Task OpeningRecoveryLoadsC418State()
    {
        FakeMissingFileRecoveryCoreBridge bridge = new();
        MissingFileRecoveryViewModel model = new(bridge);

        await model.OpenAsync("/home/me/AreaMatrix", 42);

        TestAssert.SequenceEqual([("state", "/home/me/AreaMatrix", 42)], bridge.Requests, nameof(bridge.Requests));
        TestAssert.Equal("docs/report.pdf", model.State?.RelativePath, "relative path");
        TestAssert.Equal(MissingFileReason.PathMissing, model.State?.Reason, "reason");
        TestAssert.False(model.CanRemoveRecord, nameof(model.CanRemoveRecord));
    }

    private static async Task TryAgainOnlyRefreshesMissingState()
    {
        FakeMissingFileRecoveryCoreBridge bridge = new();
        MissingFileRecoveryViewModel model = new(bridge);

        await model.OpenAsync("/home/me/AreaMatrix", 7);
        await model.RefreshAsync();

        TestAssert.SequenceEqual(
            [
                ("state", "/home/me/AreaMatrix", 7),
                ("state", "/home/me/AreaMatrix", 7)
            ],
            bridge.Requests,
            nameof(bridge.Requests));
    }

    private static async Task RelinkUsesConfirmedCoreRequestAndReportsHashMismatch()
    {
        FakeMissingFileRecoveryCoreBridge bridge = new()
        {
            RelinkReport = Report(9, MissingFileRecoveryStatus.HashMismatch, hashMatched: false)
        };
        FakeMissingFileRecoveryFilePicker picker = new("/home/me/Desktop/report.pdf");
        MissingFileRecoveryView view = new(new MissingFileRecoveryViewModel(bridge), picker);

        await view.OpenRouteAsync(new MissingFileRecoveryRoute("/home/me/AreaMatrix", 9));
        await view.LocateFileAsync();
        await view.RelinkSelectedFileAsync();

        TestAssert.Equal(9, bridge.LastRelinkRequest?.FileId, "relink file id");
        TestAssert.Equal("/home/me/Desktop/report.pdf", bridge.LastRelinkRequest?.NewPath, "relink path");
        TestAssert.True(bridge.LastRelinkRequest?.Confirmed == true, "relink confirmed");
        TestAssert.True(picker.WasOpened, "picker opened");
        TestAssert.Equal(MissingFileRecoveryStatus.HashMismatch, view.ViewModel.Report?.Status, "report status");
        TestAssert.Contains("does not match", view.ViewModel.Error?.Message ?? "", "hash mismatch message");
    }

    private static async Task LocateFileUsesNativePickerAndDoesNotRelinkOnCancel()
    {
        FakeMissingFileRecoveryCoreBridge bridge = new();
        FakeMissingFileRecoveryFilePicker picker = new(null);
        MissingFileRecoveryView view = new(new MissingFileRecoveryViewModel(bridge), picker);

        await view.OpenRouteAsync(new MissingFileRecoveryRoute("/home/me/AreaMatrix", 8));
        await view.LocateFileAsync();
        await view.RelinkSelectedFileAsync();

        TestAssert.True(picker.WasOpened, "picker opened");
        TestAssert.Equal(string.Empty, view.ViewModel.SelectedRelinkPath, "selected relink path");
        TestAssert.Equal(null, bridge.LastRelinkRequest, "cancelled picker must not relink");
    }

    private static async Task RemoveRecordRequiresConfirmationAndDoesNotDeleteFiles()
    {
        FakeMissingFileRecoveryCoreBridge bridge = new()
        {
            RemoveReport = Report(
                11,
                MissingFileRecoveryStatus.RecordRemoved,
                recordRemoved: true,
                fileDeleted: false,
                changeLogAction: "missing_file_record_removed")
        };
        MissingFileRecoveryViewModel model = new(bridge);

        await model.OpenAsync("/home/me/AreaMatrix", 11);
        await model.RemoveRecordAsync();
        model.RemoveRecordConfirmed = true;
        await model.RemoveRecordAsync();

        TestAssert.Equal(11, bridge.LastRemoveRequest?.FileId, "remove file id");
        TestAssert.True(bridge.LastRemoveRequest?.Confirmed == true, "remove confirmed");
        TestAssert.True(model.Report?.RecordRemoved == true, "record removed");
        TestAssert.False(model.Report?.FileDeleted == true, "file deleted");
        TestAssert.Equal("missing_file_record_removed", model.Report?.ChangeLogAction, "change log action");
    }

    private static async Task CoreBridgeMapsRecoveryContract()
    {
        RecordingMissingFileRecoveryCoreClient client = new();
        MissingFileRecoveryCoreBridge bridge = new(client);

        MissingFileRecoveryState state = await bridge.GetMissingFileStateAsync("/home/me/AreaMatrix", 3);
        MissingFileRecoveryReport report = await bridge.RemoveMissingFileRecordAsync(
            "/home/me/AreaMatrix",
            new MissingFileRemoveRecordRequest(3, true));

        TestAssert.Equal(MissingFileReason.CloudPlaceholder, state.Reason, "mapped reason");
        TestAssert.Equal(MissingFileRecoveryStatus.RecordRemoved, report.Status, "mapped status");
        TestAssert.False(report.FileDeleted, "mapped file deleted");
        TestAssert.Equal(3, client.LastRemoveRequest?.FileId, "core remove file id");
    }

    private static async Task LinuxDesktopShellOpensRecoveryRouteFromMissingSelection()
    {
        FakeDesktopMainQueryCoreBridge queryBridge = new(includeMissingFile: true);
        FakeLinuxMainWindowFactory mainWindowFactory = new(queryBridge);
        FakeMissingFileRecoveryViewFactory recoveryFactory = new(new FakeMissingFileRecoveryCoreBridge());
        LinuxChooseRepositoryViewModel chooseModel = new(
            new FakeLinuxRepositoryCoreBridge(
                LinuxRepositoryValidationSamples.Initialized("/home/me/AreaMatrix")));
        LinuxChooseRepositoryView chooseView = new(
            chooseModel,
            new FakeLinuxFolderPickerAdapter("/home/me/AreaMatrix"));
        LinuxDesktopShell shell = new(
            chooseView,
            mainWindowFactory,
            missingFileRecoveryViewFactory: recoveryFactory);

        await chooseView.TypeRepositoryPathAsync("/home/me/AreaMatrix");
        await shell.ContinueFromRepositorySelectionAsync();
        await shell.MainWindow!.SelectFileAsync(shell.MainWindow.ViewModel.Files.Single(file =>
            file.AvailabilityStatus == AreaMatrix.Linux.Features.Library.DesktopFileAvailabilityStatus.Missing));
        bool opened = await shell.OpenMissingFileRecoveryAsync();

        TestAssert.True(opened, "recovery opened");
        TestAssert.NotNull(shell.MissingFileRecoveryView, nameof(shell.MissingFileRecoveryView));
        TestAssert.SequenceEqual(
            [("/home/me/AreaMatrix", 3)],
            recoveryFactory.CreatedRoutes.Select(route => (route.RepoPath, route.FileId)).ToArray(),
            "recovery routes");
    }

    private static void S4X06WiresLinuxRecoveryRouteToCoreBridge()
    {
        string project = File.ReadAllText(RepositoryPath("apps/linux/AreaMatrix/AreaMatrix.Linux.csproj"));
        string ui = File.ReadAllText(RepositoryPath(
            "apps/linux/AreaMatrix/Features/Recovery/MissingFileRecoveryView.ui"));
        string shell = File.ReadAllText(RepositoryPath(
            "apps/linux/AreaMatrix/Features/Library/LinuxDesktopShell.cs"));
        string mainModel = File.ReadAllText(RepositoryPath(
            "apps/linux/AreaMatrix/Features/Library/LinuxMainWindowViewModel.cs"));
        string view = File.ReadAllText(RepositoryPath(
            "apps/linux/AreaMatrix/Features/Recovery/MissingFileRecoveryView.cs"));
        string viewModel = File.ReadAllText(RepositoryPath(
            "apps/linux/AreaMatrix/Features/Recovery/MissingFileRecoveryViewModel.cs"));
        string picker = File.ReadAllText(RepositoryPath(
            "apps/linux/AreaMatrix/Features/Recovery/MissingFileRecoveryFilePicker.cs"));
        string bridge = File.ReadAllText(RepositoryPath(
            "apps/linux/AreaMatrix/Features/Recovery/MissingFileRecoveryCoreBridge.cs"));
        string nativeClient = File.ReadAllText(RepositoryPath(
            "apps/linux/AreaMatrix/Core/AreaMatrixNativeCoreClient.MissingFileRecovery.cs"));
        string nativeLibrary = File.ReadAllText(RepositoryPath(
            "apps/linux/AreaMatrix/Core/NativeCoreLibrary.cs"));
        string nativeInterop = File.ReadAllText(RepositoryPath(
            "apps/linux/AreaMatrix/Core/NativeCoreInterop.cs"));
        string coreClient = File.ReadAllText(RepositoryPath(
            "apps/linux/AreaMatrix/Core/AreaMatrixNativeCoreClient.cs"));

        TestAssert.Contains("MissingFileRecoveryView.ui", project, "recovery UI resource");
        TestAssert.Contains("page_id: S4-X-06", ui, "S4-X-06 UI id");
        TestAssert.Contains("<object class=\"GtkDialog\" id=\"S4X06MissingFileRecoveryDialog\">", ui, "native GTK dialog");
        TestAssert.Contains("id=\"LocateFileButton\"", ui, "locate file button");
        TestAssert.Contains("<property name=\"action-name\">recovery.locate-file</property>", ui, "locate action");
        TestAssert.Contains("id=\"RelinkFileButton\"", ui, "relink file button");
        TestAssert.Contains("<property name=\"action-name\">recovery.relink-file</property>", ui, "relink action");
        TestAssert.Contains("id=\"RemoveRecordButton\"", ui, "remove record button");
        TestAssert.Contains("CanOpenMissingFileRecovery", mainModel, "missing file recovery route gate");
        TestAssert.Contains("OpenMissingFileRecoveryAsync", shell, "recovery route entry");
        TestAssert.Contains("MissingFileRecoveryCoreBridge recoveryBridge = new(nativeCoreClient)", shell, "real recovery bridge");
        TestAssert.Contains("new LinuxMissingFileRecoveryViewFactory(recoveryBridge)", shell, "recovery factory wiring");
        TestAssert.Contains("LocateFileAsync", view, "locate user action");
        TestAssert.Contains("PickReplacementFileAsync", view + picker, "native picker path");
        TestAssert.Contains("zenity", picker, "zenity native picker");
        TestAssert.Contains("kdialog", picker, "kdialog native picker");
        TestAssert.Contains("RelinkSelectedFileAsync", view, "relink user action");
        TestAssert.Contains("RemoveRecordAsync", view, "remove record user action");
        TestAssert.Contains("GetMissingFileStateAsync", viewModel + bridge, "C4-18 state call");
        TestAssert.Contains("RelinkMissingFileAsync", viewModel + bridge, "C4-18 relink call");
        TestAssert.Contains("RemoveMissingFileRecordAsync", viewModel + bridge, "C4-18 remove call");
        TestAssert.Contains("uniffi_area_matrix_core_fn_func_get_missing_file_state", nativeLibrary, "state native binding");
        TestAssert.Contains("uniffi_area_matrix_core_fn_func_relink_missing_file", nativeLibrary, "relink native binding");
        TestAssert.Contains("uniffi_area_matrix_core_fn_func_remove_missing_file_record", nativeLibrary, "remove native binding");
        TestAssert.Contains("GetMissingFileStateDelegate", nativeInterop, "state delegate");
        TestAssert.Contains("GetMissingFileStateChecksum = 9097", coreClient, "state checksum");
        TestAssert.Contains("RelinkMissingFileChecksum = 39194", coreClient, "relink checksum");
        TestAssert.Contains("RemoveMissingFileRecordChecksum = 46697", coreClient, "remove checksum");
        TestAssert.Contains("LowerMissingFileRelinkRequest", nativeClient, "relink request lowering");
        TestAssert.Contains("LowerMissingFileRemoveRecordRequest", nativeClient, "remove request lowering");
        TestAssert.NotContains("ReindexFromFilesystemAsync", view + viewModel + bridge, "C4-18 must not run rescan");
        TestAssert.NotContains("PreviewManualRescanAsync", view + viewModel + bridge, "C4-18 must not preview rescan");
    }

    private static MissingFileRecoveryState State(long fileId)
    {
        return new MissingFileRecoveryState(
            fileId,
            "docs/report.pdf",
            "/home/me/AreaMatrix/docs/report.pdf",
            1_700_000_000,
            MissingFileReason.PathMissing,
            "hash",
            true,
            true,
            true,
            true,
            true,
            null);
    }

    private static MissingFileRecoveryReport Report(
        long fileId,
        MissingFileRecoveryStatus status,
        bool hashMatched = false,
        bool recordRemoved = false,
        bool fileDeleted = false,
        string? changeLogAction = null)
    {
        return new MissingFileRecoveryReport(
            fileId,
            status,
            "docs/report.pdf",
            status == MissingFileRecoveryStatus.Relinked ? "/home/me/Selected/report.pdf" : null,
            hashMatched,
            recordRemoved,
            fileDeleted,
            changeLogAction,
            null);
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

        throw new InvalidOperationException($"Could not locate `{relativePath}`.");
    }

    private sealed class FakeMissingFileRecoveryCoreBridge : IMissingFileRecoveryCoreBridge
    {
        public List<(string Action, string RepoPath, long FileId)> Requests { get; } = [];

        public MissingFileRecoveryReport RelinkReport { get; set; } =
            Report(1, MissingFileRecoveryStatus.Relinked, hashMatched: true);

        public MissingFileRecoveryReport RemoveReport { get; set; } =
            Report(1, MissingFileRecoveryStatus.RecordRemoved, recordRemoved: true);

        public MissingFileRelinkRequest? LastRelinkRequest { get; private set; }

        public MissingFileRemoveRecordRequest? LastRemoveRequest { get; private set; }

        public Task<MissingFileRecoveryState> GetMissingFileStateAsync(
            string repoPath,
            long fileId,
            CancellationToken cancellationToken = default)
        {
            Requests.Add(("state", repoPath, fileId));
            return Task.FromResult(State(fileId));
        }

        public Task<MissingFileRecoveryReport> RelinkMissingFileAsync(
            string repoPath,
            MissingFileRelinkRequest request,
            CancellationToken cancellationToken = default)
        {
            LastRelinkRequest = request;
            Requests.Add(("relink", repoPath, request.FileId));
            return Task.FromResult(RelinkReport with { FileId = request.FileId });
        }

        public Task<MissingFileRecoveryReport> RemoveMissingFileRecordAsync(
            string repoPath,
            MissingFileRemoveRecordRequest request,
            CancellationToken cancellationToken = default)
        {
            LastRemoveRequest = request;
            Requests.Add(("remove", repoPath, request.FileId));
            return Task.FromResult(RemoveReport with { FileId = request.FileId });
        }
    }

    private sealed class RecordingMissingFileRecoveryCoreClient : IAreaMatrixLinuxMissingFileRecoveryCoreClient
    {
        public CoreMissingFileRemoveRecordRequest? LastRemoveRequest { get; private set; }

        public Task<CoreMissingFileState> GetMissingFileStateAsync(
            string repoPath,
            long fileId,
            CancellationToken cancellationToken = default)
        {
            return Task.FromResult(new CoreMissingFileState(
                fileId,
                "docs/report.pdf",
                "/home/me/AreaMatrix/docs/report.pdf",
                1_700_000_000,
                "CloudPlaceholder",
                "hash",
                true,
                true,
                true,
                true,
                false,
                "Rescan is a separate C4-19 route."));
        }

        public Task<CoreMissingFileRecoveryReport> RelinkMissingFileAsync(
            string repoPath,
            CoreMissingFileRelinkRequest request,
            CancellationToken cancellationToken = default)
        {
            return Task.FromResult(new CoreMissingFileRecoveryReport(
                request.FileId,
                "Relinked",
                "docs/report.pdf",
                request.NewPath,
                true,
                false,
                false,
                "missing_file_relinked",
                null));
        }

        public Task<CoreMissingFileRecoveryReport> RemoveMissingFileRecordAsync(
            string repoPath,
            CoreMissingFileRemoveRecordRequest request,
            CancellationToken cancellationToken = default)
        {
            LastRemoveRequest = request;
            return Task.FromResult(new CoreMissingFileRecoveryReport(
                request.FileId,
                "RecordRemoved",
                "docs/report.pdf",
                null,
                false,
                true,
                false,
                "missing_file_record_removed",
                null));
        }
    }

    private sealed class FakeMissingFileRecoveryViewFactory : ILinuxMissingFileRecoveryViewFactory
    {
        private readonly IMissingFileRecoveryCoreBridge bridge;

        public FakeMissingFileRecoveryViewFactory(IMissingFileRecoveryCoreBridge bridge)
        {
            this.bridge = bridge;
        }

        public List<MissingFileRecoveryRoute> CreatedRoutes { get; } = [];

        public MissingFileRecoveryView Create(MissingFileRecoveryRoute route)
        {
            CreatedRoutes.Add(route);
            return new MissingFileRecoveryView(new MissingFileRecoveryViewModel(bridge));
        }
    }

    private sealed class FakeMissingFileRecoveryFilePicker : IMissingFileRecoveryFilePicker
    {
        private readonly string? selectedPath;

        public FakeMissingFileRecoveryFilePicker(string? selectedPath)
        {
            this.selectedPath = selectedPath;
        }

        public bool WasOpened { get; private set; }

        public Task<string?> PickReplacementFileAsync(CancellationToken cancellationToken = default)
        {
            cancellationToken.ThrowIfCancellationRequested();
            WasOpened = true;
            return Task.FromResult(selectedPath);
        }
    }
}
