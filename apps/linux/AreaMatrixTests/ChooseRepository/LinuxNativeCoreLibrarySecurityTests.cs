using System.Security.Cryptography;
using System.Text.Json;
using AreaMatrix.Linux.Core;
using AreaMatrix.Linux.Features.Onboarding;

namespace AreaMatrix.Linux.Tests.ChooseRepository;

public static class LinuxNativeCoreLibrarySecurityTests
{
    public static void RunAll()
    {
        VerifiedFixtureManifestAcceptsMatchingRegularFile();
        VerificationRejectsHashRuntimeAndLinkMismatch();
        DevelopmentOverrideRequiresExplicitOptIn();
        DefaultLaunchFailsClosedWithoutVerifiedPackage();
        LinuxProjectRemainsFixtureOnly();
    }

    private static void VerifiedFixtureManifestAcceptsMatchingRegularFile()
    {
        using NativeFixture fixture = NativeFixture.Create();
        string resolved = NativeCoreLibrary.VerifyLibrary(
            fixture.LibraryPath,
            fixture.ManifestPath,
            "linux-x64",
            "x64");

        TestAssert.Equal(fixture.LibraryPath, resolved, "verified Linux fixture library path");
    }

    private static void VerificationRejectsHashRuntimeAndLinkMismatch()
    {
        using NativeFixture hashFixture = NativeFixture.Create();
        File.AppendAllText(hashFixture.LibraryPath, "tampered");
        AssertThrows<LinuxRepositoryCoreException>(
            () => NativeCoreLibrary.VerifyLibrary(
                hashFixture.LibraryPath,
                hashFixture.ManifestPath,
                "linux-x64",
                "x64"),
            "tampered Linux fixture hash");

        using NativeFixture runtimeFixture = NativeFixture.Create();
        AssertThrows<LinuxRepositoryCoreException>(
            () => NativeCoreLibrary.VerifyLibrary(
                runtimeFixture.LibraryPath,
                runtimeFixture.ManifestPath,
                "linux-arm64",
                "arm64"),
            "Linux RID mismatch");

        using NativeFixture linkFixture = NativeFixture.Create();
        string linkPath = Path.Combine(linkFixture.DirectoryPath, "libarea_matrix_core_link.so");
        File.CreateSymbolicLink(linkPath, linkFixture.LibraryPath);
        AssertThrows<LinuxRepositoryCoreException>(
            () => NativeCoreLibrary.VerifyLibrary(
                linkPath,
                linkFixture.ManifestPath,
                "linux-x64",
                "x64"),
            "linked Linux fixture library");

        string nonCanonical = Path.Combine(
            linkFixture.DirectoryPath,
            ".",
            Path.GetFileName(linkFixture.LibraryPath));
        AssertThrows<LinuxRepositoryCoreException>(
            () => NativeCoreLibrary.VerifyLibrary(
                nonCanonical,
                linkFixture.ManifestPath,
                "linux-x64",
                "x64"),
            "non-canonical Linux fixture library path");
    }

    private static void DevelopmentOverrideRequiresExplicitOptIn()
    {
        using NativeFixture fixture = NativeFixture.Create();
        string? previousLibrary = Environment.GetEnvironmentVariable(NativeCoreLibrary.LibraryOverride);
        string? previousManifest = Environment.GetEnvironmentVariable(NativeCoreLibrary.ManifestOverride);
        string? previousOptIn = Environment.GetEnvironmentVariable(NativeCoreLibrary.DevelopmentOverrideOptIn);
        try
        {
            Environment.SetEnvironmentVariable(NativeCoreLibrary.LibraryOverride, fixture.LibraryPath);
            Environment.SetEnvironmentVariable(NativeCoreLibrary.ManifestOverride, fixture.ManifestPath);
            Environment.SetEnvironmentVariable(NativeCoreLibrary.DevelopmentOverrideOptIn, null);

            AssertThrows<LinuxRepositoryCoreException>(
                () => NativeCoreLibrary.LoadDefault(),
                "Linux development override without explicit opt-in");
        }
        finally
        {
            Environment.SetEnvironmentVariable(NativeCoreLibrary.LibraryOverride, previousLibrary);
            Environment.SetEnvironmentVariable(NativeCoreLibrary.ManifestOverride, previousManifest);
            Environment.SetEnvironmentVariable(NativeCoreLibrary.DevelopmentOverrideOptIn, previousOptIn);
        }
    }

