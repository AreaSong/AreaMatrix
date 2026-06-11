using System.Runtime.InteropServices;

namespace AreaMatrix.Linux.Core;

[UnmanagedFunctionPointer(CallingConvention.Cdecl)]
internal delegate RustBuffer GetVersionDelegate(ref RustCallStatus status);

[UnmanagedFunctionPointer(CallingConvention.Cdecl)]
internal delegate RustBuffer ValidateRepoPathDelegate(RustBuffer repoPath, ref RustCallStatus status);

[UnmanagedFunctionPointer(CallingConvention.Cdecl)]
internal delegate RustBuffer LoadConfigDelegate(RustBuffer repoPath, ref RustCallStatus status);

[UnmanagedFunctionPointer(CallingConvention.Cdecl)]
internal delegate void UpdateConfigDelegate(
    RustBuffer repoPath,
    RustBuffer newConfig,
    ref RustCallStatus status);

[UnmanagedFunctionPointer(CallingConvention.Cdecl)]
internal delegate void InitRepoDelegate(RustBuffer repoPath, RustBuffer options, ref RustCallStatus status);

[UnmanagedFunctionPointer(CallingConvention.Cdecl)]
internal delegate RustBuffer PredictCategoryDelegate(
    RustBuffer repoPath,
    RustBuffer filename,
    ref RustCallStatus status);

[UnmanagedFunctionPointer(CallingConvention.Cdecl)]
internal delegate RustBuffer ImportFileWithResultDelegate(
    RustBuffer repoPath,
    RustBuffer sourcePath,
    RustBuffer options,
    ref RustCallStatus status);

[UnmanagedFunctionPointer(CallingConvention.Cdecl)]
internal delegate RustBuffer PreviewImportConflictBatchDelegate(
    RustBuffer repoPath,
    RustBuffer request,
    ref RustCallStatus status);

[UnmanagedFunctionPointer(CallingConvention.Cdecl)]
internal delegate RustBuffer ApplyImportConflictBatchDelegate(
    RustBuffer repoPath,
    RustBuffer request,
    RustBuffer previewToken,
    ref RustCallStatus status);

[UnmanagedFunctionPointer(CallingConvention.Cdecl)]
internal delegate RustBuffer InspectBindingContractDelegate(
    RustBuffer request,
    ref RustCallStatus status);

[UnmanagedFunctionPointer(CallingConvention.Cdecl)]
internal delegate RustBuffer GetPlatformCapabilitiesDelegate(
    RustBuffer platform,
    RustBuffer appVersion,
    ref RustCallStatus status);

[UnmanagedFunctionPointer(CallingConvention.Cdecl)]
internal delegate RustBuffer ListFilesDelegate(RustBuffer repoPath, RustBuffer filter, ref RustCallStatus status);

[UnmanagedFunctionPointer(CallingConvention.Cdecl)]
internal delegate RustBuffer GetFileDelegate(RustBuffer repoPath, long fileId, ref RustCallStatus status);

[UnmanagedFunctionPointer(CallingConvention.Cdecl)]
internal delegate RustBuffer GetMissingFileStateDelegate(RustBuffer repoPath, long fileId, ref RustCallStatus status);

[UnmanagedFunctionPointer(CallingConvention.Cdecl)]
internal delegate RustBuffer RelinkMissingFileDelegate(
    RustBuffer repoPath,
    RustBuffer request,
    ref RustCallStatus status);

[UnmanagedFunctionPointer(CallingConvention.Cdecl)]
internal delegate RustBuffer RemoveMissingFileRecordDelegate(
    RustBuffer repoPath,
    RustBuffer request,
    ref RustCallStatus status);

[UnmanagedFunctionPointer(CallingConvention.Cdecl)]
internal delegate RustBuffer ListTreeJsonDelegate(RustBuffer repoPath, RustBuffer locale, ref RustCallStatus status);

[UnmanagedFunctionPointer(CallingConvention.Cdecl)]
internal delegate RustBuffer DetectSyncConflictsDelegate(RustBuffer repoPath, ref RustCallStatus status);

[UnmanagedFunctionPointer(CallingConvention.Cdecl)]
internal delegate RustBuffer PreviewSyncConflictResolutionDelegate(
    RustBuffer repoPath,
    RustBuffer conflictId,
    RustBuffer resolution,
    ref RustCallStatus status);

[UnmanagedFunctionPointer(CallingConvention.Cdecl)]
internal delegate RustBuffer ResolveSyncConflictDelegate(
    RustBuffer repoPath,
    RustBuffer conflictId,
    RustBuffer resolution,
    ref RustCallStatus status);

[UnmanagedFunctionPointer(CallingConvention.Cdecl)]
internal delegate RustBuffer SearchFilesDelegate(
    RustBuffer repoPath,
    RustBuffer query,
    RustBuffer filter,
    RustBuffer sort,
    RustBuffer pagination,
    ref RustCallStatus status);

[UnmanagedFunctionPointer(CallingConvention.Cdecl)]
internal delegate RustBuffer RecordWatcherHealthDelegate(
    RustBuffer repoPath,
    RustBuffer signal,
    ref RustCallStatus status);

[UnmanagedFunctionPointer(CallingConvention.Cdecl)]
internal delegate RustBuffer PreviewManualRescanDelegate(RustBuffer repoPath, ref RustCallStatus status);

[UnmanagedFunctionPointer(CallingConvention.Cdecl)]
internal delegate RustBuffer ReindexFromFilesystemDelegate(RustBuffer repoPath, ref RustCallStatus status);

[UnmanagedFunctionPointer(CallingConvention.Cdecl)]
internal delegate RustBuffer GetLatestScanSessionDelegate(RustBuffer repoPath, ref RustCallStatus status);

[UnmanagedFunctionPointer(CallingConvention.Cdecl)]
internal delegate RustBuffer ResumeScanSessionDelegate(
    RustBuffer repoPath,
    long scanSessionId,
    ref RustCallStatus status);

[UnmanagedFunctionPointer(CallingConvention.Cdecl)]
internal delegate RustBuffer RustBufferFromBytesDelegate(ForeignBytes bytes, ref RustCallStatus status);

[UnmanagedFunctionPointer(CallingConvention.Cdecl)]
internal delegate void RustBufferFreeDelegate(RustBuffer buffer, ref RustCallStatus status);

[UnmanagedFunctionPointer(CallingConvention.Cdecl)]
internal delegate ushort ChecksumDelegate();

internal delegate RustBuffer NativeResultCall(ref RustCallStatus status);

internal delegate void NativeVoidCall(ref RustCallStatus status);

[StructLayout(LayoutKind.Sequential)]
internal readonly struct RustBuffer
{
    public RustBuffer(ulong capacity, ulong length, IntPtr data)
    {
        this.capacity = capacity;
        this.length = length;
        this.data = data;
    }

    private readonly ulong capacity;

    private readonly ulong length;

    private readonly IntPtr data;

    public ulong Length => length;

    public IntPtr Data => data;
}

[StructLayout(LayoutKind.Sequential)]
internal readonly struct ForeignBytes
{
    public ForeignBytes(int length, IntPtr data)
    {
        this.length = length;
        this.data = data;
    }

    private readonly int length;

    private readonly IntPtr data;
}

[StructLayout(LayoutKind.Sequential)]
internal struct RustCallStatus
{
    public sbyte Code;
    public RustBuffer ErrorBuffer;

    public static RustCallStatus Success()
    {
        return new RustCallStatus
        {
            Code = 0,
            ErrorBuffer = new RustBuffer(0, 0, IntPtr.Zero)
        };
    }
}
