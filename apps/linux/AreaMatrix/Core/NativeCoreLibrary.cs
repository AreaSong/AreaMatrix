using System.Runtime.InteropServices;
using AreaMatrix.Linux.Features.Onboarding;

namespace AreaMatrix.Linux.Core;

internal sealed class NativeCoreLibrary : IDisposable
{
    private readonly IntPtr handle;

    private NativeCoreLibrary(IntPtr handle)
    {
        this.handle = handle;
        ValidateRepoPath = LoadFunction<ValidateRepoPathDelegate>(
            "uniffi_area_matrix_core_fn_func_validate_repo_path");
        InitRepo = LoadFunction<InitRepoDelegate>("uniffi_area_matrix_core_fn_func_init_repo");
        GetPlatformCapabilities = LoadFunction<GetPlatformCapabilitiesDelegate>(
            "uniffi_area_matrix_core_fn_func_get_platform_capabilities");
        ListFiles = LoadFunction<ListFilesDelegate>("uniffi_area_matrix_core_fn_func_list_files");
        GetFile = LoadFunction<GetFileDelegate>("uniffi_area_matrix_core_fn_func_get_file");
        ListTreeJson = LoadFunction<ListTreeJsonDelegate>("uniffi_area_matrix_core_fn_func_list_tree_json");
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
        InitRepoChecksum = LoadFunction<ChecksumDelegate>(
            "uniffi_area_matrix_core_checksum_func_init_repo");
        GetPlatformCapabilitiesChecksum = LoadFunction<ChecksumDelegate>(
            "uniffi_area_matrix_core_checksum_func_get_platform_capabilities");
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

    public InitRepoDelegate InitRepo { get; }

    public GetPlatformCapabilitiesDelegate GetPlatformCapabilities { get; }

    public ListFilesDelegate ListFiles { get; }

    public GetFileDelegate GetFile { get; }

    public ListTreeJsonDelegate ListTreeJson { get; }

    public SearchFilesDelegate SearchFiles { get; }

    public RecordWatcherHealthDelegate RecordWatcherHealth { get; }

    public PreviewManualRescanDelegate PreviewManualRescan { get; }

    public ReindexFromFilesystemDelegate ReindexFromFilesystem { get; }

    public GetLatestScanSessionDelegate GetLatestScanSession { get; }

    public ResumeScanSessionDelegate ResumeScanSession { get; }

    public RustBufferFromBytesDelegate RustBufferFromBytes { get; }

    public RustBufferFreeDelegate RustBufferFree { get; }

    public ChecksumDelegate ValidateRepoPathChecksum { get; }

    public ChecksumDelegate InitRepoChecksum { get; }

    public ChecksumDelegate GetPlatformCapabilitiesChecksum { get; }

    public ChecksumDelegate ListFilesChecksum { get; }

    public ChecksumDelegate GetFileChecksum { get; }

    public ChecksumDelegate ListTreeJsonChecksum { get; }

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
            throw new LinuxRepositoryCoreException(
                LinuxRepositoryErrorKind.Unavailable,
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
