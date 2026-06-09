using System;
using System.IO;
using System.Runtime.InteropServices;
using AreaMatrix.Features.Onboarding;

namespace AreaMatrix.Core;

internal sealed class NativeCoreLibrary : IDisposable
{
    private readonly IntPtr handle;

    private NativeCoreLibrary(IntPtr handle)
    {
        this.handle = handle;
        ValidateRepoPath = LoadFunction<ValidateRepoPathDelegate>(
            "uniffi_area_matrix_core_fn_func_validate_repo_path");
        DetectCloudStorageState = LoadFunction<DetectCloudStorageStateDelegate>(
            "uniffi_area_matrix_core_fn_func_detect_cloud_storage_state");
        InspectBindingContract = LoadFunction<InspectBindingContractDelegate>(
            "uniffi_area_matrix_core_fn_func_inspect_binding_contract");
        GetPlatformCapabilities = LoadFunction<GetPlatformCapabilitiesDelegate>(
            "uniffi_area_matrix_core_fn_func_get_platform_capabilities");
        AcknowledgeOneDriveRiskNotice = LoadFunction<AcknowledgeOneDriveRiskNoticeDelegate>(
            "uniffi_area_matrix_core_fn_func_acknowledge_onedrive_risk_notice");
        InitRepo = LoadFunction<InitRepoDelegate>("uniffi_area_matrix_core_fn_func_init_repo");
        LoadConfig = LoadFunction<LoadConfigDelegate>("uniffi_area_matrix_core_fn_func_load_config");
        PredictCategory = LoadFunction<PredictCategoryDelegate>(
            "uniffi_area_matrix_core_fn_func_predict_category");
        ImportFileWithResult = LoadFunction<ImportFileWithResultDelegate>(
            "uniffi_area_matrix_core_fn_func_import_file_with_result");
        PreviewImportConflictBatch = LoadFunction<PreviewImportConflictBatchDelegate>(
            "uniffi_area_matrix_core_fn_func_preview_import_conflict_batch");
        ApplyImportConflictBatch = LoadFunction<ApplyImportConflictBatchDelegate>(
            "uniffi_area_matrix_core_fn_func_apply_import_conflict_batch");
        ListFiles = LoadFunction<ListFilesDelegate>("uniffi_area_matrix_core_fn_func_list_files");
        GetFile = LoadFunction<GetFileDelegate>("uniffi_area_matrix_core_fn_func_get_file");
        GetMissingFileState = LoadFunction<GetMissingFileStateDelegate>(
            "uniffi_area_matrix_core_fn_func_get_missing_file_state");
        RelinkMissingFile = LoadFunction<RelinkMissingFileDelegate>(
            "uniffi_area_matrix_core_fn_func_relink_missing_file");
        RemoveMissingFileRecord = LoadFunction<RemoveMissingFileRecordDelegate>(
            "uniffi_area_matrix_core_fn_func_remove_missing_file_record");
        ListTreeJson = LoadFunction<ListTreeJsonDelegate>("uniffi_area_matrix_core_fn_func_list_tree_json");
        DetectSyncConflicts = LoadFunction<DetectSyncConflictsDelegate>(
            "uniffi_area_matrix_core_fn_func_detect_sync_conflicts");
        SearchFiles = LoadFunction<SearchFilesDelegate>("uniffi_area_matrix_core_fn_func_search_files");
        RecordWatcherHealth = LoadFunction<RecordWatcherHealthDelegate>(
            "uniffi_area_matrix_core_fn_func_record_watcher_health");
        PreviewManualRescan = LoadFunction<PreviewManualRescanDelegate>(
            "uniffi_area_matrix_core_fn_func_preview_manual_rescan");
        ReindexFromFilesystem = LoadFunction<ReindexFromFilesystemDelegate>(
            "uniffi_area_matrix_core_fn_func_reindex_from_filesystem");
        GetLatestScanSession = LoadFunction<GetLatestScanSessionDelegate>(
            "uniffi_area_matrix_core_fn_func_get_latest_scan_session");
        ResumeScanSession = LoadFunction<ResumeScanSessionDelegate>(
            "uniffi_area_matrix_core_fn_func_resume_scan_session");
        RustBufferFromBytes = LoadFunction<RustBufferFromBytesDelegate>(
            "ffi_area_matrix_core_rustbuffer_from_bytes");
        RustBufferFree = LoadFunction<RustBufferFreeDelegate>("ffi_area_matrix_core_rustbuffer_free");
        ValidateRepoPathChecksum = LoadFunction<ChecksumDelegate>(
            "uniffi_area_matrix_core_checksum_func_validate_repo_path");
        DetectCloudStorageStateChecksum = LoadFunction<ChecksumDelegate>(
            "uniffi_area_matrix_core_checksum_func_detect_cloud_storage_state");
        InspectBindingContractChecksum = LoadFunction<ChecksumDelegate>(
            "uniffi_area_matrix_core_checksum_func_inspect_binding_contract");
        GetPlatformCapabilitiesChecksum = LoadFunction<ChecksumDelegate>(
            "uniffi_area_matrix_core_checksum_func_get_platform_capabilities");
        AcknowledgeOneDriveRiskNoticeChecksum = LoadFunction<ChecksumDelegate>(
            "uniffi_area_matrix_core_checksum_func_acknowledge_onedrive_risk_notice");
        InitRepoChecksum = LoadFunction<ChecksumDelegate>(
            "uniffi_area_matrix_core_checksum_func_init_repo");
        LoadConfigChecksum = LoadFunction<ChecksumDelegate>(
            "uniffi_area_matrix_core_checksum_func_load_config");
        PredictCategoryChecksum = LoadFunction<ChecksumDelegate>(
            "uniffi_area_matrix_core_checksum_func_predict_category");
        ImportFileWithResultChecksum = LoadFunction<ChecksumDelegate>(
            "uniffi_area_matrix_core_checksum_func_import_file_with_result");
        PreviewImportConflictBatchChecksum = LoadFunction<ChecksumDelegate>(
            "uniffi_area_matrix_core_checksum_func_preview_import_conflict_batch");
        ApplyImportConflictBatchChecksum = LoadFunction<ChecksumDelegate>(
            "uniffi_area_matrix_core_checksum_func_apply_import_conflict_batch");
        ListFilesChecksum = LoadFunction<ChecksumDelegate>(
            "uniffi_area_matrix_core_checksum_func_list_files");
        GetFileChecksum = LoadFunction<ChecksumDelegate>(
            "uniffi_area_matrix_core_checksum_func_get_file");
        GetMissingFileStateChecksum = LoadFunction<ChecksumDelegate>(
            "uniffi_area_matrix_core_checksum_func_get_missing_file_state");
        RelinkMissingFileChecksum = LoadFunction<ChecksumDelegate>(
            "uniffi_area_matrix_core_checksum_func_relink_missing_file");
        RemoveMissingFileRecordChecksum = LoadFunction<ChecksumDelegate>(
            "uniffi_area_matrix_core_checksum_func_remove_missing_file_record");
        ListTreeJsonChecksum = LoadFunction<ChecksumDelegate>(
            "uniffi_area_matrix_core_checksum_func_list_tree_json");
        DetectSyncConflictsChecksum = LoadFunction<ChecksumDelegate>(
            "uniffi_area_matrix_core_checksum_func_detect_sync_conflicts");
        SearchFilesChecksum = LoadFunction<ChecksumDelegate>(
            "uniffi_area_matrix_core_checksum_func_search_files");
        RecordWatcherHealthChecksum = LoadFunction<ChecksumDelegate>(
            "uniffi_area_matrix_core_checksum_func_record_watcher_health");
        PreviewManualRescanChecksum = LoadFunction<ChecksumDelegate>(
            "uniffi_area_matrix_core_checksum_func_preview_manual_rescan");
        ReindexFromFilesystemChecksum = LoadFunction<ChecksumDelegate>(
            "uniffi_area_matrix_core_checksum_func_reindex_from_filesystem");
        GetLatestScanSessionChecksum = LoadFunction<ChecksumDelegate>(
            "uniffi_area_matrix_core_checksum_func_get_latest_scan_session");
        ResumeScanSessionChecksum = LoadFunction<ChecksumDelegate>(
            "uniffi_area_matrix_core_checksum_func_resume_scan_session");
    }

