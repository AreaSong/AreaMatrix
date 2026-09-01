using System.Security.Cryptography;
using System.Text.Json;
using AreaMatrix.Core;
using AreaMatrix.Features.Onboarding;
using AreaMatrixTests.ChooseRepository;

namespace AreaMatrixTests.Architecture;

public static class NativeCoreLibrarySecurityTests
{
    public static void RunAll()
    {
        VerifiedManifestAcceptsMatchingRegularFile();
        VerificationRejectsHashAndRuntimeMismatch();
        VerificationRejectsLinksAndNonCanonicalPaths();
        ApprovedAssetsRequireCommitProvenanceAndAppLocalPaths();
        DevelopmentOverrideRequiresExplicitOptIn();
        WindowsProjectLocksNuGetAndShipsFailClosedManifest();
    }

    private static void VerifiedManifestAcceptsMatchingRegularFile()
    {
        using NativeFixture fixture = NativeFixture.Create();
        string resolved = NativeCoreLibrary.VerifyLibrary(
            fixture.LibraryPath,
            fixture.ManifestPath,
            "win-x64",
            "x64");

        TestAssert.Equal(fixture.LibraryPath, resolved, "verified native library path");
    }

    private static void VerificationRejectsHashAndRuntimeMismatch()
    {
        using NativeFixture fixture = NativeFixture.Create();
        File.AppendAllText(fixture.LibraryPath, "tampered");
        AssertThrows<WindowsRepositoryCoreException>(
            () => NativeCoreLibrary.VerifyLibrary(
                fixture.LibraryPath,
                fixture.ManifestPath,
                "win-x64",
                "x64"),
            "tampered native library hash");

        using NativeFixture runtimeFixture = NativeFixture.Create();
        AssertThrows<WindowsRepositoryCoreException>(
            () => NativeCoreLibrary.VerifyLibrary(
                runtimeFixture.LibraryPath,
                runtimeFixture.ManifestPath,
                "win-arm64",
                "arm64"),
            "RID and architecture mismatch");
    }

    private static void VerificationRejectsLinksAndNonCanonicalPaths()
    {
        using NativeFixture fixture = NativeFixture.Create();
        string linkPath = Path.Combine(fixture.DirectoryPath, "area_matrix_core_link.dll");
        File.CreateSymbolicLink(linkPath, fixture.LibraryPath);
        AssertThrows<WindowsRepositoryCoreException>(
            () => NativeCoreLibrary.VerifyLibrary(
                linkPath,
                fixture.ManifestPath,
                "win-x64",
                "x64"),
            "linked native library");

        string nonCanonical = Path.Combine(fixture.DirectoryPath, ".", Path.GetFileName(fixture.LibraryPath));
        AssertThrows<WindowsRepositoryCoreException>(
            () => NativeCoreLibrary.VerifyLibrary(
                nonCanonical,
                fixture.ManifestPath,
                "win-x64",
                "x64"),
            "non-canonical native library path");
    }

    private static void DevelopmentOverrideRequiresExplicitOptIn()
    {
        string? previousLibrary = Environment.GetEnvironmentVariable(NativeCoreLibrary.LibraryOverride);
        string? previousManifest = Environment.GetEnvironmentVariable(NativeCoreLibrary.ManifestOverride);
        string? previousOptIn = Environment.GetEnvironmentVariable(NativeCoreLibrary.DevelopmentOverrideOptIn);
        try
        {
            Environment.SetEnvironmentVariable(NativeCoreLibrary.LibraryOverride, "/tmp/untrusted.dll");
            Environment.SetEnvironmentVariable(NativeCoreLibrary.ManifestOverride, null);
            Environment.SetEnvironmentVariable(NativeCoreLibrary.DevelopmentOverrideOptIn, null);

            AssertThrows<WindowsRepositoryCoreException>(
                () => NativeCoreLibrary.LoadDefault(),
                "development override without explicit opt-in");
        }
        finally
        {
            Environment.SetEnvironmentVariable(NativeCoreLibrary.LibraryOverride, previousLibrary);
            Environment.SetEnvironmentVariable(NativeCoreLibrary.ManifestOverride, previousManifest);
            Environment.SetEnvironmentVariable(NativeCoreLibrary.DevelopmentOverrideOptIn, previousOptIn);
        }
    }

