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
        InitRepo = LoadFunction<InitRepoDelegate>("uniffi_area_matrix_core_fn_func_init_repo");
        LoadConfig = LoadFunction<LoadConfigDelegate>("uniffi_area_matrix_core_fn_func_load_config");
        RustBufferFromBytes = LoadFunction<RustBufferFromBytesDelegate>(
            "ffi_area_matrix_core_rustbuffer_from_bytes");
        RustBufferFree = LoadFunction<RustBufferFreeDelegate>("ffi_area_matrix_core_rustbuffer_free");
        ValidateRepoPathChecksum = LoadFunction<ChecksumDelegate>(
            "uniffi_area_matrix_core_checksum_func_validate_repo_path");
        InitRepoChecksum = LoadFunction<ChecksumDelegate>(
            "uniffi_area_matrix_core_checksum_func_init_repo");
        LoadConfigChecksum = LoadFunction<ChecksumDelegate>(
            "uniffi_area_matrix_core_checksum_func_load_config");
    }

    public ValidateRepoPathDelegate ValidateRepoPath { get; }

    public InitRepoDelegate InitRepo { get; }

    public LoadConfigDelegate LoadConfig { get; }

    public RustBufferFromBytesDelegate RustBufferFromBytes { get; }

    public RustBufferFreeDelegate RustBufferFree { get; }

    public ChecksumDelegate ValidateRepoPathChecksum { get; }

    public ChecksumDelegate InitRepoChecksum { get; }

    public ChecksumDelegate LoadConfigChecksum { get; }

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
