using AreaMatrix.Linux.Features.Import;

namespace AreaMatrix.Linux.Core;

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

    public Task<CoreDesktopImportConflictBatchPreviewReport> PreviewImportConflictBatchAsync(
        string repoPath,
        CoreDesktopImportConflictBatchPreviewRequest request,
        CancellationToken cancellationToken = default)
    {
        cancellationToken.ThrowIfCancellationRequested();
        CoreDesktopImportConflictBatchPreviewReport result = CallWithResult(
            (ref RustCallStatus status) => native.PreviewImportConflictBatch(
                LowerString(repoPath),
                LowerImportConflictBatchPreviewRequest(request),
                ref status),
            ReadImportConflictBatchPreviewReport);
        return Task.FromResult(result);
    }

    public Task<CoreDesktopImportConflictBatchApplyReport> ApplyImportConflictBatchAsync(
        string repoPath,
        CoreDesktopImportConflictBatchApplyRequest request,
        string previewToken,
        CancellationToken cancellationToken = default)
    {
        cancellationToken.ThrowIfCancellationRequested();
        CoreDesktopImportConflictBatchApplyReport result = CallWithResult(
            (ref RustCallStatus status) => native.ApplyImportConflictBatch(
                LowerString(repoPath),
                LowerImportConflictBatchApplyRequest(request),
                LowerString(previewToken),
                ref status),
            ReadImportConflictBatchApplyReport);
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

    private CoreDesktopImportConflictBatchPreviewReport ReadImportConflictBatchPreviewReport(
        UniFfiReader reader)
    {
        return new CoreDesktopImportConflictBatchPreviewReport(
            reader.ReadString(),
            reader.ReadString(),
            reader.ReadBool(),
            reader.ReadInt64(),
            reader.ReadInt64(),
            reader.ReadInt64(),
            reader.ReadInt64(),
            reader.ReadInt64(),
            reader.ReadInt64(),
            reader.ReadInt64(),
            reader.ReadInt64(),
            reader.ReadInt64(),
            reader.ReadInt64(),
            reader.ReadBool(),
            reader.ReadBool(),
            reader.ReadBool(),
            ReadOptionalString(reader),
            reader.ReadBool(),
            ReadOptionalString(reader),
            ReadImportConflictBatchPreviewItems(reader));
    }

    private CoreDesktopImportConflictBatchApplyReport ReadImportConflictBatchApplyReport(
        UniFfiReader reader)
    {
        return new CoreDesktopImportConflictBatchApplyReport(
            reader.ReadString(),
            reader.ReadInt64(),
            reader.ReadInt64(),
            reader.ReadInt64(),
            reader.ReadInt64(),
            reader.ReadInt64(),
            reader.ReadInt64(),
            reader.ReadInt64(),
            reader.ReadInt64(),
            ReadImportConflictBatchItemResults(reader),
            ReadInt64s(reader),
            ReadOptionalString(reader),
            ReadStrings(reader),
            ReadOptionalString(reader));
    }

    private IReadOnlyList<CoreDesktopImportConflictBatchPreviewItem> ReadImportConflictBatchPreviewItems(
        UniFfiReader reader)
    {
        int count = reader.ReadInt32();
        List<CoreDesktopImportConflictBatchPreviewItem> items = new(count);
        for (int index = 0; index < count; index += 1)
        {
            items.Add(ReadImportConflictBatchPreviewItem(reader));
        }

        return items;
    }

    private CoreDesktopImportConflictBatchPreviewItem ReadImportConflictBatchPreviewItem(
        UniFfiReader reader)
    {
        return new CoreDesktopImportConflictBatchPreviewItem(
            reader.ReadString(),
            ReadImportConflictBatchConflictType(reader),
            ReadOptionalInt64(reader),
            ReadOptionalString(reader),
            reader.ReadString(),
            ReadOptionalString(reader),
            ReadImportConflictBatchStrategy(reader),
            ReadImportConflictBatchPreviewStatus(reader),
            reader.ReadBool(),
            reader.ReadBool(),
            reader.ReadBool(),
            reader.ReadBool(),
            reader.ReadBool(),
            reader.ReadString(),
            ReadOptionalString(reader));
    }

    private IReadOnlyList<CoreDesktopImportConflictBatchItemResult> ReadImportConflictBatchItemResults(
        UniFfiReader reader)
    {
        int count = reader.ReadInt32();
        List<CoreDesktopImportConflictBatchItemResult> items = new(count);
        for (int index = 0; index < count; index += 1)
        {
            items.Add(ReadImportConflictBatchItemResult(reader));
        }

        return items;
    }

    private CoreDesktopImportConflictBatchItemResult ReadImportConflictBatchItemResult(
        UniFfiReader reader)
    {
        return new CoreDesktopImportConflictBatchItemResult(
            reader.ReadString(),
            ReadImportConflictBatchConflictType(reader),
            ReadImportConflictBatchStrategy(reader),
            ReadImportConflictBatchResultStatus(reader),
            ReadOptionalInt64(reader),
            ReadOptionalString(reader),
            ReadOptionalString(reader));
    }

    private IReadOnlyList<long> ReadInt64s(UniFfiReader reader)
    {
        int count = reader.ReadInt32();
        List<long> values = new(count);
        for (int index = 0; index < count; index += 1)
        {
            values.Add(reader.ReadInt64());
        }

        return values;
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

    private RustBuffer LowerImportConflictBatchPreviewRequest(
        CoreDesktopImportConflictBatchPreviewRequest request)
    {
        List<byte> bytes = [];
        WriteString(bytes, request.ImportSessionId);
        WriteStrings(bytes, request.ConflictIds);
        WriteImportConflictBatchStrategy(bytes, request.DuplicateStrategy);
        WriteImportConflictBatchStrategy(bytes, request.SameNameStrategy);
        WriteBool(bytes, request.ApplyToAllSimilarConflicts);
        return RustBufferFromBytes(bytes.ToArray());
    }

    private RustBuffer LowerImportConflictBatchApplyRequest(
        CoreDesktopImportConflictBatchApplyRequest request)
    {
        List<byte> bytes = [];
        WriteString(bytes, request.ImportSessionId);
        WriteStrings(bytes, request.ConflictIds);
        WriteImportConflictBatchStrategy(bytes, request.DuplicateStrategy);
        WriteImportConflictBatchStrategy(bytes, request.SameNameStrategy);
        WriteBool(bytes, request.ApplyToAllSimilarConflicts);
        WriteBool(bytes, request.ReplaceConfirmed);
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
            "Overwrite" => 2,
            "KeepBoth" => 3,
            "Ask" => 4,
            _ => throw BindingConfigError($"Unsupported desktop import duplicate strategy `{strategy}`.")
        });
    }

    private static void WriteImportConflictBatchStrategy(List<byte> bytes, string strategy)
    {
        WriteEnum(bytes, strategy switch
        {
            "Skip" => 1,
            "KeepBoth" => 2,
            "Replace" => 3,
            "AskPerItem" => 4,
            _ => throw BindingConfigError($"Unsupported import conflict strategy `{strategy}`.")
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

    private static string ReadImportConflictBatchConflictType(UniFfiReader reader)
    {
        return reader.ReadInt32() switch
        {
            1 => "DuplicateHash",
            2 => "SameNameDifferentContent",
            _ => throw BindingConfigError("AreaMatrix Core returned an unknown import conflict type.")
        };
    }

    private static string ReadImportConflictBatchStrategy(UniFfiReader reader)
    {
        return reader.ReadInt32() switch
        {
            1 => "Skip",
            2 => "KeepBoth",
            3 => "Replace",
            4 => "AskPerItem",
            _ => throw BindingConfigError("AreaMatrix Core returned an unknown import conflict strategy.")
        };
    }

    private static string ReadImportConflictBatchPreviewStatus(UniFfiReader reader)
    {
        return reader.ReadInt32() switch
        {
            1 => "Ready",
            2 => "Pending",
            3 => "NeedsConfirmation",
            4 => "Blocked",
            5 => "Failed",
            _ => throw BindingConfigError("AreaMatrix Core returned an unknown import conflict preview status.")
        };
    }

    private static string ReadImportConflictBatchResultStatus(UniFfiReader reader)
    {
        return reader.ReadInt32() switch
        {
            1 => "Skipped",
            2 => "KeptBoth",
            3 => "Replaced",
            4 => "QueuedForPerItem",
            5 => "Pending",
            6 => "Failed",
            _ => throw BindingConfigError("AreaMatrix Core returned an unknown import conflict result status.")
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
