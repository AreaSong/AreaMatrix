using AreaMatrix.Features.Import;
using AreaMatrix.Features.Library;

namespace AreaMatrixTests.Import;

internal sealed class FakeDesktopImportCoreBridge : IDesktopImportCoreBridge
{
    public List<string> PreviewRequests { get; } = [];

    public List<string> ImportRequests { get; } = [];

    public List<DesktopImportConflictBatchPreviewRequest> ReplacePreviewRequests { get; } = [];

    public List<DesktopImportConflictBatchApplyRequest> ReplaceApplyRequests { get; } = [];

    public DesktopImportRequest? LastRequest { get; private set; }

    public DesktopImportConflictBatchPreviewRequest? LastReplacePreviewRequest { get; private set; }

    public DesktopImportConflictBatchApplyRequest? LastReplaceApplyRequest { get; private set; }

    public string? LastPreviewToken { get; private set; }

    public DesktopImportResult Result { get; set; } = new(
        new DesktopFileEntry(
            1,
            @"finance\report.pdf",
            "report.pdf",
            "report.pdf",
            "finance",
            2048,
            "hash-1",
            DesktopStorageMode.Copied,
            DesktopFileOrigin.Imported,
            null,
            DesktopFileAvailabilityStatus.Available,
            1_700_000_000,
            1_700_000_100),
        @"C:\Users\me\Downloads\report.pdf",
        DesktopImportSourceRemovalStatus.NotRequested,
        null);

    public Exception? ImportException { get; set; }

    public DesktopImportPreviewStatus PreviewStatus { get; set; } = DesktopImportPreviewStatus.Ready;

    public DesktopImportMovePreflight MovePreflight { get; set; } = new(true, []);

    public Task<DesktopImportPreviewItem> PredictImportAsync(
        string repoPath,
        string sourcePath,
        CancellationToken cancellationToken = default)
    {
        PreviewRequests.Add(sourcePath);
        return Task.FromResult(new DesktopImportPreviewItem(
            sourcePath,
            Path.GetFileName(sourcePath),
            "PDF",
            "2 KB",
            "finance",
            Path.GetFileName(sourcePath),
            PreviewStatus,
            ExistingPath: PreviewStatus == DesktopImportPreviewStatus.NameConflict
                ? @"C:\Repos\AreaMatrix\finance\report.pdf"
                : null,
            TargetPath: PreviewStatus == DesktopImportPreviewStatus.NameConflict
                ? @"C:\Repos\AreaMatrix\finance\report.pdf"
                : null,
            ReplacePreflightAvailable: false,
            ReplaceBlockedReason: PreviewStatus == DesktopImportPreviewStatus.NameConflict
                    ? "Replace requires Core import conflict preview with Recycle Bin safety state."
                    : null));
    }

    public Task<DesktopImportResult> ImportFileWithResultAsync(
        string repoPath,
        string sourcePath,
        DesktopImportRequest request,
        CancellationToken cancellationToken = default)
    {
        if (ImportException is not null)
        {
            throw ImportException;
        }

        ImportRequests.Add(sourcePath);
        LastRequest = request;
        return Task.FromResult(Result);
    }

    public Task<DesktopImportConflictBatchPreviewReport> PreviewReplaceConflictAsync(
        string repoPath,
        DesktopImportConflictBatchPreviewRequest request,
        CancellationToken cancellationToken = default)
    {
        ReplacePreviewRequests.Add(request);
        LastReplacePreviewRequest = request;
        return Task.FromResult(ReplacePreview(request));
    }

    public Task<DesktopImportConflictBatchApplyReport> ApplyReplaceConflictAsync(
        string repoPath,
        DesktopImportConflictBatchApplyRequest request,
        string previewToken,
        CancellationToken cancellationToken = default)
    {
        ReplaceApplyRequests.Add(request);
        LastReplaceApplyRequest = request;
        LastPreviewToken = previewToken;
        return Task.FromResult(ReplaceReport(request));
    }

    public DesktopImportMovePreflight CheckMovePreflight(
        string repoPath,
        IReadOnlyList<DesktopImportPreviewItem> previewItems)
    {
        return MovePreflight;
    }

