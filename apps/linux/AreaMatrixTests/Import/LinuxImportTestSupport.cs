using AreaMatrix.Linux.Features.Import;
using AreaMatrix.Linux.Features.Library;

namespace AreaMatrix.Linux.Tests.Import;

internal sealed class FakeDesktopImportCoreBridge : IDesktopImportCoreBridge
{
    public List<string> PreviewRequests { get; } = [];

    public List<string> ImportRequests { get; } = [];

    public DesktopImportRequest? LastRequest { get; private set; }

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
}

internal sealed class RecordingDesktopImportCoreClient : IAreaMatrixLinuxDesktopImportCoreClient
{
    public List<string> PredictedFilenames { get; } = [];

    public List<CoreDesktopImportOptions> ImportOptions { get; } = [];

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
