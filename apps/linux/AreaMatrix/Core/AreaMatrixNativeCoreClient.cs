using System.Text;
using System.Runtime.InteropServices;
using AreaMatrix.Linux.Features.Import;
using AreaMatrix.Linux.Features.Library;
using AreaMatrix.Linux.Features.Onboarding;
using AreaMatrix.Linux.Features.System;

namespace AreaMatrix.Linux.Core;

public sealed partial class AreaMatrixNativeCoreClient :
    IAreaMatrixLinuxCoreClient,
    IAreaMatrixLinuxDesktopQueryCoreClient,
    IAreaMatrixLinuxDesktopImportCoreClient,
    IAreaMatrixLinuxWatcherStatusCoreClient,
    IDisposable
{
    private const ushort InitRepoChecksum = 29414;
    private const ushort ValidateRepoPathChecksum = 43498;
    private const ushort PredictCategoryChecksum = 65047;
    private const ushort ImportFileWithResultChecksum = 52959;
    private const ushort PreviewImportConflictBatchChecksum = 52321;
    private const ushort ApplyImportConflictBatchChecksum = 14573;
    private const ushort GetPlatformCapabilitiesChecksum = 42907;
    private const ushort GetFileChecksum = 6132;
    private const ushort ListFilesChecksum = 56809;
    private const ushort ListTreeJsonChecksum = 45468;
    private const ushort SearchFilesChecksum = 65;
    private const ushort RecordWatcherHealthChecksum = 47455;
    private const ushort PreviewManualRescanChecksum = 12140;
    private const ushort ReindexFromFilesystemChecksum = 54635;
    private const ushort GetLatestScanSessionChecksum = 31155;
    private const ushort ResumeScanSessionChecksum = 31216;

    private readonly NativeCoreLibrary native;
    private bool disposed;

    public AreaMatrixNativeCoreClient()
        : this(NativeCoreLibrary.LoadDefault())
    {
    }

    public AreaMatrixNativeCoreClient(string libraryPath)
        : this(NativeCoreLibrary.Load(libraryPath))
    {
    }

    private AreaMatrixNativeCoreClient(NativeCoreLibrary native)
    {
        this.native = native;
        VerifyContract();
    }

    public Task<CoreRepoPathValidation> ValidateRepoPathAsync(
        string repoPath,
        CancellationToken cancellationToken = default)
    {
        cancellationToken.ThrowIfCancellationRequested();
        CoreRepoPathValidation validation = CallWithResult(
            (ref RustCallStatus status) => native.ValidateRepoPath(LowerString(repoPath), ref status),
            ReadRepoPathValidation);
        return Task.FromResult(validation);
    }

    public Task InitRepoAsync(
        string repoPath,
        CoreRepoInitOptions options,
        CancellationToken cancellationToken = default)
    {
        cancellationToken.ThrowIfCancellationRequested();
        CallVoid((ref RustCallStatus status) => native.InitRepo(
            LowerString(repoPath),
            LowerRepoInitOptions(options),
            ref status));
        return Task.CompletedTask;
    }

    public void Dispose()
    {
        if (disposed)
        {
            return;
        }

        native.Dispose();
        disposed = true;
    }

    private void VerifyContract()
    {
        if (native.InitRepoChecksum() != InitRepoChecksum
            || native.ValidateRepoPathChecksum() != ValidateRepoPathChecksum
            || native.PredictCategoryChecksum() != PredictCategoryChecksum
            || native.ImportFileWithResultChecksum() != ImportFileWithResultChecksum
            || native.PreviewImportConflictBatchChecksum() != PreviewImportConflictBatchChecksum
            || native.ApplyImportConflictBatchChecksum() != ApplyImportConflictBatchChecksum
            || native.GetPlatformCapabilitiesChecksum() != GetPlatformCapabilitiesChecksum
            || native.GetFileChecksum() != GetFileChecksum
            || native.ListFilesChecksum() != ListFilesChecksum
            || native.ListTreeJsonChecksum() != ListTreeJsonChecksum
            || native.SearchFilesChecksum() != SearchFilesChecksum
            || native.RecordWatcherHealthChecksum() != RecordWatcherHealthChecksum
            || native.PreviewManualRescanChecksum() != PreviewManualRescanChecksum
            || native.ReindexFromFilesystemChecksum() != ReindexFromFilesystemChecksum
            || native.GetLatestScanSessionChecksum() != GetLatestScanSessionChecksum
            || native.ResumeScanSessionChecksum() != ResumeScanSessionChecksum)
        {
            throw new LinuxRepositoryCoreException(
                LinuxRepositoryErrorKind.Config,
                "AreaMatrix Core binding checksum mismatch.");
        }
    }

    private T CallWithResult<T>(
        NativeResultCall call,
        Func<UniFfiReader, T> read)
    {
        RustCallStatus status = RustCallStatus.Success();
        RustBuffer buffer = call(ref status);
        CheckCallStatus(status);
        return Lift(buffer, read);
    }

    private void CallVoid(NativeVoidCall call)
    {
        RustCallStatus status = RustCallStatus.Success();
        call(ref status);
        CheckCallStatus(status);
    }

    private void CheckCallStatus(RustCallStatus status)
    {
        switch (status.Code)
        {
            case 0:
                return;
            case 1:
                throw Lift(status.ErrorBuffer, ReadCoreError);
            case 2:
                throw new LinuxRepositoryCoreException(
                    LinuxRepositoryErrorKind.Unavailable,
                    status.ErrorBuffer.Length > 0
                        ? Lift(status.ErrorBuffer, reader => reader.ReadString())
                        : "AreaMatrix Core failed unexpectedly.");
            default:
                FreeRustBuffer(status.ErrorBuffer);
                throw new LinuxRepositoryCoreException(
                    LinuxRepositoryErrorKind.Unavailable,
                    "AreaMatrix Core returned an unsupported call status.");
        }
    }

    private T Lift<T>(RustBuffer buffer, Func<UniFfiReader, T> read)
    {
        try
        {
            byte[] bytes = ReadBufferBytes(buffer);
            UniFfiReader reader = new(bytes);
            T value = read(reader);
            if (!reader.IsAtEnd)
            {
                throw new LinuxRepositoryCoreException(
                    LinuxRepositoryErrorKind.Config,
                    "AreaMatrix Core returned extra binding data.");
            }

            return value;
        }
        finally
        {
            FreeRustBuffer(buffer);
        }
    }

    private static CoreRepoPathValidation ReadRepoPathValidation(UniFfiReader reader)
    {
        return new CoreRepoPathValidation(
            reader.ReadString(),
            reader.ReadBool(),
            reader.ReadBool(),
            reader.ReadBool(),
            reader.ReadBool(),
            reader.ReadBool(),
            reader.ReadBool(),
            reader.ReadBool(),
            reader.ReadBool(),
            reader.ReadBool(),
            ReadPlatformPathKind(reader),
            reader.ReadBool(),
            reader.ReadBool(),
            ReadOptionalRepoInitMode(reader),
            ReadRepoPathIssues(reader));
    }

    private static LinuxRepositoryCoreException ReadCoreError(UniFfiReader reader)
    {
        int variant = reader.ReadInt32();
        string payload = reader.ReadString();
        LinuxRepositoryErrorKind kind = variant switch
        {
            1 => LinuxRepositoryErrorKind.DiskUnavailable,
            2 => LinuxRepositoryErrorKind.Db,
            3 => LinuxRepositoryErrorKind.Config,
            8 => LinuxRepositoryErrorKind.FileNotFound,
            10 => LinuxRepositoryErrorKind.RepoNotInitialized,
            11 => LinuxRepositoryErrorKind.InvalidPath,
            12 => LinuxRepositoryErrorKind.ICloudPlaceholder,
            13 => LinuxRepositoryErrorKind.InvalidRepository,
            14 => LinuxRepositoryErrorKind.PermissionDenied,
            _ => LinuxRepositoryErrorKind.Unavailable
        };
        return new LinuxRepositoryCoreException(kind, payload, payload);
    }

    private RustBuffer LowerString(string value)
    {
        byte[] bytes = Encoding.UTF8.GetBytes(value);
        return RustBufferFromBytes(bytes);
    }

    private RustBuffer LowerRepoInitOptions(CoreRepoInitOptions options)
    {
        List<byte> bytes = [];
        WriteEnum(bytes, options.Mode switch
        {
            "CreateEmpty" => 1,
            "AdoptExisting" => 2,
            _ => throw new LinuxRepositoryCoreException(
                LinuxRepositoryErrorKind.Config,
                $"Unsupported repository init mode `{options.Mode}`.")
        });
        WriteBool(bytes, options.CreateDefaultCategories);
        WriteEnum(bytes, options.OverviewOutput switch
        {
            "GeneratedOnly" => 1,
            "RootAreaMatrixFile" => 2,
            _ => throw new LinuxRepositoryCoreException(
                LinuxRepositoryErrorKind.Config,
                $"Unsupported overview output `{options.OverviewOutput}`.")
        });
        return RustBufferFromBytes(bytes.ToArray());
    }

    private RustBuffer RustBufferFromBytes(byte[] bytes)
    {
        GCHandle handle = GCHandle.Alloc(bytes, GCHandleType.Pinned);
        try
        {
            RustCallStatus status = RustCallStatus.Success();
            ForeignBytes foreignBytes = new(bytes.Length, handle.AddrOfPinnedObject());
            RustBuffer buffer = native.RustBufferFromBytes(foreignBytes, ref status);
            CheckCallStatus(status);
            return buffer;
        }
        finally
        {
            handle.Free();
        }
    }

    private static byte[] ReadBufferBytes(RustBuffer buffer)
    {
        if (buffer.Data == IntPtr.Zero || buffer.Length == 0)
        {
            return [];
        }

        byte[] bytes = new byte[checked((int)buffer.Length)];
        Marshal.Copy(buffer.Data, bytes, 0, bytes.Length);
        return bytes;
    }

    private void FreeRustBuffer(RustBuffer buffer)
    {
        if (buffer.Data == IntPtr.Zero)
        {
            return;
        }

        RustCallStatus status = RustCallStatus.Success();
        native.RustBufferFree(buffer, ref status);
    }

    private static string? ReadOptionalRepoInitMode(UniFfiReader reader)
    {
        return reader.ReadByte() switch
        {
            0 => null,
            1 => ReadRepoInitMode(reader),
            _ => throw new LinuxRepositoryCoreException(
                LinuxRepositoryErrorKind.Config,
                "AreaMatrix Core returned an invalid optional tag.")
        };
    }

    private static IReadOnlyList<string> ReadRepoPathIssues(UniFfiReader reader)
    {
        int count = reader.ReadInt32();
        List<string> issues = new(count);
        for (int index = 0; index < count; index += 1)
        {
            issues.Add(ReadRepoPathIssue(reader));
        }

        return issues;
    }

    private static string ReadRepoInitMode(UniFfiReader reader)
    {
        return reader.ReadInt32() switch
        {
            1 => "CreateEmpty",
            2 => "AdoptExisting",
            _ => throw new LinuxRepositoryCoreException(
                LinuxRepositoryErrorKind.Config,
                "AreaMatrix Core returned an unknown repository init mode.")
        };
    }

    private static string ReadRepoPathIssue(UniFfiReader reader)
    {
        return reader.ReadInt32() switch
        {
            1 => "MissingPath",
            2 => "NotDirectory",
            3 => "NotReadable",
            4 => "NotWritable",
            5 => "NonEmptyDirectory",
            6 => "AlreadyInitialized",
            7 => "InsideAreaMatrix",
            8 => "ICloudPath",
            9 => "OneDrivePath",
            10 => "WindowsReservedName",
            11 => "WindowsCaseInsensitive",
            12 => "UnfinishedScanSession",
            _ => throw new LinuxRepositoryCoreException(
                LinuxRepositoryErrorKind.Config,
                "AreaMatrix Core returned an unknown repository path issue.")
        };
    }

    private static string ReadPlatformPathKind(UniFfiReader reader)
    {
        return reader.ReadInt32() switch
        {
            1 => "Local",
            2 => "ICloudDrive",
            3 => "OneDrive",
            4 => "NetworkShare",
            5 => "Unknown",
            _ => throw new LinuxRepositoryCoreException(
                LinuxRepositoryErrorKind.Config,
                "AreaMatrix Core returned an unknown platform path kind.")
        };
    }

    private static void WriteEnum(List<byte> bytes, int tag)
    {
        bytes.AddRange(BitConverter.GetBytes(System.Net.IPAddress.HostToNetworkOrder(tag)));
    }

    private static void WriteBool(List<byte> bytes, bool value)
    {
        bytes.Add(value ? (byte)1 : (byte)0);
    }
}
