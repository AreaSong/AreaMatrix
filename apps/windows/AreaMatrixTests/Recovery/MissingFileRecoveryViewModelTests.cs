using AreaMatrix.Features.Onboarding;
using AreaMatrix.Features.Recovery;
using AreaMatrixTests.ChooseRepository;

namespace AreaMatrixTests.Recovery;

public static class MissingFileRecoveryViewModelTests
{
    public static async Task RunAllAsync()
    {
        await OpeningRecoveryLoadsC418State();
        await TryAgainOnlyRefreshesMissingState();
        await RelinkUsesConfirmedCoreRequestAndReportsHashMismatch();
        await RemoveRecordRequiresConfirmationAndDoesNotDeleteFiles();
        await CoreBridgeMapsRecoveryContract();
        S4X06WiresMainWindowRecoveryRouteToCoreBridge();
    }

    private static async Task OpeningRecoveryLoadsC418State()
    {
        FakeMissingFileRecoveryCoreBridge bridge = new();
        MissingFileRecoveryViewModel model = new(bridge);

        await model.OpenAsync(@"C:\Repos\AreaMatrix", 42);

        TestAssert.SequenceEqual([("state", @"C:\Repos\AreaMatrix", 42)], bridge.Requests, nameof(bridge.Requests));
        TestAssert.Equal("docs\\report.pdf", model.State?.RelativePath, "relative path");
        TestAssert.Equal(MissingFileReason.PathMissing, model.State?.Reason, "reason");
        TestAssert.False(model.CanRemoveRecord, nameof(model.CanRemoveRecord));
    }

    private static async Task TryAgainOnlyRefreshesMissingState()
    {
        FakeMissingFileRecoveryCoreBridge bridge = new();
        MissingFileRecoveryViewModel model = new(bridge);

        await model.OpenAsync(@"C:\Repos\AreaMatrix", 7);
        await model.RefreshAsync();

        TestAssert.SequenceEqual(
            [
                ("state", @"C:\Repos\AreaMatrix", 7),
                ("state", @"C:\Repos\AreaMatrix", 7)
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
        MissingFileRecoveryViewModel model = new(bridge);

        await model.OpenAsync(@"C:\Repos\AreaMatrix", 9);
        model.SelectedRelinkPath = @"C:\Users\me\Desktop\report.pdf";
        await model.RelinkSelectedFileAsync();

        TestAssert.Equal(9, bridge.LastRelinkRequest?.FileId, "relink file id");
        TestAssert.Equal(@"C:\Users\me\Desktop\report.pdf", bridge.LastRelinkRequest?.NewPath, "relink path");
        TestAssert.True(bridge.LastRelinkRequest?.Confirmed == true, "relink confirmed");
        TestAssert.Equal(MissingFileRecoveryStatus.HashMismatch, model.Report?.Status, "report status");
        TestAssert.Contains("does not match", model.Error?.Message ?? "", "hash mismatch message");
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

        await model.OpenAsync(@"C:\Repos\AreaMatrix", 11);
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

        MissingFileRecoveryState state = await bridge.GetMissingFileStateAsync(@"C:\Repo", 3);
        MissingFileRecoveryReport report = await bridge.RemoveMissingFileRecordAsync(
            @"C:\Repo",
            new MissingFileRemoveRecordRequest(3, true));

        TestAssert.Equal(MissingFileReason.CloudPlaceholder, state.Reason, "mapped reason");
        TestAssert.Equal(MissingFileRecoveryStatus.RecordRemoved, report.Status, "mapped status");
        TestAssert.False(report.FileDeleted, "mapped file deleted");
        TestAssert.Equal(3, client.LastRemoveRequest?.FileId, "core remove file id");
    }

    private static void S4X06WiresMainWindowRecoveryRouteToCoreBridge()
    {
        string mainWindow = File.ReadAllText(RepositoryPath("apps/windows/AreaMatrix/MainWindow.xaml.cs"));
        string mainWindowXaml = File.ReadAllText(RepositoryPath("apps/windows/AreaMatrix/MainWindow.xaml"));
        string libraryView = File.ReadAllText(RepositoryPath(
            "apps/windows/AreaMatrix/Features/Library/WindowsMainWindow.xaml"));
        string libraryCode = File.ReadAllText(RepositoryPath(
            "apps/windows/AreaMatrix/Features/Library/WindowsMainWindow.xaml.cs"));
        string dialog = File.ReadAllText(RepositoryPath(
            "apps/windows/AreaMatrix/Features/Recovery/MissingFileRecoveryDialog.xaml.cs"));
        string bridge = File.ReadAllText(RepositoryPath(
            "apps/windows/AreaMatrix/Features/Recovery/MissingFileRecoveryCoreBridge.cs"));

        TestAssert.Contains("DetailMissingFileRecoveryButton", libraryView, "detail recovery action");
        TestAssert.Contains("OpenMissingFileRecoveryRequested", libraryCode + mainWindow, "recovery route event");
        TestAssert.Contains("MissingFileRecoveryPage", mainWindowXaml + mainWindow, "recovery page host");
        TestAssert.Contains("new MissingFileRecoveryCoreBridge(coreClient)", mainWindow, "real core bridge");
        TestAssert.Contains("GetMissingFileStateAsync", bridge, "C4-18 state call");
        TestAssert.Contains("RelinkMissingFileAsync", bridge + dialog, "C4-18 relink call");
        TestAssert.Contains("RemoveMissingFileRecordAsync", bridge + dialog, "C4-18 remove call");
        TestAssert.DoesNotContain("ReindexFromFilesystemAsync", dialog, "C4-18 must not run rescan");
        TestAssert.DoesNotContain("PreviewManualRescanAsync", dialog, "C4-18 must not preview rescan");
    }

    private static MissingFileRecoveryState State(long fileId)
    {
        return new MissingFileRecoveryState(
            fileId,
            @"docs\report.pdf",
            @"C:\Repos\AreaMatrix\docs\report.pdf",
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
            @"docs\report.pdf",
            status == MissingFileRecoveryStatus.Relinked ? @"C:\Selected\report.pdf" : null,
            hashMatched,
            recordRemoved,
            fileDeleted,
            changeLogAction,
            null);
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

    private sealed class RecordingMissingFileRecoveryCoreClient : IAreaMatrixMissingFileRecoveryCoreClient
    {
        public CoreMissingFileRemoveRecordRequest? LastRemoveRequest { get; private set; }

        public Task<CoreMissingFileState> GetMissingFileStateAsync(
            string repoPath,
            long fileId,
            CancellationToken cancellationToken = default)
        {
            return Task.FromResult(new CoreMissingFileState(
                fileId,
                @"docs\report.pdf",
                @"C:\Repo\docs\report.pdf",
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
                @"docs\report.pdf",
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
                @"docs\report.pdf",
                null,
                false,
                true,
                false,
                "missing_file_record_removed",
                null));
        }
    }
}
