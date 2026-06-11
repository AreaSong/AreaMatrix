using System.Xml.Linq;
using AreaMatrix.Features.Conflicts;
using AreaMatrix.Features.Library;
using AreaMatrix.Features.Onboarding;
using AreaMatrixTests.ChooseRepository;
using AreaMatrixTests.DesktopMainQuery;

namespace AreaMatrixTests.Conflicts;

public static class WindowsSyncConflictEntryPageFeatureTests
{
    private static readonly XNamespace Xaml = "http://schemas.microsoft.com/winfx/2006/xaml";

    public static async Task RunAllAsync()
    {
        await LoadsNeedsReviewConflictsFromCoreBridge();
        await LaterDismissesBannerAndKeepsNeedsReviewList();
        await ReviewRouteUsesStableConflictId();
        await MissingConflictIdDisablesReviewRoute();
        await DetailConflictMatchesSelectedFile();
        await ErrorStateMapsCoreConflictError();
        await ReviewRoutePreviewsConfirmsAndAppliesReplace();
        await CoreSafetyBackupAllowsReplaceWhenRecycleBinUnavailable();
        await ReplacePlanTextShowsCompleteS4X09Fields();
        WindowsMainWindowSmokeExposesS4X03C415Entry();
        WindowsMainWindowWiresS4X03ReviewRoute();
    }

    private static async Task LoadsNeedsReviewConflictsFromCoreBridge()
    {
        FakeSyncConflictEntryCoreBridge syncBridge = new([
            Conflict("resolved", status: SyncConflictEntryStatus.Resolved),
            Conflict("needs-review", primaryPath: @"Contracts\review.pdf")
        ]);
        WindowsMainWindowViewModel model = new(new FakeDesktopMainQueryCoreBridge(), syncBridge);

        await model.OpenRepositoryAsync(Route(@"C:\Repos\AreaMatrix"));

        TestAssert.SequenceEqual([@"C:\Repos\AreaMatrix"], syncBridge.Requests, "detect requests");
        TestAssert.Equal(1, model.SyncConflictEntry?.Conflicts.Count, "needs review count");
        TestAssert.Equal("needs-review", model.SyncConflictEntry?.Conflicts[0].ConflictId, "conflict id");
        TestAssert.True(model.SyncConflictEntry?.IsBannerVisible ?? false, "banner visible");
    }

    private static async Task LaterDismissesBannerAndKeepsNeedsReviewList()
    {
        FakeSyncConflictEntryCoreBridge syncBridge = new([Conflict("later")]);
        SyncConflictEntryViewModel model = new(syncBridge);

        await model.OpenRepositoryAsync(@"C:\Repos\AreaMatrix");
        model.DismissBanner();

        TestAssert.False(model.IsBannerVisible, "banner dismissed");
        TestAssert.Equal(1, model.Conflicts.Count, "list retained");
        TestAssert.Equal(SyncConflictEntryStatus.NeedsReview, model.Conflicts[0].Status, "status retained");
    }

    private static async Task ReviewRouteUsesStableConflictId()
    {
        FakeSyncConflictEntryCoreBridge syncBridge = new([Conflict("route", primaryPath: @"Docs\route.md")]);
        SyncConflictEntryViewModel model = new(syncBridge);

        await model.OpenRepositoryAsync(@"C:\Repos\AreaMatrix");
        SyncConflictEntryReviewRoute? route = model.ReviewRouteFor(model.FirstReviewableConflict);

        TestAssert.Equal(@"C:\Repos\AreaMatrix", route?.RepoPath, "route repo");
        TestAssert.Equal("route", route?.ConflictId, "route conflict");
        TestAssert.Equal(@"Docs\route.md", route?.PrimaryPath, "route path");
    }

    private static async Task MissingConflictIdDisablesReviewRoute()
    {
        FakeSyncConflictEntryCoreBridge syncBridge = new([Conflict("   ")]);
        SyncConflictEntryViewModel model = new(syncBridge);

        await model.OpenRepositoryAsync(@"C:\Repos\AreaMatrix");

        TestAssert.Null(model.FirstReviewableConflict, "first reviewable");
        TestAssert.Null(model.ReviewRouteFor(model.Conflicts[0]), "route");
    }