    private static void ApprovedAssetsRequireCommitProvenanceAndAppLocalPaths()
    {
        using NativeFixture approved = NativeFixture.Create(
            status: "approved",
            sourceCommit: new string('a', 40));
        string resolved = NativeCoreLibrary.VerifyLibrary(
            approved.LibraryPath,
            approved.ManifestPath,
            "win-x64",
            "x64",
            approved.DirectoryPath,
            "approved");
        TestAssert.Equal(approved.LibraryPath, resolved, "approved app-local native library");

        using NativeFixture placeholder = NativeFixture.Create(
            status: "approved",
            sourceCommit: "unavailable");
        AssertThrows<WindowsRepositoryCoreException>(
            () => NativeCoreLibrary.VerifyLibrary(
                placeholder.LibraryPath,
                placeholder.ManifestPath,
                "win-x64",
                "x64",
                placeholder.DirectoryPath,
                "approved"),
            "approved native library with placeholder source commit");

        string unrelatedRoot = Path.Combine(approved.DirectoryPath, "unrelated-root");
        Directory.CreateDirectory(unrelatedRoot);
        AssertThrows<WindowsRepositoryCoreException>(
            () => NativeCoreLibrary.VerifyLibrary(
                approved.LibraryPath,
                approved.ManifestPath,
                "win-x64",
                "x64",
                unrelatedRoot,
                "approved"),
            "approved native library outside application root");
    }

    private static void WindowsProjectLocksNuGetAndShipsFailClosedManifest()
    {
        string project = File.ReadAllText(RepositoryPath("apps/windows/AreaMatrix/AreaMatrix.Windows.csproj"));
        string config = File.ReadAllText(RepositoryPath("apps/windows/NuGet.config"));
        string lockFile = File.ReadAllText(RepositoryPath(
            "apps/windows/AreaMatrix/packages.lock.json"));
        string manifest = File.ReadAllText(RepositoryPath(
            "apps/windows/AreaMatrix/native-core.manifest.json"));

        TestAssert.Contains("<RestoreLockedMode>true</RestoreLockedMode>", project, "locked restore");
        TestAssert.Contains("native-core.manifest.json", project, "native manifest copy");
        TestAssert.Contains("<clear />", config, "cleared package sources");
        TestAssert.Contains("https://api.nuget.org/v3/index.json", config, "approved NuGet source");
        TestAssert.Contains("<packageSourceMapping>", config, "NuGet source mapping");
        TestAssert.Contains("\"Microsoft.WindowsAppSDK\"", lockFile, "Windows App SDK lock entry");
        TestAssert.Contains("\"contentHash\"", lockFile, "NuGet package content hashes");
        TestAssert.Contains("blocked-external-artifact", manifest, "fail-closed Windows manifest");
        TestAssert.Contains("\"artifacts\": []", manifest, "no placeholder Windows artifacts");
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

        public static NativeFixture Create(
            string status = "development",
            string sourceCommit = "test-fixture")
        {
            string directory = Path.Combine(Path.GetTempPath(), $"areamatrix-win-native-{Guid.NewGuid():N}");
            Directory.CreateDirectory(directory);
            string library = Path.Combine(directory, "area_matrix_core.dll");
            File.WriteAllBytes(library, [0x41, 0x4d, 0x43, 0x4f, 0x52, 0x45]);
            string hash = Convert.ToHexString(SHA256.HashData(File.ReadAllBytes(library))).ToLowerInvariant();
            string manifest = Path.Combine(directory, NativeCoreLibrary.ManifestFileName);
            File.WriteAllText(
                manifest,
                JsonSerializer.Serialize(
                    new
                    {
                        schemaVersion = 1,
                        status,
                        sourceCommit,
                        buildCommand = "test-fixture",
                        license = "LICENSE",
                        sbom = "test-fixture",
                        artifacts = new[]
                        {
                            new
                            {
                                rid = "win-x64",
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
