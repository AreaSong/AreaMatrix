using AreaMatrix.Features.Import;
using AreaMatrix.Features.Library;
using AreaMatrixTests.ChooseRepository;

namespace AreaMatrixTests.Import;

public static class WindowsImportViewModelTests
{
    public static async Task RunAllAsync()
    {
        await PreparingPreviewUsesCorePredictCategoryForEachSource();
        await CoreBridgeMarksUnreadablePreviewWithoutCorePredictCall();
        await CoreBridgeMarksDuplicateAndNameConflictPreviewStatuses();
        await CoreBridgeMarksNameConflictReplaceBlockedWithoutCoreSession();
        await CopyImportCommitsThroughCoreImportFileWithResult();
        await FolderImportCanPreserveRelativeDirectoryThroughCoreOptions();
        await UnreadablePreviewItemDoesNotCommitImport();
        await DuplicatePreviewItemDoesNotCommitImport();
        await DuplicatePreviewCanImportWithKeepBothStrategy();
        await NameConflictImportsWithKeepBothByDefault();
        await MoveImportRequiresExplicitConfirmation();
        await MovePreflightFailureBlocksMoveImport();
        await WindowsFileProbeRequiresWritableStagingForMovePreflight();
        await MoveRetainedResultKeepsImportedFileAndReportsOriginalRetained();
        await FailedImportStaysOnResultPageAndCanRetry();
        await ImportCloseRequestCarriesImportedFileIds();
    }

    private static async Task PreparingPreviewUsesCorePredictCategoryForEachSource()
    {
        FakeDesktopImportCoreBridge bridge = new();
        WindowsImportViewModel model = new(bridge);
        model.OpenRepository(@"C:\Repos\AreaMatrix");
        model.SourcePathsText = @"C:\Users\me\Downloads\report.pdf";

        await model.PreparePreviewAsync();

        TestAssert.SequenceEqual([@"C:\Users\me\Downloads\report.pdf"], bridge.PreviewRequests, "preview requests");
        TestAssert.Empty(bridge.ImportRequests, nameof(bridge.ImportRequests));
        TestAssert.Equal("finance", model.PreviewItems[0].SuggestedCategory, "suggested category");
        TestAssert.True(model.CanImport, nameof(model.CanImport));
    }

    private static async Task CoreBridgeMarksUnreadablePreviewWithoutCorePredictCall()
    {
        RecordingDesktopImportCoreClient coreClient = new();
        DesktopImportCoreBridge bridge = new(
            coreClient,
            new StaticWindowsImportFileProbe(isReadable: false));

        DesktopImportPreviewItem item = await bridge.PredictImportAsync(
            @"C:\Repos\AreaMatrix",
            @"C:\Users\me\Downloads\missing.pdf");

        TestAssert.Equal(DesktopImportPreviewStatus.Unreadable, item.Status, "preview status");
        TestAssert.Empty(coreClient.PredictedFilenames, nameof(coreClient.PredictedFilenames));
    }

    private static async Task CoreBridgeMarksDuplicateAndNameConflictPreviewStatuses()
    {
        string root = CreateTempDirectory();
        try
        {
            string repo = Path.Combine(root, "repo");
            string source = Path.Combine(root, "sources");
            Directory.CreateDirectory(Path.Combine(repo, ".areamatrix", "staging"));
            Directory.CreateDirectory(Path.Combine(repo, "finance"));
            Directory.CreateDirectory(source);

            string duplicateSource = Path.Combine(source, "duplicate.pdf");
            string nameConflictSource = Path.Combine(source, "report.pdf");
            await File.WriteAllTextAsync(duplicateSource, "same-content");
            await File.WriteAllTextAsync(Path.Combine(repo, "finance", "existing.pdf"), "same-content");
            await File.WriteAllTextAsync(nameConflictSource, "incoming-content");
            await File.WriteAllTextAsync(Path.Combine(repo, "finance", "report.pdf"), "existing-content");

            DesktopImportCoreBridge bridge = new(
                new RecordingDesktopImportCoreClient(),
                new WindowsImportFileProbe());

            DesktopImportPreviewItem duplicate = await bridge.PredictImportAsync(repo, duplicateSource);
            DesktopImportPreviewItem nameConflict = await bridge.PredictImportAsync(repo, nameConflictSource);

            TestAssert.Equal(DesktopImportPreviewStatus.Duplicate, duplicate.Status, "duplicate status");
            TestAssert.Equal(DesktopImportPreviewStatus.NameConflict, nameConflict.Status, "name conflict status");
            TestAssert.Equal("Duplicate", duplicate.StatusText, "duplicate status text");
            TestAssert.Equal("Name conflict", nameConflict.StatusText, "name conflict status text");
        }
        finally
        {
            Directory.Delete(root, recursive: true);
        }
    }

