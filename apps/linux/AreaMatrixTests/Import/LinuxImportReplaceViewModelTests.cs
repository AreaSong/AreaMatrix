using AreaMatrix.Linux.Features.Import;
using AreaMatrix.Linux.Tests.ChooseRepository;

namespace AreaMatrix.Linux.Tests.Import;

public static class LinuxImportReplaceViewModelTests
{
    public static async Task RunAllAsync()
    {
        await RealPickerNameConflictWithoutCoreSessionDisablesReplace();
        await ConfirmedRealPickerReplaceDoesNotUseImportOverwriteFallback();
        await DialogPickerAndDropNameConflictCannotPreviewReplaceWithoutInjectedSession();
        await ReplaceRequiresCorePreviewAndSecondConfirmation();
    }

    private static async Task RealPickerNameConflictWithoutCoreSessionDisablesReplace()
    {
        FakeDesktopImportCoreBridge bridge = new()
        {
            PreviewStatus = DesktopImportPreviewStatus.NameConflict
        };
        LinuxImportViewModel model = new(bridge);
        model.OpenRepository("/home/me/AreaMatrix");
        model.SourcePathsText = "/home/me/Downloads/report.pdf";

        await model.PreparePreviewAsync();
        await model.PreviewReplaceAsync();

        TestAssert.True(model.HasNameConflicts, nameof(model.HasNameConflicts));
        TestAssert.False(model.CanPreviewReplace, nameof(model.CanPreviewReplace));
        TestAssert.True(model.PendingReplaceConfirmation is null, nameof(model.PendingReplaceConfirmation));
        TestAssert.False(model.CanApplyReplace, nameof(model.CanApplyReplace));
        TestAssert.Contains("Core import conflict session", model.ReplaceStatusText, nameof(model.ReplaceStatusText));
        TestAssert.Empty(bridge.ReplacePreviewRequests, nameof(bridge.ReplacePreviewRequests));
        TestAssert.Empty(bridge.ImportRequests, nameof(bridge.ImportRequests));
    }

    private static async Task ConfirmedRealPickerReplaceDoesNotUseImportOverwriteFallback()
    {
        FakeDesktopImportCoreBridge bridge = new()
        {
            PreviewStatus = DesktopImportPreviewStatus.NameConflict
        };
        LinuxImportViewModel model = new(bridge);
        model.OpenRepository("/home/me/AreaMatrix");
        model.SourcePathsText = "/home/me/Downloads/report.pdf";

        await model.PreparePreviewAsync();
        await model.PreviewReplaceAsync();
        await model.ApplyReplaceAsync();

        TestAssert.Empty(bridge.ImportRequests, "unconfirmed replace imports");

        model.ReplaceConfirmed = true;
        await model.ApplyReplaceAsync();

        TestAssert.Empty(bridge.ImportRequests, "confirmed replace imports");
        TestAssert.Empty(bridge.ReplaceApplyRequests, nameof(bridge.ReplaceApplyRequests));
        TestAssert.True(model.Results.Count == 0, "replace results");
        TestAssert.False(model.HasPendingReplaceConfirmation, nameof(model.HasPendingReplaceConfirmation));
    }

    private static async Task DialogPickerAndDropNameConflictCannotPreviewReplaceWithoutInjectedSession()
    {
        FakeDesktopImportCoreBridge bridge = new()
        {
            PreviewStatus = DesktopImportPreviewStatus.NameConflict
        };
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
        await dialog.PreviewReplaceAsync();

        TestAssert.False(dialog.ViewModel.CanPreviewReplace, "picker can preview replace");
        TestAssert.True(dialog.ViewModel.PendingReplaceConfirmation is null, "picker replace confirmation");
        TestAssert.True(dialog.ViewModel.Sources.All(source => source.ImportSessionId is null), "picker source session");
        TestAssert.Empty(bridge.ReplacePreviewRequests, "picker replace batch preview");

        await dialog.DropPathsAsync(["/home/me/Downloads/notes.txt"]);
        await dialog.PreviewReplaceAsync();

        TestAssert.False(dialog.ViewModel.CanPreviewReplace, "drop can preview replace");
        TestAssert.True(dialog.ViewModel.PendingReplaceConfirmation is null, "drop replace confirmation");
        TestAssert.True(dialog.ViewModel.Sources.All(source => source.ConflictId is null), "drop source conflict");
    }

    private static async Task ReplaceRequiresCorePreviewAndSecondConfirmation()
    {
        FakeDesktopImportCoreBridge bridge = new()
        {
            PreviewStatus = DesktopImportPreviewStatus.NameConflict
        };
        LinuxImportViewModel model = new(bridge);
        model.OpenRepository("/home/me/AreaMatrix");
        model.SetSources([
            new DesktopImportSource(
                "/home/me/Downloads/report.pdf",
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
        TestAssert.Contains("Trash", model.ReplaceStatusText, nameof(model.ReplaceStatusText));

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
