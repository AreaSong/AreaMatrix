using AreaMatrix.Linux.Features.Conflicts;
using AreaMatrix.Linux.Features.Library;
using AreaMatrix.Linux.Features.Onboarding;
using AreaMatrix.Linux.Tests.ChooseRepository;

namespace AreaMatrix.Linux.Tests.Library;

public static class LinuxSyncConflictEntryPageFeatureTests
{
    public static async Task RunAllAsync()
    {
        await LoadsNeedsReviewConflictsFromCoreBridge();
        await LaterDismissesBannerAndKeepsNeedsReviewList();
        await ReviewRouteUsesStableConflictId();
        await MissingConflictIdDisablesReviewRoute();
        await DetailConflictMatchesSelectedFile();
        await ErrorStateMapsCoreConflictError();
        await ReviewRoutePreviewsConfirmsAndAppliesReplace();
        await CoreSafetyBackupAllowsReplaceWhenTrashUnavailable();
        await ReplacePlanTextShowsCompleteS4X09Fields();
        LinuxMainWindowSmokeExposesS4X03C415Entry();
        LinuxDesktopShellWiresS4X03ToRealCoreBridge();
    }

    private static async Task LoadsNeedsReviewConflictsFromCoreBridge()
    {
        FakeSyncConflictEntryCoreBridge syncBridge = new([
            Conflict("resolved", status: SyncConflictEntryStatus.Resolved),
            Conflict("needs-review", primaryPath: "Contracts/review.pdf")
        ]);
        LinuxMainWindowViewModel model = new(new FakeDesktopMainQueryCoreBridge(), syncBridge);

        await model.OpenRepositoryAsync(Route("/home/me/AreaMatrix"));

        TestAssert.SequenceEqual(["/home/me/AreaMatrix"], syncBridge.Requests, "detect requests");
        TestAssert.Equal(1, model.SyncConflictEntry?.Conflicts.Count, "needs review count");
        TestAssert.Equal("needs-review", model.SyncConflictEntry?.Conflicts[0].ConflictId, "conflict id");
        TestAssert.True(model.SyncConflictEntry?.IsBannerVisible ?? false, "banner visible");
    }

    private static async Task LaterDismissesBannerAndKeepsNeedsReviewList()
    {
        FakeSyncConflictEntryCoreBridge syncBridge = new([Conflict("later")]);
        SyncConflictEntryViewModel model = new(syncBridge);

        await model.OpenRepositoryAsync("/home/me/AreaMatrix");
        model.DismissBanner();

        TestAssert.False(model.IsBannerVisible, "banner dismissed");
        TestAssert.Equal(1, model.Conflicts.Count, "list retained");
        TestAssert.Equal(SyncConflictEntryStatus.NeedsReview, model.Conflicts[0].Status, "status retained");
    }

    private static async Task ReviewRouteUsesStableConflictId()
    {
        FakeSyncConflictEntryCoreBridge syncBridge = new([Conflict("route", primaryPath: "Docs/route.md")]);
        SyncConflictEntryViewModel model = new(syncBridge);

        await model.OpenRepositoryAsync("/home/me/AreaMatrix");
        SyncConflictEntryReviewRoute? route = model.ReviewRouteFor(model.FirstReviewableConflict);

        TestAssert.Equal("/home/me/AreaMatrix", route?.RepoPath, "route repo");
        TestAssert.Equal("route", route?.ConflictId, "route conflict");
        TestAssert.Equal("Docs/route.md", route?.PrimaryPath, "route path");
    }

    private static async Task MissingConflictIdDisablesReviewRoute()
    {
        FakeSyncConflictEntryCoreBridge syncBridge = new([Conflict("   ")]);
        SyncConflictEntryViewModel model = new(syncBridge);

        await model.OpenRepositoryAsync("/home/me/AreaMatrix");

        TestAssert.Null(model.FirstReviewableConflict, "first reviewable");
        TestAssert.Null(model.ReviewRouteFor(model.Conflicts[0]), "route");
        TestAssert.Equal("Repair index first", ReadSyncConflictEntryUiFragment("disabled_review"), "repair copy");
    }

