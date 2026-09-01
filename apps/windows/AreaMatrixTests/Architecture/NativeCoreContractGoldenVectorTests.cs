using System.Buffers.Binary;
using System.Text;
using AreaMatrix.Core;
using AreaMatrix.Features.Onboarding;
using AreaMatrixTests.ChooseRepository;

namespace AreaMatrixTests.Architecture;

public static class NativeCoreContractGoldenVectorTests
{
    public static void RunAll()
    {
        CoreErrorVariantsMatchTheUdlContract();
        RevisionConflictPreservesBothRevisions();
        UnknownAndTrailingCoreErrorDataFailClosed();
        RepositoryBridgePreservesRevisionAndLocalePolicy();
    }

    private static void CoreErrorVariantsMatchTheUdlContract()
    {
        (int Variant, WindowsRepositoryErrorKind Kind, string Name)[] vectors =
        [
            (1, WindowsRepositoryErrorKind.DiskUnavailable, "Io"),
            (2, WindowsRepositoryErrorKind.Db, "Db"),
            (3, WindowsRepositoryErrorKind.DbLocked, "DbLocked"),
            (4, WindowsRepositoryErrorKind.DbCorrupted, "DbCorrupted"),
            (5, WindowsRepositoryErrorKind.Config, "Config"),
            (6, WindowsRepositoryErrorKind.Validation, "Validation"),
            (7, WindowsRepositoryErrorKind.Classify, "Classify"),
            (8, WindowsRepositoryErrorKind.Conflict, "Conflict"),
            (10, WindowsRepositoryErrorKind.DuplicateFile, "DuplicateFile"),
            (11, WindowsRepositoryErrorKind.FileNotFound, "FileNotFound"),
            (12, WindowsRepositoryErrorKind.ExpiredAction, "ExpiredAction"),
            (13, WindowsRepositoryErrorKind.RepoNotInitialized, "RepoNotInitialized"),
            (14, WindowsRepositoryErrorKind.InvalidPath, "InvalidPath"),
            (15, WindowsRepositoryErrorKind.ICloudPlaceholder, "ICloudPlaceholder"),
            (16, WindowsRepositoryErrorKind.StagingRecoveryRequired, "StagingRecoveryRequired"),
            (17, WindowsRepositoryErrorKind.PermissionDenied, "PermissionDenied"),
            (18, WindowsRepositoryErrorKind.Internal, "Internal")
        ];

        foreach ((int variant, WindowsRepositoryErrorKind kind, string name) in vectors)
        {
            WindowsRepositoryCoreException error = AreaMatrixNativeCoreClient.DecodeCoreErrorForTest(
                ErrorVector(variant, $"payload-{variant}"));
            TestAssert.Equal(kind, error.Kind, $"CoreError {name} kind");
            TestAssert.Equal(name, error.CoreErrorVariant, $"CoreError {name} variant");
        }
    }

    private static void RevisionConflictPreservesBothRevisions()
    {
        WindowsRepositoryCoreException error = AreaMatrixNativeCoreClient.DecodeCoreErrorForTest(
            RevisionConflictVector("repo-config", 41, 42));

        TestAssert.Equal(WindowsRepositoryErrorKind.RevisionConflict, error.Kind, "RevisionConflict kind");
        TestAssert.Equal("RevisionConflict", error.CoreErrorVariant, "RevisionConflict variant");
        TestAssert.Equal("repo-config", error.Path, "RevisionConflict resource");
        TestAssert.Equal(41L, error.ExpectedRevision, "RevisionConflict expected revision");
        TestAssert.Equal(42L, error.CurrentRevision, "RevisionConflict current revision");
    }

    private static void UnknownAndTrailingCoreErrorDataFailClosed()
    {
        AssertThrows<WindowsRepositoryCoreException>(
            () => AreaMatrixNativeCoreClient.DecodeCoreErrorForTest(ErrorVector(99, "unknown")),
            "unknown CoreError variant");

        byte[] trailing = [.. ErrorVector(1, "io"), 0x7f];
        AssertThrows<WindowsRepositoryCoreException>(
            () => AreaMatrixNativeCoreClient.DecodeCoreErrorForTest(trailing),
            "trailing CoreError data");
    }

