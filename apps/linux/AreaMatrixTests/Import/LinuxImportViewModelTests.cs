using AreaMatrix.Linux.Features.Import;
using AreaMatrix.Linux.Tests.ChooseRepository;

namespace AreaMatrix.Linux.Tests.Import;

public static class LinuxImportViewModelTests
{
    public static async Task RunAllAsync()
    {
        await PreparingPreviewUsesCorePredictCategoryForEachSource();
        await CoreBridgeMarksUnreadablePreviewWithoutCorePredictCall();
        await LinuxImportDialogAddFilesAndDropActionsTriggerPreviewAndImport();
        await CopyImportCommitsThroughCoreImportFileWithResult();
        await DuplicatePreviewDoesNotCommitImportUnlessKeepBoth();
        await NameConflictImportsWithKeepBothByDefault();
        await MoveImportRequiresExplicitConfirmation();
        await MovePreflightFailureBlocksMoveImport();
        LinuxFileProbeReportsUnknownMountWhenMountInfoCannotMapPath();
        await MoveRetainedResultKeepsImportedFileAndReportsOriginalRetained();
        await FailedImportStaysOnResultPageAndCanRetry();
        ImportCloseRequestCarriesImportedFileIds();
    }

    private static async Task PreparingPreviewUsesCorePredictCategoryForEachSource()
    {
        FakeDesktopImportCoreBridge bridge = new();
        LinuxImportViewModel model = new(bridge);
        model.OpenRepository("/home/me/AreaMatrix");
        model.SourcePathsText = "/home/me/Downloads/report.pdf";

        await model.PreparePreviewAsync();

        TestAssert.SequenceEqual(["/home/me/Downloads/report.pdf"], bridge.PreviewRequests, "preview requests");
        TestAssert.Empty(bridge.ImportRequests, nameof(bridge.ImportRequests));
        TestAssert.Equal("finance", model.PreviewItems[0].SuggestedCategory, "suggested category");
        TestAssert.True(model.CanImport, nameof(model.CanImport));
    }

    private static async Task CoreBridgeMarksUnreadablePreviewWithoutCorePredictCall()
    {
        RecordingDesktopImportCoreClient coreClient = new();
        DesktopImportCoreBridge bridge = new(
            coreClient,
            new StaticLinuxImportFileProbe(isReadable: false));

        DesktopImportPreviewItem item = await bridge.PredictImportAsync(
            "/home/me/AreaMatrix",
            "/home/me/Downloads/missing.pdf");

        TestAssert.Equal(DesktopImportPreviewStatus.PermissionDenied, item.Status, "preview status");
        TestAssert.Empty(coreClient.PredictedFilenames, nameof(coreClient.PredictedFilenames));
    }

    private static async Task LinuxImportDialogAddFilesAndDropActionsTriggerPreviewAndImport()
    {
        FakeDesktopImportCoreBridge bridge = new();
        FakeLinuxImportPickerAdapter picker = new()
        {
            FilePaths = ["/home/me/Downloads/report.pdf"]
        };
        LinuxImportDialog dialog = new(
            new LinuxImportViewModel(bridge),
            new StaticLinuxImportFileProbe(isReadable: true),
            picker);
        dialog.OpenRepository("/home/me/AreaMatrix");

        await dialog.AddFilesAsync();

        TestAssert.SequenceEqual(["/home/me/Downloads/report.pdf"], bridge.PreviewRequests, "add files preview");
        TestAssert.True(dialog.ViewModel.CanImport, "dialog can import selected file");

        dialog.SetImportMode(DesktopImportMode.Move);
        dialog.ConfirmMoveOriginals(true);
        await dialog.ImportAsync();

        TestAssert.Equal(DesktopImportMode.Move, bridge.LastRequest?.Mode, "dialog move mode");
        TestAssert.True(bridge.LastRequest?.MoveConfirmed == true, "dialog move confirmed");

        await dialog.DropPathsAsync(["/home/me/Downloads/notes.txt"]);

        TestAssert.SequenceEqual(
            ["/home/me/Downloads/report.pdf", "/home/me/Downloads/notes.txt"],
            dialog.ViewModel.SourcePathsText.Split('\n', StringSplitOptions.TrimEntries),
            "drop appends source selection");
        TestAssert.SequenceEqual(
            ["/home/me/Downloads/report.pdf", "/home/me/Downloads/report.pdf", "/home/me/Downloads/notes.txt"],
            bridge.PreviewRequests,
            "drop path preview");
    }