    private static async Task DetailConflictMatchesSelectedFile()
    {
        SyncConflictEntryConflict conflict = Conflict(
            "detail",
            primaryPath: "Contracts/client-contract-1.pdf",
            affectedFiles:
            [
                new SyncConflictEntryAffectedFile(
                    "Contracts/client-contract-1.pdf",
                    1,
                    SyncConflictEntryFileRole.Existing,
                    2048,
                    1_700_000_100,
                    "hash-1",
                    "Linux")
            ]);
        FakeSyncConflictEntryCoreBridge syncBridge = new([conflict]);
        LinuxMainWindowViewModel model = new(new FakeDesktopMainQueryCoreBridge(), syncBridge);

        await model.OpenRepositoryAsync(Route("/home/me/AreaMatrix"));
        await model.SelectFileAsync(model.Files[0]);

        TestAssert.Equal("detail", model.SelectedFileSyncConflict?.ConflictId, "selected conflict");
        TestAssert.Contains("This file has a sync conflict", ReadSyncConflictEntryUi(), "detail banner");
    }

    private static async Task ErrorStateMapsCoreConflictError()
    {
        FakeSyncConflictEntryCoreBridge syncBridge = new(
            new LinuxRepositoryCoreException(
                LinuxRepositoryErrorKind.Conflict,
                "conflict metadata changed"));
        SyncConflictEntryViewModel model = new(syncBridge);

        await model.OpenRepositoryAsync("/home/me/AreaMatrix");

        TestAssert.Equal(SyncConflictEntryErrorKind.Conflict, model.Error?.Kind, "error kind");
        TestAssert.Equal("Could not load review items", model.StatusText, "status text");
        TestAssert.Contains("Try again", model.Error?.SuggestedAction ?? "", "retry action");
    }

    private static async Task ReviewRoutePreviewsConfirmsAndAppliesReplace()
    {
        FakeSyncConflictEntryCoreBridge syncBridge = new([
            Conflict("replace", primaryPath: "Contracts/client-contract-1.pdf")
        ]);
        SyncConflictEntryViewModel model = new(syncBridge);

        await model.OpenRepositoryAsync("/home/me/AreaMatrix");
        SyncConflictEntryReviewRoute route = model.ReviewRouteFor(model.FirstReviewableConflict)
            ?? throw new InvalidOperationException("review route missing");

        await model.OpenReviewRouteAsync(route);
        model.ConfirmReplacePlan(true);
        await model.ApplyReplaceAsync();

        TestAssert.Equal(1, syncBridge.PreviewRequests.Count, "preview request count");
        TestAssert.Equal("/home/me/AreaMatrix", syncBridge.PreviewRequests[0].RepoPath, "preview repo");
        TestAssert.Equal("replace", syncBridge.PreviewRequests[0].ConflictId, "preview conflict");
        TestAssert.Equal(
            SyncConflictResolutionStrategy.UseIncoming,
            syncBridge.PreviewRequests[0].Resolution,
            "preview strategy");
        TestAssert.Contains(
            "S4-X-09-C4-21",
            syncBridge.ResolveRequests[0].Request.ReplaceConfirmationId ?? "",
            "confirmation id");
        TestAssert.True(syncBridge.ResolveRequests[0].Request.ReplaceConfirmed, "replace confirmed");
        TestAssert.Equal(SyncConflictEntryStatus.Resolved, model.ReplaceResult?.Status, "resolved status");
        TestAssert.Equal(0, model.Conflicts.Count, "resolved conflict removed");
    }

