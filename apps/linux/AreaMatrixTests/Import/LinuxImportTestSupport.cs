using AreaMatrix.Linux.Features.Import;
using AreaMatrix.Linux.Features.Library;

namespace AreaMatrix.Linux.Tests.Import;

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

    public DesktopImportResult Result { get; set; } = ImportResult(DesktopImportSourceRemovalStatus.NotRequested);

    public Exception? ImportException { get; set; }

    public DesktopImportPreviewStatus PreviewStatus { get; set; } = DesktopImportPreviewStatus.Ready;

    public DesktopImportMovePreflight MovePreflight { get; set; } = new(true, [], "same mount");

    public Task<DesktopImportPreviewItem> PredictImportAsync(
        string repoPath,
        string sourcePath,
        CancellationToken cancellationToken = default)
    {
        cancellationToken.ThrowIfCancellationRequested();
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
                ? "/home/me/AreaMatrix/finance/report.pdf"
                : null,
            TargetPath: PreviewStatus == DesktopImportPreviewStatus.NameConflict
                ? "/home/me/AreaMatrix/finance/report.pdf"
                : null,
            ReplaceBlockedReason: PreviewStatus == DesktopImportPreviewStatus.NameConflict
                ? "Replace requires a Core import conflict session, preview token, and Linux Trash availability."
                : null));
    }

    public Task<DesktopImportResult> ImportFileWithResultAsync(
        string repoPath,
        string sourcePath,
        DesktopImportRequest request,
        CancellationToken cancellationToken = default)
    {
        cancellationToken.ThrowIfCancellationRequested();
        if (ImportException is not null)
        {
            throw ImportException;
        }

        ImportRequests.Add(sourcePath);
        LastRequest = request;
        return Task.FromResult(Result with { SourcePath = sourcePath });
    }

    public Task<DesktopImportConflictBatchPreviewReport> PreviewReplaceConflictAsync(
        string repoPath,
        DesktopImportConflictBatchPreviewRequest request,
        CancellationToken cancellationToken = default)
    {
        cancellationToken.ThrowIfCancellationRequested();
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
        cancellationToken.ThrowIfCancellationRequested();
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

    public static DesktopImportResult ImportResult(
        DesktopImportSourceRemovalStatus sourceRemovalStatus,
        string? sourceRemovalFailure = null)
    {
        return new DesktopImportResult(
            new DesktopFileEntry(
                1,
                "finance/report.pdf",
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
            "/home/me/Downloads/report.pdf",
            sourceRemovalStatus,
            sourceRemovalFailure);
    }

    private static DesktopImportConflictBatchPreviewReport ReplacePreview(
        DesktopImportConflictBatchPreviewRequest request)
    {
        return new DesktopImportConflictBatchPreviewReport(
            request.ImportSessionId,
            "token-1",
            request.ApplyToAllSimilarConflicts,
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
            "Existing file will move to Trash before replacement.",
            request.ConflictIds.Select(conflictId => new DesktopImportConflictBatchPreviewItem(
                conflictId,
                "SameNameDifferentContent",
                7,
                "/home/me/AreaMatrix/finance/report.pdf",
                "/home/me/Downloads/report.pdf",
                "/home/me/AreaMatrix/finance/report.pdf",
                DesktopImportConflictBatchStrategy.Replace,
                DesktopImportConflictBatchPreviewStatus.NeedsConfirmation,
                true,
                false,
                false,
                false,
                false,
                "Existing file will move to Trash.",
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
                "finance/report.pdf",
                null)).ToArray(),
            [9],
            "undo-1",
            ["import_replace"],
            null);
    }
}

internal sealed class RecordingDesktopImportCoreClient : IAreaMatrixLinuxDesktopImportCoreClient
{
    public List<string> PredictedFilenames { get; } = [];

    public List<CoreDesktopImportOptions> ImportOptions { get; } = [];

    public List<CoreDesktopImportConflictBatchPreviewRequest> ReplacePreviewRequests { get; } = [];

    public List<CoreDesktopImportConflictBatchApplyRequest> ReplaceApplyRequests { get; } = [];

    public Task<CoreDesktopClassifyResult> PredictCategoryAsync(
        string repoPath,
        string filename,
        CancellationToken cancellationToken = default)
    {
        cancellationToken.ThrowIfCancellationRequested();
        PredictedFilenames.Add(filename);
        return Task.FromResult(new CoreDesktopClassifyResult("finance", filename, "Extension", 0.9f));
    }

    public Task<CoreDesktopImportResult> ImportFileWithResultAsync(
        string repoPath,
        string sourcePath,
        CoreDesktopImportOptions options,
        CancellationToken cancellationToken = default)
    {
        cancellationToken.ThrowIfCancellationRequested();
        ImportOptions.Add(options);
        return Task.FromResult(new CoreDesktopImportResult(
            new CoreDesktopFileEntry(
                2,
                "finance/report.pdf",
                "report.pdf",
                "report.pdf",
                "finance",
                2048,
                "hash-2",
                "Copied",
                "Imported",
                null,
                "Available",
                1_700_000_000,
                1_700_000_100),
            "NotRequested",
            null));
    }

    public Task<CoreDesktopImportConflictBatchPreviewReport> PreviewImportConflictBatchAsync(
        string repoPath,
        CoreDesktopImportConflictBatchPreviewRequest request,
        CancellationToken cancellationToken = default)
    {
        cancellationToken.ThrowIfCancellationRequested();
        ReplacePreviewRequests.Add(request);
        return Task.FromResult(new CoreDesktopImportConflictBatchPreviewReport(
            request.ImportSessionId,
            "token-1",
            request.ApplyToAllSimilarConflicts,
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
            "Existing file will move to Trash before replacement.",
            request.ConflictIds.Select(conflictId => new CoreDesktopImportConflictBatchPreviewItem(
                conflictId,
                "SameNameDifferentContent",
                7,
                "/home/me/AreaMatrix/finance/report.pdf",
                "/home/me/Downloads/report.pdf",
                "/home/me/AreaMatrix/finance/report.pdf",
                "Replace",
                "NeedsConfirmation",
                true,
                false,
                false,
                false,
                false,
                "Existing file will move to Trash.",
                null)).ToArray()));
    }

    public Task<CoreDesktopImportConflictBatchApplyReport> ApplyImportConflictBatchAsync(
        string repoPath,
        CoreDesktopImportConflictBatchApplyRequest request,
        string previewToken,
        CancellationToken cancellationToken = default)
    {
        cancellationToken.ThrowIfCancellationRequested();
        ReplaceApplyRequests.Add(request);
        return Task.FromResult(new CoreDesktopImportConflictBatchApplyReport(
            request.ImportSessionId,
            request.ConflictIds.Count,
            request.ConflictIds.Count,
            0,
            0,
            request.ConflictIds.Count,
            0,
            0,
            0,
            request.ConflictIds.Select(conflictId => new CoreDesktopImportConflictBatchItemResult(
                conflictId,
                "SameNameDifferentContent",
                "Replace",
                "Replaced",
                9,
                "finance/report.pdf",
                null)).ToArray(),
            [9],
            "undo-1",
            ["import_replace"],
            null));
    }
}

internal sealed class StaticLinuxImportFileProbe : ILinuxImportFileProbe
{
    private readonly bool isReadable;

    public StaticLinuxImportFileProbe(bool isReadable)
    {
        this.isReadable = isReadable;
    }

    public LinuxImportFileProbeResult Probe(string sourcePath)
    {
        DesktopImportPreviewStatus status = isReadable
            ? DesktopImportPreviewStatus.Ready
            : DesktopImportPreviewStatus.PermissionDenied;
        return new LinuxImportFileProbeResult(
            sourcePath,
            Path.GetFileName(sourcePath),
            isReadable ? "PDF" : "Unavailable",
            isReadable ? "2 KB" : "-",
            isReadable,
            isReadable,
            status,
            "same mount",
            isReadable ? null : "source file is not readable",
            isReadable ? null : "source folder does not allow removal");
    }

    public LinuxImportFileProbeResult ResolvePreviewProbe(
        string repoPath,
        LinuxImportFileProbeResult source,
        string suggestedCategory,
        string suggestedName)
    {
        return source;
    }

    public DesktopImportMovePreflight CheckMovePreflight(
        string repoPath,
        IReadOnlyList<DesktopImportPreviewItem> previewItems)
    {
        return new DesktopImportMovePreflight(isReadable, isReadable ? [] : ["source file is not readable"], "same mount");
    }

    public IReadOnlyList<DesktopImportSource> ExpandSources(IEnumerable<string> sourcePaths)
    {
        return sourcePaths.Select(path => new DesktopImportSource(path)).ToArray();
    }
}

internal sealed class FakeLinuxImportPickerAdapter : ILinuxImportPickerAdapter
{
    public IReadOnlyList<string> FilePaths { get; set; } = [];

    public string? FolderPath { get; set; }

    public Task<IReadOnlyList<string>> PickFilesAsync(CancellationToken cancellationToken = default)
    {
        cancellationToken.ThrowIfCancellationRequested();
        return Task.FromResult(FilePaths);
    }

    public Task<string?> PickFolderAsync(CancellationToken cancellationToken = default)
    {
        cancellationToken.ThrowIfCancellationRequested();
        return Task.FromResult(FolderPath);
    }
}