    private static async Task DetailConflictMatchesSelectedFile()
    {
        SyncConflictEntryConflict conflict = Conflict(
            "detail",
            primaryPath: @"Contracts\client-contract.pdf",
            affectedFiles:
            [
                new SyncConflictEntryAffectedFile(
                    @"Contracts\client-contract.pdf",
                    1,
                    SyncConflictEntryFileRole.Existing,
                    2048,
                    1_700_000_100,
                    "hash-1",
                    "Windows")
            ]);
        FakeSyncConflictEntryCoreBridge syncBridge = new([conflict]);
        WindowsMainWindowViewModel model = new(new FakeDesktopMainQueryCoreBridge(), syncBridge);

        await model.OpenRepositoryAsync(Route(@"C:\Repos\AreaMatrix"));
        await model.SelectFileAsync(model.Files[0]);

        TestAssert.Equal("detail", model.SelectedFileSyncConflict?.ConflictId, "selected conflict");
    }

    private static async Task ErrorStateMapsCoreConflictError()
    {
        FakeSyncConflictEntryCoreBridge syncBridge = new(
            new SyncConflictEntryCoreException(
                SyncConflictEntryErrorKind.Conflict,
                "conflict metadata changed"));
        SyncConflictEntryViewModel model = new(syncBridge);

        await model.OpenRepositoryAsync(@"C:\Repos\AreaMatrix");

        TestAssert.Equal(SyncConflictEntryErrorKind.Conflict, model.Error?.Kind, "error kind");
        TestAssert.Equal("Could not load review items", model.StatusText, "status text");
        TestAssert.Contains("Try again", model.Error?.SuggestedAction ?? string.Empty, "retry action");
    }

    private static async Task ReviewRoutePreviewsConfirmsAndAppliesReplace()
    {
        FakeSyncConflictEntryCoreBridge syncBridge = new([
            Conflict("replace", primaryPath: @"Contracts\client-contract.pdf")
        ]);
        SyncConflictEntryViewModel model = new(syncBridge);

        await model.OpenRepositoryAsync(@"C:\Repos\AreaMatrix");
        SyncConflictEntryReviewRoute route = model.ReviewRouteFor(model.FirstReviewableConflict)
            ?? throw new InvalidOperationException("review route missing");

        await model.OpenReviewRouteAsync(route);
        model.ConfirmReplacePlan(true);
        await model.ApplyReplaceAsync();

        TestAssert.Equal(1, syncBridge.PreviewRequests.Count, "preview request count");
        TestAssert.Equal(@"C:\Repos\AreaMatrix", syncBridge.PreviewRequests[0].RepoPath, "preview repo");
        TestAssert.Equal("replace", syncBridge.PreviewRequests[0].ConflictId, "preview conflict");
        TestAssert.Equal(SyncConflictResolutionStrategy.UseIncoming, syncBridge.PreviewRequests[0].Resolution, "preview strategy");
        TestAssert.Contains("S4-X-09-C4-21", syncBridge.ResolveRequests[0].Request.ReplaceConfirmationId ?? "", "confirmation id");
        TestAssert.True(syncBridge.ResolveRequests[0].Request.ReplaceConfirmed, "replace confirmed");
        TestAssert.Equal(SyncConflictEntryStatus.Resolved, model.ReplaceResult?.Status, "resolved status");
        TestAssert.Equal(0, model.Conflicts.Count, "resolved conflict removed");
    }