    private static async Task CoreSafetyBackupAllowsReplaceWhenTrashUnavailable()
    {
        FakeSyncConflictEntryCoreBridge syncBridge = new(
            [Conflict("backup", primaryPath: "Contracts/client-contract-1.pdf")],
            CoreSafetyBackupPreview);
        SyncConflictEntryViewModel model = new(syncBridge);

        await model.OpenRepositoryAsync("/home/me/AreaMatrix");
        SyncConflictEntryReviewRoute route = model.ReviewRouteFor(model.FirstReviewableConflict)
            ?? throw new InvalidOperationException("review route missing");

        await model.OpenReviewRouteAsync(route);
        model.ConfirmReplacePlan(true);
        await model.ApplyReplaceAsync();

        TestAssert.True(model.ReplacePreview?.HasRecoverableOldVersion ?? false, "Core safety backup recovery");
        TestAssert.True(syncBridge.ResolveRequests[0].Request.ReplaceConfirmed, "replace confirmed");
        TestAssert.Contains(
            ".areamatrix/staging/safety-backups/client-contract-1.pdf",
            model.ReplacePlanText,
            "backup target");
    }

    private static async Task ReplacePlanTextShowsCompleteS4X09Fields()
    {
        FakeSyncConflictEntryCoreBridge syncBridge = new([
            Conflict("plan", primaryPath: "Contracts/client-contract-1.pdf")
        ]);
        SyncConflictEntryViewModel model = new(syncBridge);

        await model.OpenRepositoryAsync("/home/me/AreaMatrix");
        SyncConflictEntryReviewRoute route = model.ReviewRouteFor(model.FirstReviewableConflict)
            ?? throw new InvalidOperationException("review route missing");

        await model.OpenReviewRouteAsync(route);
        string planText = model.ReplacePlanText;

        foreach (string fragment in new[]
        {
            "Old file path: ",
            "New file path: ",
            "Old hash: old-hash",
            "New hash: new-hash",
            "Affected record: 1",
            "Conflict or import item: plan",
            "Old version will be kept at: Trash",
            "Database update: canonical record will point to incoming file",
            "Change log: replace_file",
            "Recovery note: Existing file remains recoverable if Core apply fails."
        })
        {
            TestAssert.Contains(fragment, planText, $"replace plan fragment {fragment}");
        }
    }

    private static void LinuxMainWindowSmokeExposesS4X03C415Entry()
    {
        string mainUi = File.ReadAllText(RepositoryPath("apps/linux/AreaMatrix/Features/Library/MainWindow.ui"));
        string entryUi = ReadSyncConflictEntryUi();
        string viewModel = File.ReadAllText(RepositoryPath(
            "apps/linux/AreaMatrix/Features/Conflicts/SyncConflictEntryViewModel.cs"));
        string bridge = File.ReadAllText(RepositoryPath(
            "apps/linux/AreaMatrix/Features/Conflicts/SyncConflictEntryCoreBridge.cs"));

        foreach (string fragment in new[]
        {
            "page_id: S4-X-03",
            "Sync conflict needs review",
            "Needs Review",
            "This file has a sync conflict",
            "The page calls detect_sync_conflicts through SyncConflictEntryCoreBridge."
        })
        {
            TestAssert.Contains(fragment, entryUi + mainUi, $"S4-X-03 fragment {fragment}");
        }

        TestAssert.Contains("DetectSyncConflictsAsync", bridge, "C4-15 bridge call");
        TestAssert.Contains("PreviewSyncConflictResolutionAsync", bridge + viewModel, "C4-16 preview");
        TestAssert.Contains("ResolveSyncConflictAsync", bridge + viewModel, "C4-16 resolve");
        TestAssert.Contains("Status == SyncConflictEntryStatus.NeedsReview", viewModel, "needs review filter");
        TestAssert.Contains("ConfirmReplacePlan", entryUi + viewModel, "S4-X-09 confirmation");
        TestAssert.Contains("S4-X-09-C4-21", viewModel, "C4-21 confirmation id");
        TestAssert.Contains("DismissBanner", viewModel, "later action");
    }

