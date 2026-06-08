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
        AcknowledgeOneDriveRiskNotice = LoadFunction<AcknowledgeOneDriveRiskNoticeDelegate>(
            "uniffi_area_matrix_core_fn_func_acknowledge_onedrive_risk_notice");
        InitRepo = LoadFunction<InitRepoDelegate>("uniffi_area_matrix_core_fn_func_init_repo");
        LoadConfig = LoadFunction<LoadConfigDelegate>("uniffi_area_matrix_core_fn_func_load_config");
        ListFiles = LoadFunction<ListFilesDelegate>("uniffi_area_matrix_core_fn_func_list_files");
        GetFile = LoadFunction<GetFileDelegate>("uniffi_area_matrix_core_fn_func_get_file");
        ListTreeJson = LoadFunction<ListTreeJsonDelegate>("uniffi_area_matrix_core_fn_func_list_tree_json");
        SearchFiles = LoadFunction<SearchFilesDelegate>("uniffi_area_matrix_core_fn_func_search_files");
        RecordWatcherHealth = LoadFunction<RecordWatcherHealthDelegate>(
            "uniffi_area_matrix_core_fn_func_record_watcher_health");
        RustBufferFromBytes = LoadFunction<RustBufferFromBytesDelegate>(
            "ffi_area_matrix_core_rustbuffer_from_bytes");
        RustBufferFree = LoadFunction<RustBufferFreeDelegate>("ffi_area_matrix_core_rustbuffer_free");
        ValidateRepoPathChecksum = LoadFunction<ChecksumDelegate>(
            "uniffi_area_matrix_core_checksum_func_validate_repo_path");
        DetectCloudStorageStateChecksum = LoadFunction<ChecksumDelegate>(
            "uniffi_area_matrix_core_checksum_func_detect_cloud_storage_state");
        AcknowledgeOneDriveRiskNoticeChecksum = LoadFunction<ChecksumDelegate>(
            "uniffi_area_matrix_core_checksum_func_acknowledge_onedrive_risk_notice");
        InitRepoChecksum = LoadFunction<ChecksumDelegate>(
            "uniffi_area_matrix_core_checksum_func_init_repo");
        LoadConfigChecksum = LoadFunction<ChecksumDelegate>(
            "uniffi_area_matrix_core_checksum_func_load_config");
        ListFilesChecksum = LoadFunction<ChecksumDelegate>(
            "uniffi_area_matrix_core_checksum_func_list_files");
        GetFileChecksum = LoadFunction<ChecksumDelegate>(
            "uniffi_area_matrix_core_checksum_func_get_file");
        ListTreeJsonChecksum = LoadFunction<ChecksumDelegate>(
            "uniffi_area_matrix_core_checksum_func_list_tree_json");
        SearchFilesChecksum = LoadFunction<ChecksumDelegate>(
            "uniffi_area_matrix_core_checksum_func_search_files");
        RecordWatcherHealthChecksum = LoadFunction<ChecksumDelegate>(
            "uniffi_area_matrix_core_checksum_func_record_watcher_health");
    }

    public ValidateRepoPathDelegate ValidateRepoPath { get; }

    public DetectCloudStorageStateDelegate DetectCloudStorageState { get; }

    public AcknowledgeOneDriveRiskNoticeDelegate AcknowledgeOneDriveRiskNotice { get; }

    public InitRepoDelegate InitRepo { get; }

    public LoadConfigDelegate LoadConfig { get; }

    public ListFilesDelegate ListFiles { get; }

    public GetFileDelegate GetFile { get; }

    public ListTreeJsonDelegate ListTreeJson { get; }

    public SearchFilesDelegate SearchFiles { get; }

    public RecordWatcherHealthDelegate RecordWatcherHealth { get; }

    public RustBufferFromBytesDelegate RustBufferFromBytes { get; }

    public RustBufferFreeDelegate RustBufferFree { get; }

    public ChecksumDelegate ValidateRepoPathChecksum { get; }

    public ChecksumDelegate DetectCloudStorageStateChecksum { get; }

    public ChecksumDelegate AcknowledgeOneDriveRiskNoticeChecksum { get; }

    public ChecksumDelegate InitRepoChecksum { get; }

    public ChecksumDelegate LoadConfigChecksum { get; }

    public ChecksumDelegate ListFilesChecksum { get; }

    public ChecksumDelegate GetFileChecksum { get; }

    public ChecksumDelegate ListTreeJsonChecksum { get; }

    public ChecksumDelegate SearchFilesChecksum { get; }

    public ChecksumDelegate RecordWatcherHealthChecksum { get; }

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
