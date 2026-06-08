using System.Collections.Generic;
using System.Threading;
using System.Threading.Tasks;
using AreaMatrix.Features.Import;

namespace AreaMatrix.Core;

public sealed partial class AreaMatrixNativeCoreClient
{
    public Task<CoreDesktopClassifyResult> PredictCategoryAsync(
        string repoPath,
        string filename,
        CancellationToken cancellationToken = default)
    {
        cancellationToken.ThrowIfCancellationRequested();
        CoreDesktopClassifyResult result = CallWithResult(
            (ref RustCallStatus status) => native.PredictCategory(
                LowerString(repoPath),
                LowerString(filename),
                ref status),
            ReadClassifyResult);
        return Task.FromResult(result);
    }

    public Task<CoreDesktopImportResult> ImportFileWithResultAsync(
        string repoPath,
        string sourcePath,
        CoreDesktopImportOptions options,
        CancellationToken cancellationToken = default)
    {
        cancellationToken.ThrowIfCancellationRequested();
        CoreDesktopImportResult result = CallWithResult(
            (ref RustCallStatus status) => native.ImportFileWithResult(
                LowerString(repoPath),
                LowerString(sourcePath),
                LowerImportOptions(options),
                ref status),
            ReadImportResult);
        return Task.FromResult(result);
    }

    private CoreDesktopClassifyResult ReadClassifyResult(UniFfiReader reader)
    {
        return new CoreDesktopClassifyResult(
            reader.ReadString(),
            reader.ReadString(),
            ReadClassifyReason(reader),
            reader.ReadSingle());
    }

    private CoreDesktopImportResult ReadImportResult(UniFfiReader reader)
    {
        return new CoreDesktopImportResult(
            ReadFileEntry(reader),
            ReadImportSourceRemovalStatus(reader),
            ReadOptionalString(reader));
    }

    private RustBuffer LowerImportOptions(CoreDesktopImportOptions options)
    {
        List<byte> bytes = [];
        WriteStorageMode(bytes, options.Mode);
        WriteImportDestination(bytes, options.Destination);
        WriteOptionalString(bytes, options.TargetDirectory);
        WriteOptionalString(bytes, options.OverrideCategory);
        WriteOptionalString(bytes, options.OverrideFilename);
        WriteDuplicateStrategy(bytes, options.DuplicateStrategy);
        return RustBufferFromBytes(bytes.ToArray());
    }

    private static void WriteImportDestination(List<byte> bytes, string destination)
    {
        WriteEnum(bytes, destination switch
        {
            "AutoClassify" => 1,
            "SelectedDirectory" => 2,
            "Category" => 3,
            _ => throw BindingConfigError($"Unsupported desktop import destination `{destination}`.")
        });
    }

    private static void WriteDuplicateStrategy(List<byte> bytes, string strategy)
    {
        WriteEnum(bytes, strategy switch
        {
            "Skip" => 1,
            "KeepBoth" => 3,
            "Ask" => 4,
            _ => throw BindingConfigError($"Unsupported desktop import duplicate strategy `{strategy}`.")
        });
    }

    private static string ReadClassifyReason(UniFfiReader reader)
    {
        return reader.ReadInt32() switch
        {
            1 => "Keyword",
            2 => "Extension",
            3 => "AiPredicted",
            4 => "Default",
            _ => throw BindingConfigError("AreaMatrix Core returned an unknown classify reason.")
        };
    }

    private static string ReadImportSourceRemovalStatus(UniFfiReader reader)
    {
        return reader.ReadInt32() switch
        {
            1 => "NotRequested",
            2 => "Removed",
            3 => "Retained",
            _ => throw BindingConfigError("AreaMatrix Core returned an unknown source removal status.")
        };
    }
}
