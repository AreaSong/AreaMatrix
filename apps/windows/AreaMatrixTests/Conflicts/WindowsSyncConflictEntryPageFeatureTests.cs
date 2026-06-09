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
        AssertNamedElement(view, "Button", "SyncConflictReviewButton");
        AssertNamedElement(view, "Button", "SyncConflictLaterButton");
        TestAssert.Contains("Sync conflict needs review", view.ToString(), "banner copy");
        TestAssert.Contains("This file has a sync conflict", view.ToString(), "detail copy");
        TestAssert.Contains("DetectSyncConflictsAsync", bridge, "C4-15 bridge call");
        TestAssert.Contains("Status == SyncConflictEntryStatus.NeedsReview", viewModel, "needs review filter");
        TestAssert.Contains("DismissBanner", codeBehind + viewModel, "later action");
        TestAssert.DoesNotContain("ResolveSyncConflict", bridge + viewModel, "no C4-16 resolve");
        TestAssert.DoesNotContain("PreviewSyncConflictResolution", bridge + viewModel, "no C4-16 preview");
    }

    private static void WindowsMainWindowWiresS4X03ReviewRoute()
    {
        string mainWindow = File.ReadAllText(RepositoryPath("apps/windows/AreaMatrix/MainWindow.xaml.cs"));
        string codeBehind = File.ReadAllText(RepositoryPath(
            "apps/windows/AreaMatrix/Features/Library/WindowsMainWindow.xaml.cs"));

        TestAssert.Contains("OpenSyncConflictReviewRequested", mainWindow + codeBehind, "review route event");
        TestAssert.Contains("ReviewRouteFor", codeBehind, "review route creation");
        TestAssert.Contains("ShowSyncConflictReviewRoute(route)", mainWindow, "visible review route handoff");
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

    public FakeSyncConflictEntryCoreBridge(IReadOnlyList<SyncConflictEntryConflict> conflicts)
    {
        this.conflicts = conflicts;
    }

    public FakeSyncConflictEntryCoreBridge(Exception error)
    {
        conflicts = [];
        this.error = error;
    }

    public List<string> Requests { get; } = [];

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
}
