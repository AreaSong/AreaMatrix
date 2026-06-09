using AreaMatrix.Linux.Features.Onboarding;
using AreaMatrix.Linux.Features.System;
using AreaMatrix.Linux.Tests.ChooseRepository;

namespace AreaMatrix.Linux.Tests.System;

public static class LinuxRescanConfirmViewModelTests
{
    public static async Task RunAllAsync()
    {
        await UncheckedConfirmationDoesNotRunRescan();
        await StalePreviewDisablesManualRescan();
        await ConfirmedRequestRunsCoreReindexAndShowsNeedsReviewResult();
        await RunningResultDisablesSecondManualRescan();
        await CoreErrorsMapToReadableRecoveryText();
    }

    private static async Task UncheckedConfirmationDoesNotRunRescan()
    {
        const string path = "/home/me/AreaMatrix";
        FakeLinuxWatcherStatusCoreBridge bridge = new();
        LinuxRescanConfirmViewModel model = new(bridge);

        model.OpenRequest(Request(path, Preview()));
        bool started = await model.RunRescanAsync();

        TestAssert.False(started, nameof(started));
        TestAssert.False(model.CanRunRescan, nameof(model.CanRunRescan));
        TestAssert.Empty(bridge.ReindexRequests, nameof(bridge.ReindexRequests));
    }

    private static async Task StalePreviewDisablesManualRescan()
    {
        const string path = "/home/me/AreaMatrix";
        FakeLinuxWatcherStatusCoreBridge bridge = new();
        LinuxRescanConfirmViewModel model = new(bridge);

        model.OpenRequest(Request(path, Preview(isStale: true)));
        model.UserConfirmed = true;
        bool started = await model.RunRescanAsync();

        TestAssert.False(started, nameof(started));
        TestAssert.False(model.CanRunRescan, nameof(model.CanRunRescan));
        TestAssert.Empty(bridge.ReindexRequests, nameof(bridge.ReindexRequests));
    }

    private static async Task ConfirmedRequestRunsCoreReindexAndShowsNeedsReviewResult()
    {
        const string path = "/home/me/AreaMatrix";
        FakeLinuxWatcherStatusCoreBridge bridge = new()
        {
            ReindexReport = new LinuxReindexReport(
                ScanSessionId: 9,
                Inserted: 2,
                Updated: 3,
                Missing: 1,
                Conflicts: 1,
                Unreadable: 1,
                Unknown: 1,
                Skipped: 4,
                Errors: [])
        };
        LinuxRescanConfirmViewModel model = new(bridge);

        model.OpenRequest(Request(path, Preview()));
        model.UserConfirmed = true;
        bool started = await model.RunRescanAsync();

        TestAssert.True(started, nameof(started));
        TestAssert.SequenceEqual([path], bridge.ReindexRequests, nameof(bridge.ReindexRequests));
        TestAssert.Contains("Inserted 2", model.ResultText, nameof(model.ResultText));
        TestAssert.Contains("Conflicts 1", model.ResultText, nameof(model.ResultText));
        TestAssert.True(model.HasNeedsReview, nameof(model.HasNeedsReview));
        TestAssert.False(model.CanRunRescan, nameof(model.CanRunRescan));
        TestAssert.Null(model.Error, nameof(model.Error));
    }

    private static async Task RunningResultDisablesSecondManualRescan()
    {
        const string path = "/home/me/AreaMatrix";
        FakeLinuxWatcherStatusCoreBridge bridge = new();
        LinuxRescanConfirmViewModel model = new(bridge);

        model.OpenRequest(Request(path, Preview()));
        model.UserConfirmed = true;
        bool firstRunStarted = await model.RunRescanAsync();
        bool secondRunStarted = await model.RunRescanAsync();

        TestAssert.True(firstRunStarted, nameof(firstRunStarted));
        TestAssert.False(secondRunStarted, nameof(secondRunStarted));
        TestAssert.SequenceEqual([path], bridge.ReindexRequests, nameof(bridge.ReindexRequests));
        TestAssert.True(model.HasResult, nameof(model.HasResult));
    }

    private static async Task CoreErrorsMapToReadableRecoveryText()
    {
        foreach ((LinuxRepositoryErrorKind kind, string expectedText) in new[]
        {
            (LinuxRepositoryErrorKind.Db, "database"),
            (LinuxRepositoryErrorKind.PermissionDenied, "cannot read or update"),
            (LinuxRepositoryErrorKind.InvalidPath, "folder not found"),
            (LinuxRepositoryErrorKind.FileNotFound, "folder not found"),
            (LinuxRepositoryErrorKind.Conflict, "already running")
        })
        {
            await CoreErrorMapsToReadableRecoveryText(kind, expectedText);
        }
    }

    private static async Task CoreErrorMapsToReadableRecoveryText(
        LinuxRepositoryErrorKind kind,
        string expectedText)
    {
        const string path = "/home/me/AreaMatrix";
        FakeLinuxWatcherStatusCoreBridge bridge = new()
        {
            ReindexError = new LinuxWatcherStatusCoreException(kind, "raw failure", path)
        };
        LinuxRescanConfirmViewModel model = new(bridge);

        model.OpenRequest(Request(path, Preview()));
        model.UserConfirmed = true;
        bool started = await model.RunRescanAsync();

        TestAssert.False(started, $"started {kind}");
        TestAssert.SequenceEqual([path], bridge.ReindexRequests, $"reindex request {kind}");
        TestAssert.Equal(kind, model.Error?.Kind, $"error kind {kind}");
        TestAssert.Contains(expectedText, model.ErrorText, $"error text {kind}");
        TestAssert.False(model.HasResult, $"has result {kind}");
        TestAssert.True(model.CanRunRescan, $"can retry {kind}");
    }

    private static LinuxRescanConfirmRequest Request(string path, LinuxManualRescanPreviewReport preview)
    {
        return new LinuxRescanConfirmRequest(
            new LinuxRepositoryRoute(
                LinuxRepositoryRouteKind.MainWindow,
                path,
                LinuxRepositoryValidationSamples.Initialized(path)),
            preview);
    }

    private static LinuxManualRescanPreviewReport Preview(bool isStale = false)
    {
        return new LinuxManualRescanPreviewReport(
            Added: 2,
            Updated: 1,
            MissingOrDeletedFromFs: 1,
            RenamedCandidates: 0,
            Conflicts: 1,
            Unreadable: 1,
            Unknown: 1,
            Skipped: 3,
            SnapshotId: "preview-1",
            CreatedAt: 1_700_000_040,
            IsStale: isStale,
            Items:
            [
                new LinuxManualRescanPreviewItem(
                    LinuxManualRescanPreviewItemKind.Unknown,
                    "docs/unknown.pdf",
                    "metadata mismatch",
                    "review manually")
            ]);
    }
}
