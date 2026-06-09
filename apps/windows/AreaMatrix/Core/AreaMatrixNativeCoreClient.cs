using System;
using System.Collections.Generic;
using System.Runtime.InteropServices;
using System.Text;
using System.Threading;
using System.Threading.Tasks;
using AreaMatrix.Features.Help;
using AreaMatrix.Features.Import;
using AreaMatrix.Features.Library;
using AreaMatrix.Features.Onboarding;

namespace AreaMatrix.Core;

public sealed partial class AreaMatrixNativeCoreClient :
    IAreaMatrixWindowsCoreClient,
    IAreaMatrixBindingContractCoreClient,
    IAreaMatrixDesktopQueryCoreClient,
    IAreaMatrixDesktopImportCoreClient,
    IAreaMatrixWatcherStatusCoreClient,
    IDisposable
{
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

    public Task<CoreRepoConfig> LoadConfigAsync(
        string repoPath,
        CancellationToken cancellationToken = default)
    {
        cancellationToken.ThrowIfCancellationRequested();
        CoreRepoConfig config = CallWithResult(
            (ref RustCallStatus status) => native.LoadConfig(LowerString(repoPath), ref status),
            ReadRepoConfig);
        return Task.FromResult(config);
    }

    public Task<CoreCloudStorageState> DetectCloudStorageStateAsync(
        string repoPath,
        CancellationToken cancellationToken = default)
    {
        cancellationToken.ThrowIfCancellationRequested();
        CoreCloudStorageState state = CallWithResult(
            (ref RustCallStatus status) => native.DetectCloudStorageState(LowerString(repoPath), ref status),
            ReadCloudStorageState);
        return Task.FromResult(state);
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
                throw new WindowsRepositoryCoreException(
                    WindowsRepositoryErrorKind.Unavailable,
                    status.ErrorBuffer.Length > 0
                        ? Lift(status.ErrorBuffer, reader => reader.ReadString())
                        : "AreaMatrix Core failed unexpectedly.");
            default:
                FreeRustBuffer(status.ErrorBuffer);
                throw new WindowsRepositoryCoreException(
                    WindowsRepositoryErrorKind.Unavailable,
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
                throw new WindowsRepositoryCoreException(
                    WindowsRepositoryErrorKind.Config,
                    "AreaMatrix Core returned extra binding data.");
            }

            return value;
        }
        finally
        {
            FreeRustBuffer(buffer);
        }
    }

    private CoreRepoPathValidation ReadRepoPathValidation(UniFfiReader reader)
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

    private CoreRepoConfig ReadRepoConfig(UniFfiReader reader)
    {
        string repoPath = reader.ReadString();
        string defaultMode = ReadStorageMode(reader);
        _ = ReadOverviewOutput(reader);
        _ = reader.ReadBool();
        string locale = reader.ReadString();
        _ = reader.ReadBool();
        _ = reader.ReadBool();
        _ = reader.ReadBool();
        _ = reader.ReadBool();
        _ = reader.ReadBool();
        return new CoreRepoConfig(repoPath, defaultMode, locale);
    }

    private CoreCloudStorageState ReadCloudStorageState(UniFfiReader reader)
    {
        return new CoreCloudStorageState(
            reader.ReadString(),
            ReadCloudStorageProviderKind(reader),
            ReadCloudStorageRiskLevel(reader),
            ReadCloudPlaceholderState(reader),
            ReadCloudPermissionState(reader),
            reader.ReadString(),
            ReadStrings(reader),
            ReadCloudStorageRecommendedAction(reader),
            reader.ReadBool(),
            reader.ReadBool(),
            reader.ReadBool(),
            reader.ReadBool());
    }

    private WindowsRepositoryCoreException ReadCoreError(UniFfiReader reader)
    {
        int variant = reader.ReadInt32();
        string payload = reader.ReadString();
        WindowsRepositoryErrorKind kind = variant switch
        {
            1 => WindowsRepositoryErrorKind.DiskUnavailable,
            2 => WindowsRepositoryErrorKind.Db,
            3 => WindowsRepositoryErrorKind.Config,
            6 => WindowsRepositoryErrorKind.Conflict,
            7 => WindowsRepositoryErrorKind.DuplicateFile,
            8 => WindowsRepositoryErrorKind.FileNotFound,
            10 => WindowsRepositoryErrorKind.InvalidRepository,
            11 => WindowsRepositoryErrorKind.InvalidPath,
            12 => WindowsRepositoryErrorKind.DiskUnavailable,
            13 => WindowsRepositoryErrorKind.Unavailable,
            14 => WindowsRepositoryErrorKind.PermissionDenied,
            _ => WindowsRepositoryErrorKind.Unavailable
        };
        return new WindowsRepositoryCoreException(kind, payload, payload);
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
            _ => throw new WindowsRepositoryCoreException(
                WindowsRepositoryErrorKind.Config,
                $"Unsupported repository init mode `{options.Mode}`.")
        });
        WriteBool(bytes, options.CreateDefaultCategories);
        WriteEnum(bytes, options.OverviewOutput switch
        {
            "GeneratedOnly" => 1,
            "RootAreaMatrixFile" => 2,
            _ => throw new WindowsRepositoryCoreException(
                WindowsRepositoryErrorKind.Config,
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

    private static string ReadOptionalRepoInitMode(UniFfiReader reader)
    {
        return reader.ReadByte() switch
        {
            0 => string.Empty,
            1 => ReadRepoInitMode(reader),
            _ => throw new WindowsRepositoryCoreException(
                WindowsRepositoryErrorKind.Config,
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

    private static IReadOnlyList<string> ReadStrings(UniFfiReader reader)
    {
        int count = reader.ReadInt32();
        List<string> values = new(count);
        for (int index = 0; index < count; index += 1)
        {
            values.Add(reader.ReadString());
        }

        return values;
    }

    private static string ReadRepoInitMode(UniFfiReader reader)
    {
        return reader.ReadInt32() switch
        {
            1 => "CreateEmpty",
            2 => "AdoptExisting",
            _ => throw new WindowsRepositoryCoreException(
                WindowsRepositoryErrorKind.Config,
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
            _ => throw new WindowsRepositoryCoreException(
                WindowsRepositoryErrorKind.Config,
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
            _ => throw new WindowsRepositoryCoreException(
                WindowsRepositoryErrorKind.Config,
                "AreaMatrix Core returned an unknown platform path kind.")
        };
    }

    private static string ReadCloudStorageProviderKind(UniFfiReader reader)
    {
        return reader.ReadInt32() switch
        {
            1 => "Local",
            2 => "ICloudDrive",
            3 => "OneDrive",
            4 => "Unknown",
            _ => throw new WindowsRepositoryCoreException(
                WindowsRepositoryErrorKind.Config,
                "AreaMatrix Core returned an unknown cloud storage provider.")
        };
    }
    private static string ReadCloudStorageRiskLevel(UniFfiReader reader)
    {
        return reader.ReadInt32() switch
        {
            1 => "NoRisk",
            2 => "Low",
            3 => "Medium",
            4 => "High",
            5 => "Unknown",
            _ => throw new WindowsRepositoryCoreException(
                WindowsRepositoryErrorKind.Config,
                "AreaMatrix Core returned an unknown cloud storage risk level.")
        };
    }
    private static string ReadCloudPlaceholderState(UniFfiReader reader)
    {
        return reader.ReadInt32() switch
        {
            1 => "NotPlaceholder",
            2 => "Placeholder",
            3 => "Unknown",
            _ => throw new WindowsRepositoryCoreException(
                WindowsRepositoryErrorKind.Config,
                "AreaMatrix Core returned an unknown cloud placeholder state.")
        };
    }
    private static string ReadCloudPermissionState(UniFfiReader reader)
    {
        return reader.ReadInt32() switch
        {
            1 => "Accessible",
            2 => "PermissionDenied",
            3 => "AccessExpired",
            4 => "Unknown",
            _ => throw new WindowsRepositoryCoreException(
                WindowsRepositoryErrorKind.Config,
                "AreaMatrix Core returned an unknown cloud permission state.")
        };
    }
    private static string ReadCloudStorageRecommendedAction(UniFfiReader reader)
    {
        return reader.ReadInt32() switch
        {
            1 => "None",
            2 => "AcknowledgeNotice",
            3 => "RetryStatusCheck",
            4 => "ReconnectFolder",
            5 => "ChooseLocalFolder",
            _ => throw new WindowsRepositoryCoreException(
                WindowsRepositoryErrorKind.Config,
                "AreaMatrix Core returned an unknown cloud storage recommended action.")
        };
    }

    private static string ReadOverviewOutput(UniFfiReader reader)
    {
        return reader.ReadInt32() switch
        {
            1 => "GeneratedOnly",
            2 => "RootAreaMatrixFile",
            _ => throw new WindowsRepositoryCoreException(
                WindowsRepositoryErrorKind.Config,
                "AreaMatrix Core returned an unknown overview output.")
        };
    }

    private static string ReadStorageMode(UniFfiReader reader)
    {
        return reader.ReadInt32() switch
        {
            1 => "Moved",
            2 => "Copied",
            3 => "Indexed",
            _ => throw new WindowsRepositoryCoreException(
                WindowsRepositoryErrorKind.Config,
                "AreaMatrix Core returned an unknown storage mode.")
        };
    }

}
