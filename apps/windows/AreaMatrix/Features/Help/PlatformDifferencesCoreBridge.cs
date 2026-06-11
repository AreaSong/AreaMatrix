namespace AreaMatrix.Features.Help;

public interface IPlatformDifferencesCoreBridge
{
    Task<PlatformDifferencesBindingContractReport> InspectBindingContractAsync(
        PlatformDifferencesBindingTarget targetPlatform,
        long bindingVersion,
        CancellationToken cancellationToken = default);

    Task<PlatformDifferencesCapabilities> GetPlatformCapabilitiesAsync(
        PlatformDifferencesPlatformId platform,
        string appVersion,
        CancellationToken cancellationToken = default);
}

public interface IAreaMatrixBindingContractCoreClient
{
    Task<CoreBindingContractReport> InspectBindingContractAsync(
        string targetPlatform,
        long bindingVersion,
        CancellationToken cancellationToken = default);

    Task<CorePlatformCapabilities> GetPlatformCapabilitiesAsync(
        string platform,
        string appVersion,
        CancellationToken cancellationToken = default);
}

public sealed class PlatformDifferencesCoreBridge : IPlatformDifferencesCoreBridge
{
    private readonly IAreaMatrixBindingContractCoreClient coreClient;

    public PlatformDifferencesCoreBridge(IAreaMatrixBindingContractCoreClient coreClient)
    {
        this.coreClient = coreClient;
    }

    public async Task<PlatformDifferencesBindingContractReport> InspectBindingContractAsync(
        PlatformDifferencesBindingTarget targetPlatform,
        long bindingVersion,
        CancellationToken cancellationToken = default)
    {
        CoreBindingContractReport report = await coreClient
            .InspectBindingContractAsync(targetPlatform.ToCoreTargetPlatform(), bindingVersion, cancellationToken)
            .ConfigureAwait(false);

        return report.ToPlatformDifferencesReport();
    }

    public async Task<PlatformDifferencesCapabilities> GetPlatformCapabilitiesAsync(
        PlatformDifferencesPlatformId platform,
        string appVersion,
        CancellationToken cancellationToken = default)
    {
        CorePlatformCapabilities capabilities = await coreClient
            .GetPlatformCapabilitiesAsync(platform.ToCorePlatformId(), appVersion, cancellationToken)
            .ConfigureAwait(false);

        return capabilities.ToPlatformDifferencesCapabilities();
    }
}

public enum PlatformDifferencesBindingTarget
{
    Swift,
    Kotlin,
    Python
}

public enum PlatformDifferencesBindingSupportStatus
{
    Supported,
    Limited,
    Missing
}

public sealed record PlatformDifferencesBindingApiContract(
    string Name,
    string Capability,
    PlatformDifferencesBindingSupportStatus Status,
    string? Reason);

public sealed record PlatformDifferencesBindingTypeMapping(
    string RustType,
    string UdlType,
    string TargetType,
    PlatformDifferencesBindingSupportStatus Status,
    string? Reason);

public sealed record PlatformDifferencesBindingMissingCapability(
    string Capability,
    string Label,
    PlatformDifferencesBindingSupportStatus Status,
    string Reason);

public sealed record PlatformDifferencesBindingContractReport(
    PlatformDifferencesBindingTarget TargetPlatform,
    long BindingVersion,
    string CoreVersion,
    IReadOnlyList<PlatformDifferencesBindingApiContract> SupportedApis,
    IReadOnlyList<PlatformDifferencesBindingTypeMapping> TypeMappings,
    IReadOnlyList<PlatformDifferencesBindingMissingCapability> MissingCapabilities);

public sealed record CoreBindingApiContract(
    string Name,
    string Capability,
    string Status,
    string? Reason);

public sealed record CoreBindingTypeMapping(
    string RustType,
    string UdlType,
    string TargetType,
    string Status,
    string? Reason);

public sealed record CoreBindingMissingCapability(
    string Capability,
    string Label,
    string Status,
    string Reason);

