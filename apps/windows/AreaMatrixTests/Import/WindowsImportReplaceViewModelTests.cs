using AreaMatrix.Features.Import;
using AreaMatrixTests.ChooseRepository;

namespace AreaMatrixTests.Import;

public static class WindowsImportReplaceViewModelTests
{
    public static async Task RunAllAsync()
    {
        await ReplaceUnavailableWithoutCoreImportConflictSession();
        await NameConflictWithoutCoreSessionNeverUsesOverwriteFallback();
        await NameConflictWithoutCoreSessionDoesNotBypassCorePreviewForMove();
        await ReplaceRequiresCorePreviewAndSecondConfirmation();
    }

    private static async Task ReplaceUnavailableWithoutCoreImportConflictSession()
    {
        FakeDesktopImportCoreBridge bridge = new()
        {
            PreviewStatus = DesktopImportPreviewStatus.NameConflict
        };
        WindowsImportViewModel model = new(bridge);
        model.OpenRepository(@"C:\Repos\AreaMatrix");
        model.SourcePathsText = @"C:\Users\me\Downloads\report.pdf";

        await model.PreparePreviewAsync();
        await model.PreviewReplaceAsync();

        TestAssert.True(model.HasNameConflicts, nameof(model.HasNameConflicts));
        TestAssert.False(model.CanPreviewReplace, nameof(model.CanPreviewReplace));
        TestAssert.Contains("Core import conflict preview", model.ReplaceStatusText, nameof(model.ReplaceStatusText));
        TestAssert.Empty(bridge.ReplacePreviewRequests, nameof(bridge.ReplacePreviewRequests));
    }

    private static async Task NameConflictWithoutCoreSessionNeverUsesOverwriteFallback()
    {
        FakeDesktopImportCoreBridge bridge = new()
        {
            PreviewStatus = DesktopImportPreviewStatus.NameConflict
        };
        WindowsImportViewModel model = new(bridge);
        model.OpenRepository(@"C:\Repos\AreaMatrix");
        model.SourcePathsText = @"C:\Users\me\Downloads\report.pdf";

        await model.PreparePreviewAsync();
        await model.PreviewReplaceAsync();

        TestAssert.False(model.CanPreviewReplace, nameof(model.CanPreviewReplace));
        TestAssert.True(model.PendingReplaceConfirmation is null, nameof(model.PendingReplaceConfirmation));
        TestAssert.Empty(bridge.ReplacePreviewRequests, nameof(bridge.ReplacePreviewRequests));

        model.ReplaceConfirmed = true;
        await model.ApplyReplaceAsync();

        TestAssert.Empty(bridge.ImportRequests, nameof(bridge.ImportRequests));
        TestAssert.True(bridge.LastRequest is null, nameof(bridge.LastRequest));
        TestAssert.Contains("Core import conflict preview", model.ReplaceStatusText, nameof(model.ReplaceStatusText));
    }

    private static async Task NameConflictWithoutCoreSessionDoesNotBypassCorePreviewForMove()
    {
        FakeDesktopImportCoreBridge bridge = new()
        {
            PreviewStatus = DesktopImportPreviewStatus.NameConflict
        };
        WindowsImportViewModel model = new(bridge);
        model.OpenRepository(@"C:\Repos\AreaMatrix");
        model.SourcePathsText = @"C:\Users\me\Downloads\report.pdf";
        model.Mode = DesktopImportMode.Move;

        await model.PreparePreviewAsync();
        await model.PreviewReplaceAsync();

        model.ReplaceConfirmed = true;
        await model.ApplyReplaceAsync();

        TestAssert.False(model.CanApplyReplace, nameof(model.CanApplyReplace));
        TestAssert.Empty(bridge.ImportRequests, nameof(bridge.ImportRequests));

        model.MoveConfirmed = true;
        await model.ApplyReplaceAsync();

        TestAssert.Empty(bridge.ImportRequests, nameof(bridge.ImportRequests));
        TestAssert.Empty(bridge.ReplaceApplyRequests, nameof(bridge.ReplaceApplyRequests));
    }

    private static async Task ReplaceRequiresCorePreviewAndSecondConfirmation()
    {
        FakeDesktopImportCoreBridge bridge = new()
        {
            PreviewStatus = DesktopImportPreviewStatus.NameConflict
        };
        WindowsImportViewModel model = new(bridge);
        model.OpenRepository(@"C:\Repos\AreaMatrix");
        model.SetSources([
            new DesktopImportSource(
                @"C:\Users\me\Downloads\report.pdf",
                ImportSessionId: "session-1",
                ConflictId: "name-1")
        ]);

        await model.PreparePreviewAsync();
        await model.PreviewReplaceAsync();

        TestAssert.True(model.PendingReplaceConfirmation is not null, nameof(model.PendingReplaceConfirmation));
        TestAssert.False(model.CanApplyReplace, nameof(model.CanApplyReplace));
        TestAssert.Equal("session-1", bridge.LastReplacePreviewRequest?.ImportSessionId, "preview session");
        TestAssert.SequenceEqual(["name-1"], bridge.LastReplacePreviewRequest?.ConflictIds ?? [], "preview conflict");
        TestAssert.Equal(
            DesktopImportConflictBatchStrategy.Replace,
            bridge.LastReplacePreviewRequest?.SameNameStrategy,
            "preview strategy");

        await model.ApplyReplaceAsync();
        TestAssert.Empty(bridge.ReplaceApplyRequests, nameof(bridge.ReplaceApplyRequests));

        model.ReplaceConfirmed = true;
        await model.ApplyReplaceAsync();

        TestAssert.Equal("token-1", bridge.LastPreviewToken, "preview token");
        TestAssert.True(bridge.LastReplaceApplyRequest?.ReplaceConfirmed == true, "replace confirmed");
        TestAssert.Equal("Replaced 1 item(s).", model.ReplaceResult?.SummaryText, "replace summary");
        TestAssert.Equal(DesktopImportConflictBatchResultStatus.Replaced, model.ReplaceResult?.ItemResults[0].Status, "result");
        TestAssert.False(model.HasPendingReplaceConfirmation, nameof(model.HasPendingReplaceConfirmation));
    }
}
