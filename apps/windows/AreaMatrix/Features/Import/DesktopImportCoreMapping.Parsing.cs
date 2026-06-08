namespace AreaMatrix.Features.Import;

internal static partial class DesktopImportCoreMapping
{
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

    private static DesktopImportConflictBatchStrategy ParseConflictBatchStrategy(string value)
    {
        return value switch
        {
            "Skip" => DesktopImportConflictBatchStrategy.Skip,
            "KeepBoth" => DesktopImportConflictBatchStrategy.KeepBoth,
            "Replace" => DesktopImportConflictBatchStrategy.Replace,
            "AskPerItem" => DesktopImportConflictBatchStrategy.AskPerItem,
            _ => throw new DesktopImportCoreException(
                DesktopImportErrorKind.Config,
                $"AreaMatrix Core returned unsupported import conflict strategy `{value}`.")
        };
    }

    private static DesktopImportConflictBatchPreviewStatus ParseConflictBatchPreviewStatus(string value)
    {
        return value switch
        {
            "Ready" => DesktopImportConflictBatchPreviewStatus.Ready,
            "Pending" => DesktopImportConflictBatchPreviewStatus.Pending,
            "NeedsConfirmation" => DesktopImportConflictBatchPreviewStatus.NeedsConfirmation,
            "Blocked" => DesktopImportConflictBatchPreviewStatus.Blocked,
            "Failed" => DesktopImportConflictBatchPreviewStatus.Failed,
            _ => throw new DesktopImportCoreException(
                DesktopImportErrorKind.Config,
                $"AreaMatrix Core returned unsupported import conflict preview status `{value}`.")
        };
    }

    private static DesktopImportConflictBatchResultStatus ParseConflictBatchResultStatus(string value)
    {
        return value switch
        {
            "Skipped" => DesktopImportConflictBatchResultStatus.Skipped,
            "KeptBoth" => DesktopImportConflictBatchResultStatus.KeptBoth,
            "Replaced" => DesktopImportConflictBatchResultStatus.Replaced,
            "QueuedForPerItem" => DesktopImportConflictBatchResultStatus.QueuedForPerItem,
            "Pending" => DesktopImportConflictBatchResultStatus.Pending,
            "Failed" => DesktopImportConflictBatchResultStatus.Failed,
            _ => throw new DesktopImportCoreException(
                DesktopImportErrorKind.Config,
                $"AreaMatrix Core returned unsupported import conflict result status `{value}`.")
        };
    }
}
