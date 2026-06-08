using System.Runtime.InteropServices;

namespace AreaMatrix.Linux.Core;

[UnmanagedFunctionPointer(CallingConvention.Cdecl)]
internal delegate RustBuffer ValidateRepoPathDelegate(RustBuffer repoPath, ref RustCallStatus status);

[UnmanagedFunctionPointer(CallingConvention.Cdecl)]
internal delegate void InitRepoDelegate(RustBuffer repoPath, RustBuffer options, ref RustCallStatus status);

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
internal delegate RustBuffer ListTreeJsonDelegate(RustBuffer repoPath, RustBuffer locale, ref RustCallStatus status);

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