    private static async Task CoreSafetyBackupAllowsReplaceWhenRecycleBinUnavailable()
    {
        FakeSyncConflictEntryCoreBridge syncBridge = new(
            [Conflict("backup", primaryPath: @"Contracts\client-contract.pdf")],
            CoreSafetyBackupPreview);
        SyncConflictEntryViewModel model = new(syncBridge);

        await model.OpenRepositoryAsync(@"C:\Repos\AreaMatrix");
        SyncConflictEntryReviewRoute route = model.ReviewRouteFor(model.FirstReviewableConflict)
            ?? throw new InvalidOperationException("review route missing");

        await model.OpenReviewRouteAsync(route);
        model.ConfirmReplacePlan(true);
        await model.ApplyReplaceAsync();

        TestAssert.True(model.ReplacePreview?.HasRecoverableOldVersion ?? false, "Core safety backup recovery");
        TestAssert.True(syncBridge.ResolveRequests[0].Request.ReplaceConfirmed, "replace confirmed");
        TestAssert.Contains(
            @".areamatrix\staging\safety-backups\client-contract.pdf",
            model.ReplacePlanText,
            "backup target");
    }

    private static async Task ReplacePlanTextShowsCompleteS4X09Fields()
    {
        FakeSyncConflictEntryCoreBridge syncBridge = new([
            Conflict("plan", primaryPath: @"Contracts\client-contract.pdf")
        ]);
        SyncConflictEntryViewModel model = new(syncBridge);

        await model.OpenRepositoryAsync(@"C:\Repos\AreaMatrix");
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
            "Old version will be kept at: Recycle Bin",
            "Database update: canonical record will point to incoming file",
            "Change log: replace_file",
            "Recovery note: Existing file remains recoverable if Core apply fails."
        })
        {
            TestAssert.Contains(fragment, planText, $"replace plan fragment {fragment}");
        }
    }

    private static void WindowsMainWindowSmokeExposesS4X03C415Entry()
    {
        XElement view = LoadXml(RepositoryPath("apps/windows/AreaMatrix/Features/Library/WindowsMainWindow.xaml"));
        string codeBehind = File.ReadAllText(RepositoryPath(
            "apps/windows/AreaMatrix/Features/Library/WindowsMainWindow.xaml.cs"));
        string viewModel = File.ReadAllText(RepositoryPath(
            "apps/windows/AreaMatrix/Features/Conflicts/SyncConflictEntryViewModel.cs"));
        string bridge = File.ReadAllText(RepositoryPath(
            "apps/windows/AreaMatrix/Features/Conflicts/SyncConflictEntryCoreBridge.cs"));

        AssertNamedElement(view, "Border", "SyncConflictBanner");
        AssertNamedElement(view, "ListView", "NeedsReviewListView");
        AssertNamedElement(view, "Border", "DetailSyncConflictBanner");
        AssertNamedElement(view, "Border", "SyncConflictReplacePlanPanel");
        AssertNamedElement(view, "CheckBox", "SyncConflictReplaceConfirmCheckBox");
        AssertNamedElement(view, "Button", "SyncConflictReviewButton");
        AssertNamedElement(view, "Button", "SyncConflictLaterButton");
        AssertNamedElement(view, "Button", "SyncConflictApplyReplaceButton");
        TestAssert.Contains("Sync conflict needs review", view.ToString(), "banner copy");
        TestAssert.Contains("Confirm Replace", view.ToString(), "replace confirm copy");
        TestAssert.Contains("This file has a sync conflict", view.ToString(), "detail copy");
        TestAssert.Contains("DetectSyncConflictsAsync", bridge, "C4-15 bridge call");
        TestAssert.Contains("PreviewSyncConflictResolutionAsync", bridge + viewModel, "C4-16 preview");
        TestAssert.Contains("ResolveSyncConflictAsync", bridge + viewModel, "C4-16 resolve");
        TestAssert.Contains("Status == SyncConflictEntryStatus.NeedsReview", viewModel, "needs review filter");
        TestAssert.Contains("ConfirmReplacePlan", codeBehind + viewModel, "S4-X-09 confirmation");
        TestAssert.Contains("S4-X-09-C4-21", viewModel, "C4-21 confirmation id");
        TestAssert.Contains("DismissBanner", codeBehind + viewModel, "later action");
    }

    private static void WindowsMainWindowWiresS4X03ReviewRoute()
    {
        string mainWindow = File.ReadAllText(RepositoryPath("apps/windows/AreaMatrix/MainWindow.xaml.cs"));
        string codeBehind = File.ReadAllText(RepositoryPath(
            "apps/windows/AreaMatrix/Features/Library/WindowsMainWindow.xaml.cs"));

        TestAssert.Contains("OpenSyncConflictReviewRequested", mainWindow + codeBehind, "review route event");
        TestAssert.Contains("ReviewRouteFor", codeBehind, "review route creation");
        TestAssert.Contains("ShowSyncConflictReviewRoute(route)", mainWindow, "visible review route handoff");
        TestAssert.Contains("OpenReviewRouteAsync(route)", codeBehind, "preview route open");
        TestAssert.Contains("SyncConflictApplyReplaceButton_Click", codeBehind, "replace apply action");
    }

    private static SyncConflictEntryConflict Conflict(
        string id,
        SyncConflictEntryStatus status = SyncConflictEntryStatus.NeedsReview,
        SyncConflictEntrySeverity severity = SyncConflictEntrySeverity.High,
        string primaryPath = @"Contracts\client-contract.pdf",
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
            "Windows",
            1_700_000_200,
            "Two versions need review.");
    }

    private static WindowsRepositoryRoute Route(string path)
    {
        return new WindowsRepositoryRoute(
            WindowsRepositoryRouteKind.MainWindow,
            path,
            WindowsRepositoryValidationSamples.Initialized(path),
            new WindowsRepositoryConfig(path, "Copied", "en-US"));
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
                ? plan with { BackupTarget = @".areamatrix\staging\safety-backups\client-contract.pdf" }
                : null
        };
    }

    private static void AssertNamedElement(XElement root, string localName, string name)
    {
        _ = Descendants(root, localName)
            .FirstOrDefault(element => AttributeValue(element, Xaml + "Name") == name)
            ?? throw new InvalidOperationException($"{localName} `{name}` was not found.");
    }

    private static IEnumerable<XElement> Descendants(XElement root, string localName)
    {
        return root.Descendants().Where(element => element.Name.LocalName == localName);
    }

    private static XElement LoadXml(string path)
    {
        return XDocument.Load(path).Root
            ?? throw new InvalidOperationException($"XML root was not found in `{path}`.");
    }

    private static string AttributeValue(XElement element, XName name)
    {
        return element.Attribute(name)?.Value ?? string.Empty;
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
}