    private static void LinuxDesktopShellWiresS4X03ToRealCoreBridge()
    {
        string shell = File.ReadAllText(RepositoryPath(
            "apps/linux/AreaMatrix/Features/Library/LinuxDesktopShell.cs"));
        string nativeClient = File.ReadAllText(RepositoryPath(
            "apps/linux/AreaMatrix/Core/AreaMatrixNativeCoreClient.cs"));
        string nativeDetect = File.ReadAllText(RepositoryPath(
            "apps/linux/AreaMatrix/Core/AreaMatrixNativeCoreClient.SyncConflictDetect.cs"));
        string nativeLibrary = File.ReadAllText(RepositoryPath(
            "apps/linux/AreaMatrix/Core/NativeCoreLibrary.cs"));
        string interop = File.ReadAllText(RepositoryPath(
            "apps/linux/AreaMatrix/Core/NativeCoreInterop.cs"));

        TestAssert.Contains("SyncConflictEntryCoreBridge syncConflictBridge = new(nativeCoreClient)", shell, "real bridge");
        TestAssert.Contains("new LinuxMainWindowFactory(queryBridge, locale, syncConflictBridge)", shell, "factory bridge");
        TestAssert.Contains("IAreaMatrixLinuxSyncConflictCoreClient", nativeClient, "native interface");
        TestAssert.Contains("DetectSyncConflictsChecksum = 31524", nativeClient, "checksum");
        TestAssert.Contains("PreviewSyncConflictResolutionChecksum = 63696", nativeClient, "preview checksum");
        TestAssert.Contains("ResolveSyncConflictChecksum = 50056", nativeClient, "resolve checksum");
        TestAssert.Contains("uniffi_area_matrix_core_fn_func_detect_sync_conflicts", nativeLibrary, "native export");
        TestAssert.Contains(
            "uniffi_area_matrix_core_fn_func_preview_sync_conflict_resolution",
            nativeLibrary,
            "preview native export");
        TestAssert.Contains(
            "uniffi_area_matrix_core_fn_func_resolve_sync_conflict",
            nativeLibrary,
            "resolve native export");
        TestAssert.Contains("DetectSyncConflictsDelegate", interop, "native delegate");
        TestAssert.Contains("PreviewSyncConflictResolutionDelegate", interop, "preview native delegate");
        TestAssert.Contains("ResolveSyncConflictDelegate", interop, "resolve native delegate");
        TestAssert.Contains("ReadSyncConflictStatus", nativeDetect, "status reader");
    }

    private static SyncConflictEntryConflict Conflict(
        string id,
        SyncConflictEntryStatus status = SyncConflictEntryStatus.NeedsReview,
        SyncConflictEntrySeverity severity = SyncConflictEntrySeverity.High,
        string primaryPath = "Contracts/client-contract-1.pdf",
        IReadOnlyList<SyncConflictEntryAffectedFile>? affectedFiles = null)
    {
        return new SyncConflictEntryConflict(
            id,
            SyncConflictEntryType.SameNameDifferentContent,
            severity,
            status,
            primaryPath,
            affectedFiles ?? [],
            2,
            "Linux",
            1_700_000_200,
            "Two versions need review.");
    }

    private static LinuxRepositoryRoute Route(string path)
    {
        return new LinuxRepositoryRoute(
            LinuxRepositoryRouteKind.MainWindow,
            path,
            LinuxRepositoryValidationSamples.Initialized(path));
    }

    private static SyncConflictResolutionPreviewReport CoreSafetyBackupPreview(
        string conflictId,
        SyncConflictResolutionStrategy resolution)
    {
        SyncConflictResolutionPreviewReport preview = FakeSyncConflictEntryCoreBridge.DefaultPreview(
            conflictId,
            resolution);
        return preview with
        {
            TrashAvailable = false,
            ReplacePlan = preview.ReplacePlan is { } plan
                ? plan with { BackupTarget = ".areamatrix/staging/safety-backups/client-contract-1.pdf" }
                : null
        };
    }

    private static string ReadSyncConflictEntryUi()
    {
        return File.ReadAllText(RepositoryPath("apps/linux/AreaMatrix/Features/Conflicts/SyncConflictEntryView.ui"));
    }

