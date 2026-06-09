using AreaMatrix.Features.Onboarding;

namespace AreaMatrix.Core;

public sealed partial class AreaMatrixNativeCoreClient
{
    private const ushort AcknowledgeOneDriveRiskNoticeChecksum = 22622;
    private const ushort ApplyImportConflictBatchChecksum = 14573;
    private const ushort DetectCloudStorageStateChecksum = 18169;
    private const ushort DetectSyncConflictsChecksum = 31524;
    private const ushort GetFileChecksum = 6132;
    private const ushort GetMissingFileStateChecksum = 9097;
    private const ushort GetPlatformCapabilitiesChecksum = 42907;
    private const ushort InitRepoChecksum = 29414;
    private const ushort InspectBindingContractChecksum = 34434;
    private const ushort ImportFileWithResultChecksum = 52959;
    private const ushort ListFilesChecksum = 56809;
    private const ushort ListTreeJsonChecksum = 45468;
    private const ushort LoadConfigChecksum = 64573;
    private const ushort GetLatestScanSessionChecksum = 31155;
    private const ushort PredictCategoryChecksum = 65047;
    private const ushort PreviewImportConflictBatchChecksum = 52321;
    private const ushort PreviewManualRescanChecksum = 12140;
    private const ushort RecordWatcherHealthChecksum = 47455;
    private const ushort ReindexFromFilesystemChecksum = 54635;
    private const ushort RelinkMissingFileChecksum = 39194;
    private const ushort RemoveMissingFileRecordChecksum = 46697;
    private const ushort ResumeScanSessionChecksum = 31216;
    private const ushort SearchFilesChecksum = 65;
    private const ushort ValidateRepoPathChecksum = 43498;

    private void VerifyContract()
    {
        if (native.InitRepoChecksum() != InitRepoChecksum
            || native.AcknowledgeOneDriveRiskNoticeChecksum() != AcknowledgeOneDriveRiskNoticeChecksum
            || native.ApplyImportConflictBatchChecksum() != ApplyImportConflictBatchChecksum
            || native.DetectCloudStorageStateChecksum() != DetectCloudStorageStateChecksum
            || native.DetectSyncConflictsChecksum() != DetectSyncConflictsChecksum
            || native.GetFileChecksum() != GetFileChecksum
            || native.GetMissingFileStateChecksum() != GetMissingFileStateChecksum
            || native.GetPlatformCapabilitiesChecksum() != GetPlatformCapabilitiesChecksum
            || native.InspectBindingContractChecksum() != InspectBindingContractChecksum
            || native.ImportFileWithResultChecksum() != ImportFileWithResultChecksum
            || native.ListFilesChecksum() != ListFilesChecksum
            || native.ListTreeJsonChecksum() != ListTreeJsonChecksum
            || native.LoadConfigChecksum() != LoadConfigChecksum
            || native.GetLatestScanSessionChecksum() != GetLatestScanSessionChecksum
            || native.PredictCategoryChecksum() != PredictCategoryChecksum
            || native.PreviewImportConflictBatchChecksum() != PreviewImportConflictBatchChecksum
            || native.PreviewManualRescanChecksum() != PreviewManualRescanChecksum
            || native.RecordWatcherHealthChecksum() != RecordWatcherHealthChecksum
            || native.ReindexFromFilesystemChecksum() != ReindexFromFilesystemChecksum
            || native.RelinkMissingFileChecksum() != RelinkMissingFileChecksum
            || native.RemoveMissingFileRecordChecksum() != RemoveMissingFileRecordChecksum
            || native.ResumeScanSessionChecksum() != ResumeScanSessionChecksum
            || native.SearchFilesChecksum() != SearchFilesChecksum
            || native.ValidateRepoPathChecksum() != ValidateRepoPathChecksum)
        {
            throw new WindowsRepositoryCoreException(
                WindowsRepositoryErrorKind.Config,
                "AreaMatrix Core binding checksum mismatch.");
        }
    }
}
