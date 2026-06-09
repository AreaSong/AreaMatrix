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
        TestAssert.Contains("Status == SyncConflictEntryStatus.NeedsReview", viewModel, "needs review filter");
        TestAssert.Contains("DismissBanner", viewModel, "later action");
        TestAssert.NotContains("ResolveSyncConflict", bridge + viewModel, "no C4-16 resolve");
        TestAssert.NotContains("PreviewSyncConflictResolution", bridge + viewModel, "no C4-16 preview");
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
        TestAssert.Contains("IAreaMatrixLinuxSyncConflictDetectCoreClient", nativeClient, "native interface");
        TestAssert.Contains("DetectSyncConflictsChecksum = 31524", nativeClient, "checksum");
        TestAssert.Contains("uniffi_area_matrix_core_fn_func_detect_sync_conflicts", nativeLibrary, "native export");
        TestAssert.Contains("DetectSyncConflictsDelegate", interop, "native delegate");
        TestAssert.Contains("ReadSyncConflictStatus", nativeDetect, "status reader");
        TestAssert.NotContains("resolve_sync_conflict", nativeDetect, "no resolve binding");
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

    public FakeSyncConflictEntryCoreBridge(IReadOnlyList<SyncConflictEntryConflict> conflicts)
    {
        this.conflicts = conflicts;
    }

    public FakeSyncConflictEntryCoreBridge(Exception exception)
    {
        this.exception = exception;
        conflicts = [];
    }

    public List<string> Requests { get; } = [];

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
}