    private static void RepositoryBridgePreservesRevisionAndLocalePolicy()
    {
        CoreRepoConfig source = new(
            @"C:\Repos\AreaMatrix",
            "Copied",
            "zh-Hans",
            Revision: 12,
            LocalePolicyState: "ZhHans");
        FakeWindowsCoreClient client = new(source);
        WindowsRepositoryCoreBridge bridge = new(client);

        WindowsRepositoryConfig loaded = bridge.LoadConfigAsync(source.RepoPath).GetAwaiter().GetResult();
        TestAssert.Equal(12L, loaded.Revision, "bridge loaded revision");
        TestAssert.Equal("ZhHans", loaded.LocalePolicyState, "bridge loaded locale policy");

        bridge.UpdateConfigAsync(source.RepoPath, loaded with { Revision = 13 }).GetAwaiter().GetResult();
        TestAssert.Equal(13L, client.LastConfig?.Revision, "bridge updated revision");
        TestAssert.Equal("ZhHans", client.LastConfig?.LocalePolicyState, "bridge updated locale policy");
    }

    private static byte[] ErrorVector(int variant, string payload)
    {
        List<byte> bytes = [];
        WriteInt32(bytes, variant);
        WriteString(bytes, payload);
        return [.. bytes];
    }

    private static byte[] RevisionConflictVector(string resource, long expected, long current)
    {
        List<byte> bytes = [];
        WriteInt32(bytes, 9);
        WriteString(bytes, resource);
        WriteInt64(bytes, expected);
        WriteInt64(bytes, current);
        return [.. bytes];
    }

    private static void WriteString(List<byte> bytes, string value)
    {
        byte[] utf8 = Encoding.UTF8.GetBytes(value);
        WriteInt32(bytes, utf8.Length);
        bytes.AddRange(utf8);
    }

    private static void WriteInt32(List<byte> bytes, int value)
    {
        Span<byte> buffer = stackalloc byte[4];
        BinaryPrimitives.WriteInt32BigEndian(buffer, value);
        bytes.AddRange(buffer.ToArray());
    }

    private static void WriteInt64(List<byte> bytes, long value)
    {
        Span<byte> buffer = stackalloc byte[8];
        BinaryPrimitives.WriteInt64BigEndian(buffer, value);
        bytes.AddRange(buffer.ToArray());
    }

    private static void AssertThrows<TException>(Action action, string label)
        where TException : Exception
    {
        try
        {
            action();
        }
        catch (TException)
        {
            return;
        }

        throw new InvalidOperationException($"{label}: expected {typeof(TException).Name}.");
    }

    private sealed class FakeWindowsCoreClient(CoreRepoConfig config) : IAreaMatrixWindowsCoreClient
    {
        public CoreRepoConfig? LastConfig { get; private set; }

        public Task<CoreRepoPathValidation> ValidateRepoPathAsync(
            string repoPath,
            CancellationToken cancellationToken = default) => throw new NotSupportedException();

        public Task<CoreCloudStorageState> DetectCloudStorageStateAsync(
            string repoPath,
            CancellationToken cancellationToken = default) => throw new NotSupportedException();

        public Task<CoreCloudStorageState> AcknowledgeOneDriveRiskNoticeAsync(
            string repoPath,
            CancellationToken cancellationToken = default) => throw new NotSupportedException();

        public Task<CoreRepoConfig> LoadConfigAsync(
            string repoPath,
            CancellationToken cancellationToken = default) => Task.FromResult(config);

        public Task UpdateConfigAsync(
            string repoPath,
            CoreRepoConfig newConfig,
            CancellationToken cancellationToken = default)
        {
            LastConfig = newConfig;
            return Task.CompletedTask;
        }

        public Task InitRepoAsync(
            string repoPath,
            CoreRepoInitOptions options,
            CancellationToken cancellationToken = default) => throw new NotSupportedException();
    }
}