    private static async Task CoreBridgeMarksNameConflictReplaceBlockedWithoutCoreSession()
    {
        string root = CreateTempDirectory();
        try
        {
            string repo = Path.Combine(root, "repo");
            string source = Path.Combine(root, "sources");
            Directory.CreateDirectory(Path.Combine(repo, ".areamatrix", "staging"));
            Directory.CreateDirectory(Path.Combine(repo, "finance"));
            Directory.CreateDirectory(source);

            string nameConflictSource = Path.Combine(source, "report.pdf");
            string existing = Path.Combine(repo, "finance", "report.pdf");
            await File.WriteAllTextAsync(nameConflictSource, "incoming-content");
            await File.WriteAllTextAsync(existing, "existing-content");

            DesktopImportCoreBridge bridge = new(
                new RecordingDesktopImportCoreClient(),
                new WindowsImportFileProbe());

            DesktopImportPreviewItem item = await bridge.PredictImportAsync(repo, nameConflictSource);

            TestAssert.Equal(DesktopImportPreviewStatus.NameConflict, item.Status, "name conflict status");
            TestAssert.True(item.HasNameConflictWithoutCoreSession, nameof(item.HasNameConflictWithoutCoreSession));
            TestAssert.False(item.CanPreviewReplace, nameof(item.CanPreviewReplace));
            TestAssert.False(item.ReplacePreflightAvailable, nameof(item.ReplacePreflightAvailable));
            TestAssert.Equal(existing, item.ExistingPath, nameof(item.ExistingPath));
            TestAssert.Contains(
                "Core import conflict preview",
                item.ReplaceBlockedReason ?? string.Empty,
                nameof(item.ReplaceBlockedReason));
        }
        finally
        {
            Directory.Delete(root, recursive: true);
        }
    }


    private static async Task CopyImportCommitsThroughCoreImportFileWithResult()
    {
        FakeDesktopImportCoreBridge bridge = new();
        WindowsImportViewModel model = new(bridge);
        model.OpenRepository(@"C:\Repos\AreaMatrix");
        model.SourcePathsText = @"C:\Users\me\Downloads\report.pdf";

        await model.PreparePreviewAsync();
        await model.ImportAsync();

        TestAssert.SequenceEqual([@"C:\Users\me\Downloads\report.pdf"], bridge.ImportRequests, "import requests");
        TestAssert.Equal(DesktopImportMode.Copy, bridge.LastRequest?.Mode, "import mode");
        TestAssert.Equal(DesktopImportDuplicateStrategy.Skip, bridge.LastRequest?.DuplicateStrategy, "duplicate strategy");
        TestAssert.Equal("Imported 1 item(s)", model.ResultSummaryText, nameof(model.ResultSummaryText));
        TestAssert.Null(model.Error, nameof(model.Error));
    }

    private static async Task FolderImportCanPreserveRelativeDirectoryThroughCoreOptions()
    {
        FakeDesktopImportCoreBridge bridge = new();
        WindowsImportViewModel model = new(bridge);
        model.OpenRepository(@"C:\Repos\AreaMatrix");
        model.SetSources([
            new DesktopImportSource(
                @"C:\Users\me\Downloads\folder\2026\report.pdf",
                @"C:\Users\me\Downloads\folder",
                @"2026")
        ]);
        model.TargetDirectory = "imports";
        model.PreserveFolderStructure = true;

        await model.PreparePreviewAsync();
        await model.ImportAsync();

        TestAssert.True(model.HasFolderSources, nameof(model.HasFolderSources));
        TestAssert.Equal(DesktopImportDestination.SelectedDirectory, bridge.LastRequest?.Destination, "destination");
        TestAssert.Equal(@"imports/2026", bridge.LastRequest?.TargetDirectory, "target directory");
    }

    private static async Task UnreadablePreviewItemDoesNotCommitImport()
    {
        FakeDesktopImportCoreBridge bridge = new()
        {
            PreviewStatus = DesktopImportPreviewStatus.Unreadable
        };
        WindowsImportViewModel model = new(bridge);
        model.OpenRepository(@"C:\Repos\AreaMatrix");
        model.SourcePathsText = @"C:\Users\me\Downloads\missing.pdf";

        await model.PreparePreviewAsync();
        await model.ImportAsync();

        TestAssert.Equal(DesktopImportPreviewStatus.Unreadable, model.PreviewItems[0].Status, "preview status");
        TestAssert.False(model.CanImport, nameof(model.CanImport));
        TestAssert.Empty(bridge.ImportRequests, nameof(bridge.ImportRequests));
    }