    private static async Task CopyImportCommitsThroughCoreImportFileWithResult()
    {
        FakeDesktopImportCoreBridge bridge = new();
        LinuxImportViewModel model = new(bridge);
        model.OpenRepository("/home/me/AreaMatrix");
        model.SourcePathsText = "/home/me/Downloads/report.pdf";

        await model.PreparePreviewAsync();
        await model.ImportAsync();

        TestAssert.SequenceEqual(["/home/me/Downloads/report.pdf"], bridge.ImportRequests, "import requests");
        TestAssert.Equal(DesktopImportMode.Copy, bridge.LastRequest?.Mode, "import mode");
        TestAssert.Equal(DesktopImportDuplicateStrategy.Skip, bridge.LastRequest?.DuplicateStrategy, "duplicate strategy");
        TestAssert.Equal("Imported 1 item(s)", model.ResultSummaryText, nameof(model.ResultSummaryText));
        TestAssert.Null(model.Error, nameof(model.Error));
    }

    private static async Task DuplicatePreviewDoesNotCommitImportUnlessKeepBoth()
    {
        FakeDesktopImportCoreBridge bridge = new()
        {
            PreviewStatus = DesktopImportPreviewStatus.Duplicate
        };
        LinuxImportViewModel model = new(bridge);
        model.OpenRepository("/home/me/AreaMatrix");
        model.SourcePathsText = "/home/me/Downloads/duplicate.pdf";

        await model.PreparePreviewAsync();
        await model.ImportAsync();

        TestAssert.False(model.CanImport, nameof(model.CanImport));
        TestAssert.Empty(bridge.ImportRequests, nameof(bridge.ImportRequests));

        model.DuplicateStrategy = DesktopImportDuplicateStrategy.KeepBoth;
        await model.ImportAsync();

        TestAssert.SequenceEqual(["/home/me/Downloads/duplicate.pdf"], bridge.ImportRequests, "keep both import");
        TestAssert.Equal(DesktopImportDuplicateStrategy.KeepBoth, bridge.LastRequest?.DuplicateStrategy, "strategy");
    }

    private static async Task NameConflictImportsWithKeepBothByDefault()
    {
        FakeDesktopImportCoreBridge bridge = new()
        {
            PreviewStatus = DesktopImportPreviewStatus.NameConflict
        };
        LinuxImportViewModel model = new(bridge);
        model.OpenRepository("/home/me/AreaMatrix");
        model.SourcePathsText = "/home/me/Downloads/report.pdf";

        await model.PreparePreviewAsync();
        await model.ImportAsync();

        TestAssert.True(model.CanImport, nameof(model.CanImport));
        TestAssert.Equal(
            DesktopImportDuplicateStrategy.KeepBoth,
            bridge.LastRequest?.DuplicateStrategy,
            "same-name conflict strategy");
    }

    private static async Task MoveImportRequiresExplicitConfirmation()
    {
        FakeDesktopImportCoreBridge bridge = new();
        LinuxImportViewModel model = new(bridge);
        model.OpenRepository("/home/me/AreaMatrix");
        model.SourcePathsText = "/home/me/Downloads/report.pdf";
        model.Mode = DesktopImportMode.Move;

        await model.PreparePreviewAsync();

        TestAssert.False(model.CanImport, nameof(model.CanImport));
        TestAssert.Empty(bridge.ImportRequests, nameof(bridge.ImportRequests));

        model.MoveConfirmed = true;
        await model.ImportAsync();

        TestAssert.Equal(DesktopImportMode.Move, bridge.LastRequest?.Mode, "move request");
        TestAssert.True(bridge.LastRequest?.MoveConfirmed == true, "move confirmed");
    }

    private static async Task MovePreflightFailureBlocksMoveImport()
    {
        FakeDesktopImportCoreBridge bridge = new()
        {
            MovePreflight = new DesktopImportMovePreflight(false, ["staging directory is not available"], "unknown")
        };
        LinuxImportViewModel model = new(bridge);
        model.OpenRepository("/home/me/AreaMatrix");
        model.SourcePathsText = "/home/me/Downloads/report.pdf";
        model.Mode = DesktopImportMode.Move;

        await model.PreparePreviewAsync();
        model.MoveConfirmed = true;
        await model.ImportAsync();

        TestAssert.False(model.CanImport, nameof(model.CanImport));
        TestAssert.Contains("Use Copy instead", model.MovePreflightText, nameof(model.MovePreflightText));
        TestAssert.Empty(bridge.ImportRequests, nameof(bridge.ImportRequests));
    }

