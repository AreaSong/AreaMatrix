namespace AreaMatrix.Features.Help;

public interface IPlatformDifferencesCoreBridge
{
    Task<PlatformDifferencesBindingContractReport> InspectBindingContractAsync(
        PlatformDifferencesBindingTarget targetPlatform,
        long bindingVersion,
        CancellationToken cancellationToken = default);
}

public interface IAreaMatrixBindingContractCoreClient
{
    Task<CoreBindingContractReport> InspectBindingContractAsync(
        string targetPlatform,
        long bindingVersion,
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