    private static async Task DuplicatePreviewItemDoesNotCommitImport()
    {
        FakeDesktopImportCoreBridge bridge = new()
        {
            PreviewStatus = DesktopImportPreviewStatus.Duplicate
        };
        WindowsImportViewModel model = new(bridge);
        model.OpenRepository(@"C:\Repos\AreaMatrix");
        model.SourcePathsText = @"C:\Users\me\Downloads\duplicate.pdf";

        await model.PreparePreviewAsync();
        await model.ImportAsync();

        TestAssert.Equal(DesktopImportPreviewStatus.Duplicate, model.PreviewItems[0].Status, "preview status");
        TestAssert.False(model.CanImport, nameof(model.CanImport));
        TestAssert.Empty(bridge.ImportRequests, nameof(bridge.ImportRequests));
    }

    private static async Task DuplicatePreviewCanImportWithKeepBothStrategy()
    {
        FakeDesktopImportCoreBridge bridge = new()
        {
            PreviewStatus = DesktopImportPreviewStatus.Duplicate
        };
        WindowsImportViewModel model = new(bridge);
        model.OpenRepository(@"C:\Repos\AreaMatrix");
        model.SourcePathsText = @"C:\Users\me\Downloads\duplicate.pdf";
        model.DuplicateStrategy = DesktopImportDuplicateStrategy.KeepBoth;

        await model.PreparePreviewAsync();
        await model.ImportAsync();

        TestAssert.True(model.CanImport, nameof(model.CanImport));
        TestAssert.SequenceEqual([@"C:\Users\me\Downloads\duplicate.pdf"], bridge.ImportRequests, "import requests");
        TestAssert.Equal(DesktopImportDuplicateStrategy.KeepBoth, bridge.LastRequest?.DuplicateStrategy, "duplicate strategy");
    }

    private static async Task NameConflictImportsWithKeepBothByDefault()
    {
        FakeDesktopImportCoreBridge bridge = new()
        {
            PreviewStatus = DesktopImportPreviewStatus.NameConflict
        };
        WindowsImportViewModel model = new(bridge);
        model.OpenRepository(@"C:\Repos\AreaMatrix");
        model.SourcePathsText = @"C:\Users\me\Downloads\report.pdf";

        await model.PreparePreviewAsync();
        await model.ImportAsync();

        TestAssert.True(model.CanImport, nameof(model.CanImport));
        TestAssert.SequenceEqual([@"C:\Users\me\Downloads\report.pdf"], bridge.ImportRequests, "import requests");
        TestAssert.Equal(
            DesktopImportDuplicateStrategy.KeepBoth,
            bridge.LastRequest?.DuplicateStrategy,
            "same-name conflict strategy");
        TestAssert.Empty(bridge.ReplaceApplyRequests, nameof(bridge.ReplaceApplyRequests));
    }

    private static async Task MoveImportRequiresExplicitConfirmation()
    {
        FakeDesktopImportCoreBridge bridge = new();
        WindowsImportViewModel model = new(bridge);
        model.OpenRepository(@"C:\Repos\AreaMatrix");
        model.SourcePathsText = @"C:\Users\me\Downloads\report.pdf";
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
            MovePreflight = new DesktopImportMovePreflight(false, ["staging directory is not available"])
        };
        WindowsImportViewModel model = new(bridge);
        model.OpenRepository(@"C:\Repos\AreaMatrix");
        model.SourcePathsText = @"C:\Users\me\Downloads\report.pdf";
        model.Mode = DesktopImportMode.Move;

        await model.PreparePreviewAsync();
        model.MoveConfirmed = true;
        await model.ImportAsync();