    private static void DefaultLaunchFailsClosedWithoutVerifiedPackage()
    {
        string? previousLibrary = Environment.GetEnvironmentVariable(NativeCoreLibrary.LibraryOverride);
        string? previousManifest = Environment.GetEnvironmentVariable(NativeCoreLibrary.ManifestOverride);
        string? previousOptIn = Environment.GetEnvironmentVariable(NativeCoreLibrary.DevelopmentOverrideOptIn);
        try
        {
            Environment.SetEnvironmentVariable(NativeCoreLibrary.LibraryOverride, null);
            Environment.SetEnvironmentVariable(NativeCoreLibrary.ManifestOverride, null);
            Environment.SetEnvironmentVariable(NativeCoreLibrary.DevelopmentOverrideOptIn, null);

            AssertThrows<LinuxRepositoryCoreException>(
                () => NativeCoreLibrary.LoadDefault(),
                "fixture-only Linux default launch");
        }
        finally
        {
            Environment.SetEnvironmentVariable(NativeCoreLibrary.LibraryOverride, previousLibrary);
            Environment.SetEnvironmentVariable(NativeCoreLibrary.ManifestOverride, previousManifest);
            Environment.SetEnvironmentVariable(NativeCoreLibrary.DevelopmentOverrideOptIn, previousOptIn);
        }
    }

    private static void LinuxProjectRemainsFixtureOnly()
    {
        string project = File.ReadAllText(RepositoryPath("apps/linux/AreaMatrix/AreaMatrix.Linux.csproj"));
        string manifest = File.ReadAllText(RepositoryPath(
            "apps/linux/AreaMatrix/native-core.manifest.json"));

        TestAssert.NotContains("<OutputType>Exe</OutputType>", project, "no Linux production executable");
        TestAssert.Contains("native-core.manifest.json", project, "Linux manifest copy");
        TestAssert.Contains("fixture-only", manifest, "Linux fixture-only status");
        TestAssert.Contains("\"artifacts\": []", manifest, "no placeholder Linux artifacts");
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

    private static string RepositoryPath(string relativePath)
    {
        string? current = AppContext.BaseDirectory;
        while (!string.IsNullOrWhiteSpace(current))
        {
            string candidate = Path.Combine(current, relativePath);
            if (File.Exists(candidate))
            {
                return candidate;
            }

            current = Directory.GetParent(current)?.FullName;
        }

        return Path.GetFullPath(relativePath);
    }

    private sealed class NativeFixture : IDisposable
    {
        private NativeFixture(string directoryPath, string libraryPath, string manifestPath)
        {
            DirectoryPath = directoryPath;
            LibraryPath = libraryPath;
            ManifestPath = manifestPath;
        }

        public string DirectoryPath { get; }

        public string LibraryPath { get; }

        public string ManifestPath { get; }

        public static NativeFixture Create()
        {
            string directory = Path.Combine(Path.GetTempPath(), $"areamatrix-linux-native-{Guid.NewGuid():N}");
            Directory.CreateDirectory(directory);
            string library = Path.Combine(directory, "libarea_matrix_core.so");
            File.WriteAllBytes(library, [0x41, 0x4d, 0x43, 0x4f, 0x52, 0x45]);
            string hash = Convert.ToHexString(SHA256.HashData(File.ReadAllBytes(library))).ToLowerInvariant();
            string manifest = Path.Combine(directory, NativeCoreLibrary.ManifestFileName);
            File.WriteAllText(
                manifest,
                JsonSerializer.Serialize(
                    new
                    {
                        schemaVersion = 1,
                        status = "development",
                        sourceCommit = "test-fixture",
                        buildCommand = "test-fixture",
                        license = "LICENSE",
                        sbom = "test-fixture",
                        artifacts = new[]
                        {
                            new
                            {
                                rid = "linux-x64",
                                architecture = "x64",
                                fileName = Path.GetFileName(library),
                                sha256 = hash
                            }
                        }
                    }));
            return new NativeFixture(directory, library, manifest);
        }

        public void Dispose()
        {
            Directory.Delete(DirectoryPath, recursive: true);
        }
    }
}