    private static void LinuxFileProbeReportsUnknownMountWhenMountInfoCannotMapPath()
    {
        string root = CreateTempDirectory();
        try
        {
            string repo = Path.Combine(root, "repo");
            string sourceDirectory = Path.Combine(root, "sources");
            string source = Path.Combine(sourceDirectory, "report.pdf");
            Directory.CreateDirectory(Path.Combine(repo, ".areamatrix", "staging"));
            Directory.CreateDirectory(sourceDirectory);
            File.WriteAllText(source, "source");

            LinuxImportFileProbe probe = new();
            DesktopImportPreviewItem item = new(
                source,
                "report.pdf",
                "PDF",
                "6 B",
                "docs",
                "report.pdf",
                DesktopImportPreviewStatus.Ready);

            DesktopImportMovePreflight preflight = probe.CheckMovePreflight(repo, [item]);

            TestAssert.True(
                preflight.MountText is "same mount" or "different mount" or "unknown",
                "mount text is structured");
            TestAssert.False(preflight.MountText.Contains("different mount / unknown", StringComparison.Ordinal), "no mixed mount state");
        }
        finally
        {
            Directory.Delete(root, recursive: true);
        }
    }

    private static async Task MoveRetainedResultKeepsImportedFileAndReportsOriginalRetained()
    {
        FakeDesktopImportCoreBridge bridge = new()
        {
            Result = FakeDesktopImportCoreBridge.ImportResult(
                DesktopImportSourceRemovalStatus.Retained,
                "source permission denied")
        };
        LinuxImportViewModel model = new(bridge);
        model.OpenRepository("/home/me/AreaMatrix");
        model.SourcePathsText = "/home/me/Downloads/report.pdf";
        model.Mode = DesktopImportMode.Move;
        model.MoveConfirmed = true;

        await model.PreparePreviewAsync();
        await model.ImportAsync();

        TestAssert.Contains("original(s) retained", model.ResultSummaryText, nameof(model.ResultSummaryText));
        TestAssert.Equal(
            DesktopImportSourceRemovalStatus.Retained,
            model.Results[0].SourceRemovalStatus,
            "source removal status");
        TestAssert.Contains("source permission denied", model.Results[0].DetailText, "result detail text");
    }

    private static async Task FailedImportStaysOnResultPageAndCanRetry()
    {
        FakeDesktopImportCoreBridge bridge = new()
        {
            ImportException = new DesktopImportCoreException(
                DesktopImportErrorKind.DuplicateFile,
                "duplicate content")
        };
        LinuxImportViewModel model = new(bridge);
        model.OpenRepository("/home/me/AreaMatrix");
        model.SourcePathsText = "/home/me/Downloads/report.pdf";

        await model.PreparePreviewAsync();
        await model.ImportAsync();

        TestAssert.True(model.HasFailedResults, nameof(model.HasFailedResults));
        TestAssert.Equal("Imported 0 item(s), 1 failed.", model.ResultSummaryText, nameof(model.ResultSummaryText));
        TestAssert.Contains("duplicate content", model.Results[0].DetailText, "failed detail");

        bridge.ImportException = null;
        await model.RetryFailedAsync(model.Results[0]);

        TestAssert.True(model.HasSuccessfulResults, nameof(model.HasSuccessfulResults));
        TestAssert.Equal("Imported 1 item(s)", model.ResultSummaryText, "retry result summary");
    }

    private static void ImportCloseRequestCarriesImportedFileIds()
    {
        LinuxImportCloseRequest request = new([7, 9]);

        TestAssert.True(request.ShouldRefreshMainWindow, "close request refresh");
        TestAssert.SequenceEqual([7, 9], request.ImportedFileIds, "imported ids");

        FakeDesktopImportCoreBridge bridge = new();
        LinuxImportViewModel model = new(bridge);
        model.OpenRepository("/home/me/AreaMatrix");
        model.SourcePathsText = "/home/me/Downloads/report.pdf";

        TestAssert.False(model.CreateCloseRequest().ShouldRefreshMainWindow, "empty close request");
    }

    private static string CreateTempDirectory()
    {
        string path = Path.Combine(Path.GetTempPath(), $"areamatrix-lnx-import-{Guid.NewGuid():N}");
        Directory.CreateDirectory(path);
        return path;
    }
}
