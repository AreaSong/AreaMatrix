using AreaMatrix.Linux.Features.Onboarding;

namespace AreaMatrix.Linux.Core;

public sealed partial class AreaMatrixNativeCoreClient
{
    public Task<CorePlatformCapabilities> GetPlatformCapabilitiesAsync(
        string platform,
        string appVersion,
        CancellationToken cancellationToken = default)
    {
        cancellationToken.ThrowIfCancellationRequested();
        CorePlatformCapabilities capabilities = CallWithResult(
            (ref RustCallStatus status) => native.GetPlatformCapabilities(
                LowerPlatformId(platform),
                LowerString(appVersion),
                ref status),
            ReadPlatformCapabilities);
        return Task.FromResult(capabilities);
    }

    private static CorePlatformCapabilities ReadPlatformCapabilities(UniFfiReader reader)
    {
        return new CorePlatformCapabilities(
            ReadPlatformId(reader),
            reader.ReadString(),
            ReadPlatformCapabilitySupport(reader),
            ReadPlatformCapabilitySupport(reader),
            ReadPlatformCapabilitySupport(reader),
            ReadPlatformCapabilitySupport(reader),
            ReadPlatformCapabilitySupport(reader));
    }

    private static CorePlatformCapabilitySupport ReadPlatformCapabilitySupport(UniFfiReader reader)
    {
        return new CorePlatformCapabilitySupport(
            ReadPlatformCapabilityStatus(reader),
            reader.ReadBool(),
            reader.ReadBool(),
            ReadOptionalCapabilityReason(reader));
    }

    private RustBuffer LowerPlatformId(string platform)
    {
        List<byte> bytes = [];
        WriteEnum(bytes, platform switch
        {
            "Macos" => 1,
            "Ios" => 2,
            "Windows" => 3,
            "Linux" => 4,
            "Unknown" => 5,
            _ => throw new LinuxRepositoryCoreException(
                LinuxRepositoryErrorKind.Config,
                $"Unsupported platform id `{platform}`.")
        });
        return RustBufferFromBytes(bytes.ToArray());
    }

    private static string ReadPlatformId(UniFfiReader reader)
    {
        return reader.ReadInt32() switch
        {
            1 => "Macos",
            2 => "Ios",
            3 => "Windows",
            4 => "Linux",
            5 => "Unknown",
            _ => throw PlatformCapabilityBindingConfigError(
                "AreaMatrix Core returned an unknown platform id.")
        };
    }

    private static string ReadPlatformCapabilityStatus(UniFfiReader reader)
    {
        return reader.ReadInt32() switch
        {
            1 => "Available",
            2 => "Limited",
            3 => "NotAvailable",
            4 => "Unknown",
            _ => throw PlatformCapabilityBindingConfigError(
                "AreaMatrix Core returned an unknown platform capability status.")
        };
    }

    private static string? ReadOptionalCapabilityReason(UniFfiReader reader)
    {
        return reader.ReadByte() switch
        {
            0 => null,
            1 => reader.ReadString(),
            _ => throw new LinuxRepositoryCoreException(
                LinuxRepositoryErrorKind.Config,
                "AreaMatrix Core returned an invalid optional capability reason tag.")
        };
    }

    private static LinuxRepositoryCoreException PlatformCapabilityBindingConfigError(string message)
    {
        return new LinuxRepositoryCoreException(LinuxRepositoryErrorKind.Config, message);
    }
}