        TestAssert.False(model.CanImport, nameof(model.CanImport));
        TestAssert.Contains("Use Copy instead", model.MovePreflightText, nameof(model.MovePreflightText));
        TestAssert.Empty(bridge.ImportRequests, nameof(bridge.ImportRequests));
    }

    private static async Task WindowsFileProbeRequiresWritableStagingForMovePreflight()
    {
        string root = CreateTempDirectory();
        try
        {
            string repo = Path.Combine(root, "repo");
            string sourceDirectory = Path.Combine(root, "sources");
            string source = Path.Combine(sourceDirectory, "report.pdf");
            Directory.CreateDirectory(repo);
            Directory.CreateDirectory(sourceDirectory);
            await File.WriteAllTextAsync(source, "source");

            WindowsImportFileProbe probe = new();
            DesktopImportPreviewItem item = new(
                source,
                "report.pdf",
                "PDF",
                "6 B",
                "finance",
                "report.pdf",
                DesktopImportPreviewStatus.Ready);

            DesktopImportMovePreflight preflight = probe.CheckMovePreflight(repo, [item]);

            TestAssert.False(preflight.CanMove, nameof(preflight.CanMove));
            TestAssert.Contains(
                "staging directory is not available",
                preflight.StatusText,
                nameof(preflight.StatusText));
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
            Result = ImportResult(DesktopImportSourceRemovalStatus.Retained, "source permission denied")
        };
        WindowsImportViewModel model = new(bridge);
        model.OpenRepository(@"C:\Repos\AreaMatrix");
        model.SourcePathsText = @"C:\Users\me\Downloads\report.pdf";
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
        WindowsImportViewModel model = new(bridge);
        model.OpenRepository(@"C:\Repos\AreaMatrix");
        model.SourcePathsText = @"C:\Users\me\Downloads\report.pdf";

        await model.PreparePreviewAsync();
        await model.ImportAsync();

        TestAssert.Equal(1, model.Results.Count, "result count");
        TestAssert.True(model.HasFailedResults, nameof(model.HasFailedResults));
        TestAssert.False(model.HasSuccessfulResults, nameof(model.HasSuccessfulResults));
        TestAssert.True(model.Results[0].CanRetry, "failed result can retry");
        TestAssert.True(model.Results[0].CanShowDetails, "failed result details");
        TestAssert.Contains("duplicate content", model.Results[0].DetailText, "failure details");
        TestAssert.Contains("0 item(s), 1 failed", model.ResultSummaryText, nameof(model.ResultSummaryText));

        bridge.ImportException = null;
        await model.RetryFailedAsync(model.Results[0]);

        TestAssert.True(model.HasSuccessfulResults, nameof(model.HasSuccessfulResults));
        TestAssert.False(model.HasFailedResults, nameof(model.HasFailedResults));
        TestAssert.Equal(1, bridge.ImportRequests.Count, "retry import count");
        TestAssert.Equal(1, model.ImportedFileIds.Count, nameof(model.ImportedFileIds));
    }

    private static async Task ImportCloseRequestCarriesImportedFileIds()
    {
        FakeDesktopImportCoreBridge bridge = new()
        {
            Result = ImportResult(DesktopImportSourceRemovalStatus.Retained, "source permission denied")
        };
        WindowsImportViewModel model = new(bridge);
        model.OpenRepository(@"C:\Repos\AreaMatrix");
        model.SourcePathsText = @"C:\Users\me\Downloads\report.pdf";
        model.Mode = DesktopImportMode.Move;
        model.MoveConfirmed = true;

        await model.PreparePreviewAsync();
        await model.ImportAsync();

        WindowsImportCloseRequest request = model.CreateCloseRequest();
        TestAssert.True(request.ShouldRefreshMainWindow, nameof(request.ShouldRefreshMainWindow));
        TestAssert.SequenceEqual([1L], request.ImportedFileIds, nameof(request.ImportedFileIds));
        TestAssert.True(model.Results[0].CanShowOriginal, "retained original action");
        TestAssert.True(model.Results[0].CanShowImportedFile, "imported file action");
    }

    private static DesktopImportResult ImportResult(
        DesktopImportSourceRemovalStatus status = DesktopImportSourceRemovalStatus.NotRequested,
        string? failure = null)
    {
        return new DesktopImportResult(
            FileEntry(1, "report.pdf"),
            @"C:\Users\me\Downloads\report.pdf",
            status,
            failure);
    }

    private static DesktopFileEntry FileEntry(long id, string name)
    {
        return new DesktopFileEntry(
            id,
            $@"finance\{name}",
            name,
            name,
            "finance",
            2048,
            $"hash-{id}",
            DesktopStorageMode.Copied,
            DesktopFileOrigin.Imported,
            null,
            DesktopFileAvailabilityStatus.Available,
            1_700_000_000,
            1_700_000_100);
    }

    private static string CreateTempDirectory()
    {
        string path = Path.Combine(Path.GetTempPath(), $"areamatrix-win-import-{Guid.NewGuid():N}");
        Directory.CreateDirectory(path);
        return path;
    }
}