internal sealed class FakeSyncConflictEntryCoreBridge : ISyncConflictEntryCoreBridge
{
    private readonly IReadOnlyList<SyncConflictEntryConflict> conflicts;
    private readonly Exception? error;
    private readonly Func<string, SyncConflictResolutionStrategy, SyncConflictResolutionPreviewReport> previewFactory;

    public FakeSyncConflictEntryCoreBridge(
        IReadOnlyList<SyncConflictEntryConflict> conflicts,
        Func<string, SyncConflictResolutionStrategy, SyncConflictResolutionPreviewReport>? previewFactory = null)
    {
        this.conflicts = conflicts;
        this.previewFactory = previewFactory ?? DefaultPreview;
    }

    public FakeSyncConflictEntryCoreBridge(Exception error)
    {
        conflicts = [];
        this.error = error;
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
        if (error is not null)
        {
            throw error;
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
            [@"Contracts\client-contract.pdf"],
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
                @"Contracts\client-contract.pdf",
                1,
                SyncConflictEntryFileRole.Existing,
                false,
                false,
                false,
                true,
                "Recycle Bin",
                "Use incoming replaces the existing visible version.")],
            [],
            [],
            [@"Contracts\client-contract.pdf"],
            [1],
            @"Contracts\client-contract.pdf",
            "replace_file",
            true,
            true,
            true,
            true,
            true,
            null,
            "preview-token",
            new SyncConflictReplacePlan(
                @"Contracts\client-contract.pdf",
                @"Contracts\client-contract-incoming.pdf",
                "old-hash",
                "new-hash",
                1,
                "Recycle Bin",
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