    public ValidateRepoPathDelegate ValidateRepoPath { get; }

    public DetectCloudStorageStateDelegate DetectCloudStorageState { get; }

    public InspectBindingContractDelegate InspectBindingContract { get; }

    public GetPlatformCapabilitiesDelegate GetPlatformCapabilities { get; }

    public AcknowledgeOneDriveRiskNoticeDelegate AcknowledgeOneDriveRiskNotice { get; }

    public InitRepoDelegate InitRepo { get; }

    public LoadConfigDelegate LoadConfig { get; }

    public PredictCategoryDelegate PredictCategory { get; }

    public ImportFileWithResultDelegate ImportFileWithResult { get; }

    public PreviewImportConflictBatchDelegate PreviewImportConflictBatch { get; }

    public ApplyImportConflictBatchDelegate ApplyImportConflictBatch { get; }

    public ListFilesDelegate ListFiles { get; }

    public GetFileDelegate GetFile { get; }

    public GetMissingFileStateDelegate GetMissingFileState { get; }

    public RelinkMissingFileDelegate RelinkMissingFile { get; }

    public RemoveMissingFileRecordDelegate RemoveMissingFileRecord { get; }

    public ListTreeJsonDelegate ListTreeJson { get; }

    public DetectSyncConflictsDelegate DetectSyncConflicts { get; }