    private static DesktopImportConflictBatchPreviewReport ReplacePreview(
        DesktopImportConflictBatchPreviewRequest request)
    {
        return new DesktopImportConflictBatchPreviewReport(
            request.ImportSessionId,
            "token-1",
            false,
            request.ConflictIds.Count,
            0,
            request.ConflictIds.Count,
            request.ConflictIds.Count,
            0,
            0,
            request.ConflictIds.Count,
            0,
            0,
            0,
            true,
            true,
            true,
            null,
            true,
            "Existing file will move to Recycle Bin before replacement.",
            request.ConflictIds.Select(conflictId => new DesktopImportConflictBatchPreviewItem(
                conflictId,
                "SameNameDifferentContent",
                7,
                @"finance\report.pdf",
                @"C:\Users\me\Downloads\report.pdf",
                @"finance\report.pdf",
                DesktopImportConflictBatchStrategy.Replace,
                DesktopImportConflictBatchPreviewStatus.NeedsConfirmation,
                true,
                false,
                false,
                false,
                false,
                "Existing file will move to Recycle Bin before replacement.",
                null)).ToArray());
    }

    private static DesktopImportConflictBatchApplyReport ReplaceReport(
        DesktopImportConflictBatchApplyRequest request)
    {
        return new DesktopImportConflictBatchApplyReport(
            request.ImportSessionId,
            request.ConflictIds.Count,
            request.ConflictIds.Count,
            0,
            0,
            request.ConflictIds.Count,
            0,
            0,
            0,
            request.ConflictIds.Select(conflictId => new DesktopImportConflictBatchItemResult(
                conflictId,
                "SameNameDifferentContent",
                DesktopImportConflictBatchStrategy.Replace,
                DesktopImportConflictBatchResultStatus.Replaced,
                9,
                @"finance\report.pdf",
                null)).ToArray(),
            [7, 9],
            "undo-1",
            ["import_conflict_replaced"],
            null);
    }
}

internal sealed class RecordingDesktopImportCoreClient : IAreaMatrixDesktopImportCoreClient
{
    public List<string> PredictedFilenames { get; } = [];

    public Task<CoreDesktopClassifyResult> PredictCategoryAsync(
        string repoPath,
        string filename,
        CancellationToken cancellationToken = default)
    {
        PredictedFilenames.Add(filename);
        return Task.FromResult(new CoreDesktopClassifyResult("finance", filename, "Extension", 0.9f));
    }

    public Task<CoreDesktopImportResult> ImportFileWithResultAsync(
        string repoPath,
        string sourcePath,
        CoreDesktopImportOptions options,
        CancellationToken cancellationToken = default)
    {
        throw new NotSupportedException("import is not used by this test");
    }

    public Task<CoreDesktopImportConflictBatchPreviewReport> PreviewImportConflictBatchAsync(
        string repoPath,
        CoreDesktopImportConflictBatchPreviewRequest request,
        CancellationToken cancellationToken = default)
    {
        throw new NotSupportedException("replace preview is not used by this test");
    }

    public Task<CoreDesktopImportConflictBatchApplyReport> ApplyImportConflictBatchAsync(
        string repoPath,
        CoreDesktopImportConflictBatchApplyRequest request,
        string previewToken,
        CancellationToken cancellationToken = default)
    {
        throw new NotSupportedException("replace apply is not used by this test");
    }
}

internal sealed class StaticWindowsImportFileProbe : IWindowsImportFileProbe
{
    private readonly bool isReadable;

    public StaticWindowsImportFileProbe(bool isReadable)
    {
        this.isReadable = isReadable;
    }

    public WindowsImportFileProbeResult Probe(string sourcePath)
    {
        return new WindowsImportFileProbeResult(
            sourcePath,
            Path.GetFileName(sourcePath),
            isReadable ? "PDF" : "Unavailable",
            isReadable ? "2 KB" : "-",
            isReadable,
            isReadable,
            isReadable ? null : "source file is not readable",
            isReadable ? null : "source location does not allow removal");
    }

    public DesktopImportPreviewStatus ResolvePreviewStatus(
        string repoPath,
        WindowsImportFileProbeResult source,
        string suggestedCategory,
        string suggestedName)
    {
        return source.IsReadable ? DesktopImportPreviewStatus.Ready : DesktopImportPreviewStatus.Unreadable;
    }

    public DesktopImportMovePreflight CheckMovePreflight(
        string repoPath,
        IReadOnlyList<DesktopImportPreviewItem> previewItems)
    {
        return new DesktopImportMovePreflight(isReadable, isReadable ? [] : ["source file is not readable"]);
    }

    public IReadOnlyList<DesktopImportSource> ExpandSources(IEnumerable<string> sourcePaths)
    {
        return sourcePaths.Select(path => new DesktopImportSource(path)).ToArray();
    }

    public WindowsImportFileProbeResult ResolveReplacePreflight(
        string repoPath,
        WindowsImportFileProbeResult source,
        string suggestedCategory,
        string suggestedName)
    {
        return source;
    }
}