    private static string ReadSyncConflictEntryUiFragment(string key)
    {
        string line = ReadSyncConflictEntryUi()
            .Split(Environment.NewLine)
            .First(value => value.TrimStart().StartsWith($"{key}: ", StringComparison.Ordinal));
        return line.Split(':', 2)[1].Trim();
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

internal sealed class FakeSyncConflictEntryCoreBridge : ISyncConflictEntryCoreBridge
{
    private readonly IReadOnlyList<SyncConflictEntryConflict> conflicts;
    private readonly Exception? exception;
    private readonly Func<string, SyncConflictResolutionStrategy, SyncConflictResolutionPreviewReport> previewFactory;

    public FakeSyncConflictEntryCoreBridge(
        IReadOnlyList<SyncConflictEntryConflict> conflicts,
        Func<string, SyncConflictResolutionStrategy, SyncConflictResolutionPreviewReport>? previewFactory = null)
    {
        this.conflicts = conflicts;
        this.previewFactory = previewFactory ?? DefaultPreview;
    }

    public FakeSyncConflictEntryCoreBridge(Exception exception)
    {
        this.exception = exception;
        conflicts = [];
        previewFactory = DefaultPreview;
    }

    public List<string> Requests { get; } = [];

    public List<SyncConflictPreviewRequest> PreviewRequests { get; } = [];

    public List<SyncConflictResolveRequest> ResolveRequests { get; } = [];

    public Task<IReadOnlyList<SyncConflictEntryConflict>> DetectSyncConflictsAsync(
        string repoPath,
        CancellationToken cancellationToken = default)
    {
        Requests.Add(repoPath);
        if (exception is not null)
        {
            throw exception;
        }

        return Task.FromResult(conflicts);
    }

    public Task<SyncConflictResolutionPreviewReport> PreviewSyncConflictResolutionAsync(
        string repoPath,
        string conflictId,
        SyncConflictResolutionStrategy resolution,
        CancellationToken cancellationToken = default)
    {
        PreviewRequests.Add(new SyncConflictPreviewRequest(repoPath, conflictId, resolution));
        return Task.FromResult(previewFactory(conflictId, resolution));
    }

    public Task<SyncConflictResolveReport> ResolveSyncConflictAsync(
        string repoPath,
        string conflictId,
        SyncConflictResolutionRequest resolution,
        CancellationToken cancellationToken = default)
    {
        ResolveRequests.Add(new SyncConflictResolveRequest(repoPath, conflictId, resolution));
        return Task.FromResult(new SyncConflictResolveReport(
            conflictId,
            resolution.Strategy,
            SyncConflictEntryStatus.Resolved,
            [],
            [],
            ["Contracts/client-contract-1.pdf"],
            [1],
            "replace_file",
            "undo-token",
            1_700_000_300));
    }

    public static SyncConflictResolutionPreviewReport DefaultPreview(
        string conflictId,
        SyncConflictResolutionStrategy resolution)
    {
        return new SyncConflictResolutionPreviewReport(
            conflictId,
            resolution,
            SyncConflictResolutionStrategy.KeepBoth,
            SyncConflictEntryStatus.NeedsReview,
            [new SyncConflictVersionImpact(
                "Contracts/client-contract-1.pdf",
                1,
                SyncConflictEntryFileRole.Existing,
                false,
                false,
                false,
                true,
                "Trash",
                "Use incoming replaces the existing visible version.")],
            [],
            [],
            ["Contracts/client-contract-1.pdf"],
            [1],
            "Contracts/client-contract-1.pdf",
            "replace_file",
            true,
            true,
            true,
            true,
            true,
            null,
            "preview-token",
            new SyncConflictReplacePlan(
                "Contracts/client-contract-1.pdf",
                "Contracts/client-contract-incoming.pdf",
                "old-hash",
                "new-hash",
                1,
                "Trash",
                "canonical record will point to incoming file",
                "replace_file",
                "Existing file remains recoverable if Core apply fails."));
    }
}

internal sealed record SyncConflictPreviewRequest(
    string RepoPath,
    string ConflictId,
    SyncConflictResolutionStrategy Resolution);

internal sealed record SyncConflictResolveRequest(
    string RepoPath,
    string ConflictId,
    SyncConflictResolutionRequest Request);
