using AreaMatrix.Linux.Features.Help;
using AreaMatrix.Linux.Features.Onboarding;

namespace AreaMatrix.Linux.Core;

public sealed partial class AreaMatrixNativeCoreClient
{
    public Task<CoreBindingContractReport> InspectBindingContractAsync(
        string targetPlatform,
        long bindingVersion,
        CancellationToken cancellationToken = default)
    {
        cancellationToken.ThrowIfCancellationRequested();
        RustBuffer request = LowerBindingContractRequest(targetPlatform, bindingVersion);
        CoreBindingContractReport report = CallWithResult(
            (ref RustCallStatus status) => native.InspectBindingContract(request, ref status),
            ReadBindingContractReport);
        return Task.FromResult(report);
    }

    private RustBuffer LowerBindingContractRequest(string targetPlatform, long bindingVersion)
    {
        List<byte> bytes = [];
        WriteEnum(bytes, targetPlatform switch
        {
            "Swift" => 1,
            "Kotlin" => 2,
            "Python" => 3,
            _ => throw new LinuxRepositoryCoreException(
                LinuxRepositoryErrorKind.Config,
                $"Unsupported binding target platform `{targetPlatform}`.")
        });
        WriteInt64(bytes, bindingVersion);
        return RustBufferFromBytes(bytes.ToArray());
    }

    private static CoreBindingContractReport ReadBindingContractReport(UniFfiReader reader)
    {
        return new CoreBindingContractReport(
            ReadBindingTargetPlatform(reader),
            reader.ReadInt64(),
            reader.ReadString(),
            ReadBindingApiContracts(reader),
            ReadBindingTypeMappings(reader),
            ReadBindingMissingCapabilities(reader));
    }

    private static IReadOnlyList<CoreBindingApiContract> ReadBindingApiContracts(UniFfiReader reader)
    {
        int count = reader.ReadInt32();
        List<CoreBindingApiContract> values = new(count);
        for (int index = 0; index < count; index += 1)
        {
            values.Add(new CoreBindingApiContract(
                reader.ReadString(),
                reader.ReadString(),
                ReadBindingSupportStatus(reader),
                ReadBindingOptionalString(reader)));
        }

        return values;
    }

    private static IReadOnlyList<CoreBindingTypeMapping> ReadBindingTypeMappings(UniFfiReader reader)
    {
        int count = reader.ReadInt32();
        List<CoreBindingTypeMapping> values = new(count);
        for (int index = 0; index < count; index += 1)
        {
            values.Add(new CoreBindingTypeMapping(
                reader.ReadString(),
                reader.ReadString(),
                reader.ReadString(),
                ReadBindingSupportStatus(reader),
                ReadBindingOptionalString(reader)));
        }

        return values;
    }

    private static IReadOnlyList<CoreBindingMissingCapability> ReadBindingMissingCapabilities(
        UniFfiReader reader)
    {
        int count = reader.ReadInt32();
        List<CoreBindingMissingCapability> values = new(count);
        for (int index = 0; index < count; index += 1)
        {
            values.Add(new CoreBindingMissingCapability(
                reader.ReadString(),
                reader.ReadString(),
                ReadBindingSupportStatus(reader),
                reader.ReadString()));
        }

        return values;
    }

    private static string ReadBindingTargetPlatform(UniFfiReader reader)
    {
        return reader.ReadInt32() switch
        {
            1 => "Swift",
            2 => "Kotlin",
            3 => "Python",
            _ => throw new LinuxRepositoryCoreException(
                LinuxRepositoryErrorKind.Config,
                "AreaMatrix Core returned an unknown binding target platform.")
        };
    }

    private static string ReadBindingSupportStatus(UniFfiReader reader)
    {
        return reader.ReadInt32() switch
        {
            1 => "Supported",
            2 => "Limited",
            3 => "Missing",
            _ => throw new LinuxRepositoryCoreException(
                LinuxRepositoryErrorKind.Config,
                "AreaMatrix Core returned an unknown binding support status.")
        };
    }

    private static string? ReadBindingOptionalString(UniFfiReader reader)
    {
        return reader.ReadByte() switch
        {
            0 => null,
            1 => reader.ReadString(),
            _ => throw new LinuxRepositoryCoreException(
                LinuxRepositoryErrorKind.Config,
                "AreaMatrix Core returned an invalid optional string tag.")
        };
    }
}