    public SearchFilesDelegate SearchFiles { get; }

    public RecordWatcherHealthDelegate RecordWatcherHealth { get; }

    public PreviewManualRescanDelegate PreviewManualRescan { get; }

    public ReindexFromFilesystemDelegate ReindexFromFilesystem { get; }

    public GetLatestScanSessionDelegate GetLatestScanSession { get; }

    public ResumeScanSessionDelegate ResumeScanSession { get; }

    public RustBufferFromBytesDelegate RustBufferFromBytes { get; }

    public RustBufferFreeDelegate RustBufferFree { get; }

    public ChecksumDelegate ValidateRepoPathChecksum { get; }

    public ChecksumDelegate DetectCloudStorageStateChecksum { get; }

    public ChecksumDelegate InspectBindingContractChecksum { get; }

    public ChecksumDelegate GetPlatformCapabilitiesChecksum { get; }

    public ChecksumDelegate AcknowledgeOneDriveRiskNoticeChecksum { get; }

    public ChecksumDelegate InitRepoChecksum { get; }

    public ChecksumDelegate LoadConfigChecksum { get; }

    public ChecksumDelegate PredictCategoryChecksum { get; }

    public ChecksumDelegate ImportFileWithResultChecksum { get; }

    public ChecksumDelegate PreviewImportConflictBatchChecksum { get; }

    public ChecksumDelegate ApplyImportConflictBatchChecksum { get; }

    public ChecksumDelegate ListFilesChecksum { get; }

    public ChecksumDelegate GetFileChecksum { get; }

    public ChecksumDelegate GetMissingFileStateChecksum { get; }

    public ChecksumDelegate RelinkMissingFileChecksum { get; }

    public ChecksumDelegate RemoveMissingFileRecordChecksum { get; }

    public ChecksumDelegate ListTreeJsonChecksum { get; }

    public ChecksumDelegate DetectSyncConflictsChecksum { get; }

    public ChecksumDelegate SearchFilesChecksum { get; }

    public ChecksumDelegate RecordWatcherHealthChecksum { get; }

    public ChecksumDelegate PreviewManualRescanChecksum { get; }

    public ChecksumDelegate ReindexFromFilesystemChecksum { get; }

    public ChecksumDelegate GetLatestScanSessionChecksum { get; }

    public ChecksumDelegate ResumeScanSessionChecksum { get; }

    public static NativeCoreLibrary LoadDefault()
    {
        string? configuredPath = Environment.GetEnvironmentVariable("AREAMATRIX_CORE_LIBRARY");
        if (!string.IsNullOrWhiteSpace(configuredPath))
        {
            return Load(configuredPath);
        }

        return new NativeCoreLibrary(NativeLibrary.Load("area_matrix_core"));
    }

    public static NativeCoreLibrary Load(string libraryPath)
    {
        if (string.IsNullOrWhiteSpace(libraryPath) || !File.Exists(libraryPath))
        {
            throw new WindowsRepositoryCoreException(
                WindowsRepositoryErrorKind.Unavailable,
                $"AreaMatrix Core library was not found at `{libraryPath}`.");
        }

        return new NativeCoreLibrary(NativeLibrary.Load(libraryPath));
    }

    public void Dispose()
    {
        NativeLibrary.Free(handle);
    }

    private T LoadFunction<T>(string name)
        where T : Delegate
    {
        IntPtr export = NativeLibrary.GetExport(handle, name);
        return Marshal.GetDelegateForFunctionPointer<T>(export);
    }
}
