using System.Collections.Generic;
using System.Threading;
using System.Threading.Tasks;
using AreaMatrix.Features.Import;

namespace AreaMatrix.Core;

public sealed partial class AreaMatrixNativeCoreClient
{
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
}
