using System.Buffers.Binary;
using System.Text;
using AreaMatrix.Linux.Core;
using AreaMatrix.Linux.Features.Onboarding;

namespace AreaMatrix.Linux.Tests.ChooseRepository;

public static class LinuxNativeCoreContractGoldenVectorTests
{
    public static void RunAll()
    {
        CoreErrorVariantsMatchTheUdlContract();
        RevisionConflictPreservesBothRevisions();
        UnknownAndTrailingCoreErrorDataFailClosed();
    }

    private static void CoreErrorVariantsMatchTheUdlContract()
    {
        (int Variant, LinuxRepositoryErrorKind Kind, string Name)[] vectors =
        [
            (1, LinuxRepositoryErrorKind.DiskUnavailable, "Io"),
            (2, LinuxRepositoryErrorKind.Db, "Db"),
            (3, LinuxRepositoryErrorKind.DbLocked, "DbLocked"),
            (4, LinuxRepositoryErrorKind.DbCorrupted, "DbCorrupted"),
            (5, LinuxRepositoryErrorKind.Config, "Config"),
            (6, LinuxRepositoryErrorKind.Validation, "Validation"),
            (7, LinuxRepositoryErrorKind.Classify, "Classify"),
            (8, LinuxRepositoryErrorKind.Conflict, "Conflict"),
            (10, LinuxRepositoryErrorKind.DuplicateFile, "DuplicateFile"),
            (11, LinuxRepositoryErrorKind.FileNotFound, "FileNotFound"),
            (12, LinuxRepositoryErrorKind.ExpiredAction, "ExpiredAction"),
            (13, LinuxRepositoryErrorKind.RepoNotInitialized, "RepoNotInitialized"),
            (14, LinuxRepositoryErrorKind.InvalidPath, "InvalidPath"),
            (15, LinuxRepositoryErrorKind.ICloudPlaceholder, "ICloudPlaceholder"),
            (16, LinuxRepositoryErrorKind.StagingRecoveryRequired, "StagingRecoveryRequired"),
            (17, LinuxRepositoryErrorKind.PermissionDenied, "PermissionDenied"),
            (18, LinuxRepositoryErrorKind.Internal, "Internal")
        ];

        foreach ((int variant, LinuxRepositoryErrorKind kind, string name) in vectors)
        {
            LinuxRepositoryCoreException error = AreaMatrixNativeCoreClient.DecodeCoreErrorForTest(
                ErrorVector(variant, $"payload-{variant}"));
            TestAssert.Equal(kind, error.Kind, $"CoreError {name} kind");
            TestAssert.Equal(name, error.CoreErrorVariant, $"CoreError {name} variant");
        }
    }

    private static void RevisionConflictPreservesBothRevisions()
    {
        LinuxRepositoryCoreException error = AreaMatrixNativeCoreClient.DecodeCoreErrorForTest(
            RevisionConflictVector("repo-config", 41, 42));

        TestAssert.Equal(LinuxRepositoryErrorKind.RevisionConflict, error.Kind, "RevisionConflict kind");
        TestAssert.Equal("RevisionConflict", error.CoreErrorVariant, "RevisionConflict variant");
        TestAssert.Equal("repo-config", error.Path, "RevisionConflict resource");
        TestAssert.Equal(41L, error.ExpectedRevision, "RevisionConflict expected revision");
        TestAssert.Equal(42L, error.CurrentRevision, "RevisionConflict current revision");
    }

    private static void UnknownAndTrailingCoreErrorDataFailClosed()
    {
        AssertThrows<LinuxRepositoryCoreException>(
            () => AreaMatrixNativeCoreClient.DecodeCoreErrorForTest(ErrorVector(99, "unknown")),
            "unknown CoreError variant");

        byte[] trailing = [.. ErrorVector(1, "io"), 0x7f];
        AssertThrows<LinuxRepositoryCoreException>(
            () => AreaMatrixNativeCoreClient.DecodeCoreErrorForTest(trailing),
            "trailing CoreError data");
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
}
