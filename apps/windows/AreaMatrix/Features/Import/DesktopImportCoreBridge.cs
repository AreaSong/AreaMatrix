using System.Threading;
using System.Threading.Tasks;
using AreaMatrix.Features.Library;

namespace AreaMatrix.Features.Import;

public interface IDesktopImportCoreBridge
{
    Task<DesktopImportPreviewItem> PredictImportAsync(
        string repoPath,
        string sourcePath,
        CancellationToken cancellationToken = default);

    Task<DesktopImportResult> ImportFileWithResultAsync(
        string repoPath,
        string sourcePath,
        DesktopImportRequest request,
        CancellationToken cancellationToken = default);

    DesktopImportMovePreflight CheckMovePreflight(
        string repoPath,
        IReadOnlyList<DesktopImportPreviewItem> previewItems);
}

public interface IAreaMatrixDesktopImportCoreClient
{
    Task<CoreDesktopClassifyResult> PredictCategoryAsync(
        string repoPath,
        string filename,
        CancellationToken cancellationToken = default);

    Task<CoreDesktopImportResult> ImportFileWithResultAsync(
        string repoPath,
        string sourcePath,
        CoreDesktopImportOptions options,
        CancellationToken cancellationToken = default);
}

public sealed class DesktopImportCoreBridge : IDesktopImportCoreBridge
{
    private readonly IAreaMatrixDesktopImportCoreClient coreClient;
    private readonly IWindowsImportFileProbe fileProbe;

    public DesktopImportCoreBridge(
        IAreaMatrixDesktopImportCoreClient coreClient,
        IWindowsImportFileProbe fileProbe)
    {
        this.coreClient = coreClient;
        this.fileProbe = fileProbe;
    }

    public async Task<DesktopImportPreviewItem> PredictImportAsync(
        string repoPath,
        string sourcePath,
        CancellationToken cancellationToken = default)
    {
        WindowsImportFileProbeResult probe = fileProbe.Probe(sourcePath);
        if (!probe.IsReadable)
        {
            return new DesktopImportPreviewItem(
                sourcePath,
                probe.FileName,
                probe.TypeText,
                probe.SizeText,
                string.Empty,
                probe.FileName,
                DesktopImportPreviewStatus.Unreadable);
        }

        CoreDesktopClassifyResult result = await coreClient
            .PredictCategoryAsync(repoPath, probe.FileName, cancellationToken)
            .ConfigureAwait(false);

        DesktopImportPreviewStatus status = fileProbe.ResolvePreviewStatus(
            repoPath,
            probe,
            result.Category,
            result.SuggestedName);

        return new DesktopImportPreviewItem(
            sourcePath,
            probe.FileName,
            probe.TypeText,
            probe.SizeText,
            result.Category,
            result.SuggestedName,
            status);
    }

    public async Task<DesktopImportResult> ImportFileWithResultAsync(
        string repoPath,
        string sourcePath,
        DesktopImportRequest request,
        CancellationToken cancellationToken = default)
    {
        CoreDesktopImportResult result = await coreClient
            .ImportFileWithResultAsync(repoPath, sourcePath, request.ToCoreOptions(), cancellationToken)
            .ConfigureAwait(false);
        return result.ToDesktopResult();
    }

    public DesktopImportMovePreflight CheckMovePreflight(
        string repoPath,
        IReadOnlyList<DesktopImportPreviewItem> previewItems)
    {
        return fileProbe.CheckMovePreflight(repoPath, previewItems);
    }
}

public sealed record CoreDesktopClassifyResult(
    string Category,
    string SuggestedName,
    string Reason,
    float Confidence);

public sealed record CoreDesktopImportOptions(
    string Mode,
    string Destination,
    string? TargetDirectory,
    string? OverrideCategory,
    string? OverrideFilename,
    string DuplicateStrategy);

public sealed record CoreDesktopImportResult(
    CoreDesktopFileEntry Entry,
    string SourceRemovalStatus,
    string? SourceRemovalFailure);

internal static class DesktopImportCoreMapping
{
    public static CoreDesktopImportOptions ToCoreOptions(this DesktopImportRequest request)
    {
        return new CoreDesktopImportOptions(
            request.Mode.ToCoreMode(),
            request.Destination.ToCoreDestination(),
            NormalizeOptional(request.TargetDirectory),
            NormalizeOptional(request.OverrideCategory),
            NormalizeOptional(request.OverrideFilename),
            request.DuplicateStrategy.ToCoreDuplicateStrategy());
    }

    public static DesktopImportResult ToDesktopResult(this CoreDesktopImportResult result)
    {
        return new DesktopImportResult(
            result.Entry.ToDesktopEntry(),
            ParseSourceRemovalStatus(result.SourceRemovalStatus),
            result.SourceRemovalFailure);
    }

    private static string ToCoreMode(this DesktopImportMode mode)
    {
        return mode switch
        {
            DesktopImportMode.Copy => "Copied",
            DesktopImportMode.Move => "Moved",
            _ => throw new DesktopImportCoreException(
                DesktopImportErrorKind.Config,
                $"Unsupported desktop import mode `{mode}`.")
        };
    }

    private static string ToCoreDestination(this DesktopImportDestination destination)
    {
        return destination switch
        {
            DesktopImportDestination.AutoClassify => "AutoClassify",
            DesktopImportDestination.SelectedDirectory => "SelectedDirectory",
            DesktopImportDestination.Category => "Category",
            _ => throw new DesktopImportCoreException(
                DesktopImportErrorKind.Config,
                $"Unsupported desktop import destination `{destination}`.")
        };
    }

    private static string ToCoreDuplicateStrategy(this DesktopImportDuplicateStrategy strategy)
    {
        return strategy switch
        {
            DesktopImportDuplicateStrategy.Skip => "Skip",
            DesktopImportDuplicateStrategy.KeepBoth => "KeepBoth",
            DesktopImportDuplicateStrategy.Ask => "Ask",
            _ => throw new DesktopImportCoreException(
                DesktopImportErrorKind.Config,
                $"Unsupported desktop import duplicate strategy `{strategy}`.")
        };
    }

    private static DesktopImportSourceRemovalStatus ParseSourceRemovalStatus(string value)
    {
        return value switch
        {
            "NotRequested" => DesktopImportSourceRemovalStatus.NotRequested,
            "Removed" => DesktopImportSourceRemovalStatus.Removed,
            "Retained" => DesktopImportSourceRemovalStatus.Retained,
            _ => throw new DesktopImportCoreException(
                DesktopImportErrorKind.Config,
                $"AreaMatrix Core returned unsupported source removal status `{value}`.")
        };
    }

    private static string? NormalizeOptional(string? value)
    {
        return string.IsNullOrWhiteSpace(value) ? null : value.Trim();
    }
}