public sealed record CoreBindingContractReport(
    string TargetPlatform,
    long BindingVersion,
    string CoreVersion,
    IReadOnlyList<CoreBindingApiContract> SupportedApis,
    IReadOnlyList<CoreBindingTypeMapping> TypeMappings,
    IReadOnlyList<CoreBindingMissingCapability> MissingCapabilities)
{
    public PlatformDifferencesBindingContractReport ToPlatformDifferencesReport()
    {
        return new PlatformDifferencesBindingContractReport(
            ParseTargetPlatform(TargetPlatform),
            BindingVersion,
            CoreVersion,
            SupportedApis.Select(item => new PlatformDifferencesBindingApiContract(
                item.Name,
                item.Capability,
                ParseSupportStatus(item.Status),
                item.Reason)).ToArray(),
            TypeMappings.Select(item => new PlatformDifferencesBindingTypeMapping(
                item.RustType,
                item.UdlType,
                item.TargetType,
                ParseSupportStatus(item.Status),
                item.Reason)).ToArray(),
            MissingCapabilities.Select(item => new PlatformDifferencesBindingMissingCapability(
                item.Capability,
                item.Label,
                ParseSupportStatus(item.Status),
                item.Reason)).ToArray());
    }

    private static PlatformDifferencesBindingTarget ParseTargetPlatform(string value)
    {
        return value switch
        {
            "Swift" => PlatformDifferencesBindingTarget.Swift,
            "Kotlin" => PlatformDifferencesBindingTarget.Kotlin,
            "Python" => PlatformDifferencesBindingTarget.Python,
            _ => throw new InvalidOperationException($"Unknown binding target platform `{value}`.")
        };
    }

    private static PlatformDifferencesBindingSupportStatus ParseSupportStatus(string value)
    {
        return value switch
        {
            "Supported" => PlatformDifferencesBindingSupportStatus.Supported,
            "Limited" => PlatformDifferencesBindingSupportStatus.Limited,
            "Missing" => PlatformDifferencesBindingSupportStatus.Missing,
            _ => throw new InvalidOperationException($"Unknown binding support status `{value}`.")
        };
    }
}

public sealed record CorePlatformCapabilitySupport(
    string Status,
    bool UiEnabled,
    bool RequiresPermission,
    string? Reason)
{
    public PlatformDifferencesCapabilitySupport ToPlatformDifferencesSupport()
    {
        return new PlatformDifferencesCapabilitySupport(
            ParseCapabilityStatus(Status),
            UiEnabled,
            RequiresPermission,
            Reason);
    }

    private static PlatformDifferencesCapabilityStatus ParseCapabilityStatus(string value)
    {
        return value switch
        {
            "Available" => PlatformDifferencesCapabilityStatus.Available,
            "Limited" => PlatformDifferencesCapabilityStatus.Limited,
            "NotAvailable" => PlatformDifferencesCapabilityStatus.NotAvailable,
            "Unknown" => PlatformDifferencesCapabilityStatus.Unknown,
            _ => throw new InvalidOperationException($"Unknown platform capability status `{value}`.")
        };
    }
}

public sealed record CorePlatformCapabilities(
    string Platform,
    string AppVersion,
    CorePlatformCapabilitySupport Watcher,
    CorePlatformCapabilitySupport Trash,
    CorePlatformCapabilitySupport ShareExtension,
    CorePlatformCapabilitySupport CloudPlaceholder,
    CorePlatformCapabilitySupport SecurityBookmark)
{
    public PlatformDifferencesCapabilities ToPlatformDifferencesCapabilities()
    {
        return new PlatformDifferencesCapabilities(
            ParsePlatformId(Platform),
            AppVersion,
            Watcher.ToPlatformDifferencesSupport(),
            Trash.ToPlatformDifferencesSupport(),
            ShareExtension.ToPlatformDifferencesSupport(),
            CloudPlaceholder.ToPlatformDifferencesSupport(),
            SecurityBookmark.ToPlatformDifferencesSupport());
    }

    private static PlatformDifferencesPlatformId ParsePlatformId(string value)
    {
        return value switch
        {
            "Macos" => PlatformDifferencesPlatformId.Macos,
            "Ios" => PlatformDifferencesPlatformId.Ios,
            "Windows" => PlatformDifferencesPlatformId.Windows,
            "Linux" => PlatformDifferencesPlatformId.Linux,
            "Unknown" => PlatformDifferencesPlatformId.Unknown,
            _ => throw new InvalidOperationException($"Unknown platform id `{value}`.")
        };
    }
}

internal static class PlatformDifferencesBindingTargetExtensions
{
    public static string ToCoreTargetPlatform(this PlatformDifferencesBindingTarget targetPlatform)
    {
        return targetPlatform switch
        {
            PlatformDifferencesBindingTarget.Swift => "Swift",
            PlatformDifferencesBindingTarget.Kotlin => "Kotlin",
            PlatformDifferencesBindingTarget.Python => "Python",
            _ => throw new InvalidOperationException($"Unknown binding target platform `{targetPlatform}`.")
        };
    }
}

internal static class PlatformDifferencesPlatformIdExtensions
{
    public static string ToCorePlatformId(this PlatformDifferencesPlatformId platform)
    {
        return platform switch
        {
            PlatformDifferencesPlatformId.Macos => "Macos",
            PlatformDifferencesPlatformId.Ios => "Ios",
            PlatformDifferencesPlatformId.Windows => "Windows",
            PlatformDifferencesPlatformId.Linux => "Linux",
            PlatformDifferencesPlatformId.Unknown => "Unknown",
            _ => throw new InvalidOperationException($"Unknown platform id `{platform}`.")
        };
    }
}
