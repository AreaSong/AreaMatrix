using System;
using System.Collections.Generic;
using System.Globalization;
using System.IO;
using System.Runtime.InteropServices;
using System.Security.Cryptography;
using System.Text.Json;
using System.Text.Json.Serialization;
using AreaMatrix.Linux.Features.Onboarding;

namespace AreaMatrix.Linux.Core;

internal sealed partial class NativeCoreLibrary
{
    internal const string DevelopmentOverrideOptIn =
        "AREAMATRIX_CORE_LIBRARY_ALLOW_DEVELOPMENT_OVERRIDE";
    internal const string LibraryOverride = "AREAMATRIX_CORE_LIBRARY";
    internal const string ManifestOverride = "AREAMATRIX_CORE_LIBRARY_MANIFEST";
    internal const string ManifestFileName = "area_matrix_core.manifest.json";

    private const int ManifestSchemaVersion = 1;
    private const int MaximumManifestBytes = 16 * 1024;

    public static NativeCoreLibrary LoadDefault()
    {
        string? configuredPath = Environment.GetEnvironmentVariable(LibraryOverride);
        string? configuredManifest = Environment.GetEnvironmentVariable(ManifestOverride);
        if (!string.IsNullOrWhiteSpace(configuredPath) || !string.IsNullOrWhiteSpace(configuredManifest))
        {
            return LoadDevelopmentOverride(configuredPath, configuredManifest);
        }

        throw Unavailable(
            "AreaMatrix Linux is a fixture-only client until a verified Linux native package is published.");
    }

    public static NativeCoreLibrary Load(string libraryPath)
    {
        return LoadDevelopmentOverride(
            libraryPath,
            Environment.GetEnvironmentVariable(ManifestOverride));
    }

    internal static string VerifyLibrary(
        string libraryPath,
        string manifestPath,
        string expectedRid,
        string expectedArchitecture,
        string expectedStatus = "development")
    {
        using FileStream library = OpenVerifiedLibrary(
            libraryPath,
            manifestPath,
            expectedRid,
            expectedArchitecture,
            expectedStatus);
        return library.Name;
    }

    private static NativeCoreLibrary LoadDevelopmentOverride(
        string? libraryPath,
        string? manifestPath)
    {
        if (!string.Equals(
                Environment.GetEnvironmentVariable(DevelopmentOverrideOptIn),
                "1",
                StringComparison.Ordinal))
        {
            throw Unavailable(
                $"AreaMatrix Core development override requires {DevelopmentOverrideOptIn}=1.");
        }

        if (string.IsNullOrWhiteSpace(libraryPath))
        {
            throw Unavailable($"AreaMatrix Core development override requires {LibraryOverride}.");
        }

        string resolvedManifest = string.IsNullOrWhiteSpace(manifestPath)
            ? Path.Combine(Path.GetDirectoryName(libraryPath) ?? string.Empty, ManifestFileName)
            : manifestPath;
        (string rid, string architecture) = CurrentRuntimeIdentity();
        using FileStream library = OpenVerifiedLibrary(
            libraryPath,
            resolvedManifest,
            rid,
            architecture,
            "development");
        return new NativeCoreLibrary(NativeLibrary.Load(VerifiedDescriptorPath(library)));
    }

    private static FileStream OpenVerifiedLibrary(
        string libraryPath,
        string manifestPath,
        string expectedRid,
        string expectedArchitecture,
        string expectedStatus)
    {
        string canonicalLibrary = CanonicalRegularFile(libraryPath, "library");
        string canonicalManifest = CanonicalRegularFile(manifestPath, "manifest");
        if (!string.Equals(
                Path.GetDirectoryName(canonicalLibrary),
                Path.GetDirectoryName(canonicalManifest),
                PathComparison))
        {
            throw Unavailable("AreaMatrix Core library and manifest must be adjacent.");
        }

        NativeCoreManifest manifest = ReadManifest(canonicalManifest);
        NativeCoreArtifact artifact = SelectArtifact(
            manifest,
            canonicalLibrary,
            expectedRid,
            expectedArchitecture,
            expectedStatus);
        FileStream library = OpenReadOnly(canonicalLibrary, "library");
        try
        {
            VerifyHash(library, artifact.Sha256);
            return library;
        }
        catch
        {
            library.Dispose();
            throw;
        }
    }

    private static FileStream OpenReadOnly(string path, string label)
    {
        try
        {
            return new FileStream(
                path,
                FileMode.Open,
                FileAccess.Read,
                FileShare.Read,
                bufferSize: 128 * 1024,
                FileOptions.SequentialScan);
        }
        catch (Exception error) when (IsFileAccessError(error))
        {
            throw Unavailable($"AreaMatrix Core {label} could not be opened safely.");
        }
    }

    private static void VerifyHash(FileStream library, string expectedSha256)
    {
        byte[] actualHash = SHA256.HashData(library);
        byte[] expectedHash = Convert.FromHexString(expectedSha256);
        if (!CryptographicOperations.FixedTimeEquals(actualHash, expectedHash))
        {
            throw Unavailable("AreaMatrix Core library SHA-256 does not match its manifest.");
        }

        library.Position = 0;
    }

    private static string VerifiedDescriptorPath(FileStream library)
    {
        // Load through the still-open descriptor so a path rename cannot swap bytes after hashing.
        long descriptor = library.SafeFileHandle.DangerousGetHandle().ToInt64();
        string descriptorText = descriptor.ToString(CultureInfo.InvariantCulture);
        if (RuntimeInformation.IsOSPlatform(OSPlatform.Linux))
        {
            return $"/proc/self/fd/{descriptorText}";
        }

        if (RuntimeInformation.IsOSPlatform(OSPlatform.OSX))
        {
            return $"/dev/fd/{descriptorText}";
        }

        throw Unavailable("AreaMatrix Linux fixture host does not expose a verified descriptor path.");
    }

    private static NativeCoreManifest ReadManifest(string manifestPath)
    {
        try
        {
            FileInfo info = new(manifestPath);
            if (info.Length is <= 0 or > MaximumManifestBytes)
            {
                throw Unavailable("AreaMatrix Core manifest size is invalid.");
            }

            JsonSerializerOptions options = new()
            {
                PropertyNameCaseInsensitive = true,
                UnmappedMemberHandling = JsonUnmappedMemberHandling.Disallow
            };
            using FileStream stream = new(
                manifestPath,
                FileMode.Open,
                FileAccess.Read,
                FileShare.Read,
                bufferSize: 4096,
                FileOptions.SequentialScan);
            return JsonSerializer.Deserialize<NativeCoreManifest>(stream, options)
                ?? throw Unavailable("AreaMatrix Core manifest is empty.");
        }
        catch (JsonException error)
        {
            throw Unavailable($"AreaMatrix Core manifest is invalid: {error.Message}");
        }
        catch (Exception error) when (IsFileAccessError(error))
        {
            throw Unavailable("AreaMatrix Core manifest could not be read safely.");
        }
    }

    private static NativeCoreArtifact SelectArtifact(
        NativeCoreManifest manifest,
        string libraryPath,
        string expectedRid,
        string expectedArchitecture,
        string expectedStatus)
    {
        if (!HasUsableProvenance(manifest, expectedStatus) || manifest.Artifacts is null)
        {
            throw Unavailable("AreaMatrix Core manifest provenance is incomplete or unapproved.");
        }

        NativeCoreArtifact? selected = null;
        foreach (NativeCoreArtifact artifact in manifest.Artifacts)
        {
            if (!string.Equals(artifact.Rid, expectedRid, StringComparison.Ordinal)
                || !string.Equals(artifact.Architecture, expectedArchitecture, StringComparison.Ordinal)
                || !string.Equals(artifact.FileName, Path.GetFileName(libraryPath), PathComparison))
            {
                continue;
            }

            if (selected is not null || !IsSha256(artifact.Sha256))
            {
                throw Unavailable("AreaMatrix Core manifest has an invalid or duplicate runtime asset.");
            }

            selected = artifact;
        }

        return selected
            ?? throw Unavailable("AreaMatrix Core manifest has no asset for this RID and architecture.");
    }

    private static bool HasUsableProvenance(NativeCoreManifest manifest, string expectedStatus)
    {
        return manifest.SchemaVersion == ManifestSchemaVersion
            && string.Equals(manifest.Status, expectedStatus, StringComparison.Ordinal)
            && IsUsableValue(manifest.SourceCommit)
            && IsUsableValue(manifest.BuildCommand)
            && IsUsableValue(manifest.License)
            && IsUsableValue(manifest.Sbom);
    }

    private static bool IsUsableValue(string? value)
    {
        return !string.IsNullOrWhiteSpace(value)
            && !string.Equals(value, "unavailable", StringComparison.OrdinalIgnoreCase)
            && !string.Equals(value, "unknown", StringComparison.OrdinalIgnoreCase)
            && !string.Equals(value, "none", StringComparison.OrdinalIgnoreCase)
            && !string.Equals(value, "null", StringComparison.OrdinalIgnoreCase);
    }

    private static string CanonicalRegularFile(string path, string label)
    {
        try
        {
            if (string.IsNullOrWhiteSpace(path) || !Path.IsPathFullyQualified(path))
            {
                throw Unavailable($"AreaMatrix Core {label} path must be canonical and absolute.");
            }

            string canonical = Path.GetFullPath(path);
            if (!string.Equals(path, canonical, PathComparison) || !File.Exists(canonical))
            {
                throw Unavailable($"AreaMatrix Core {label} was not found at its canonical path.");
            }

            FileAttributes attributes = File.GetAttributes(canonical);
            if ((attributes & (FileAttributes.Directory | FileAttributes.ReparsePoint | FileAttributes.Device)) != 0)
            {
                throw Unavailable($"AreaMatrix Core {label} must be a regular file, not a link or device.");
            }

            return canonical;
        }
        catch (Exception error) when (IsFileAccessError(error))
        {
            throw Unavailable($"AreaMatrix Core {label} path could not be verified safely.");
        }
    }

    private static (string Rid, string Architecture) CurrentRuntimeIdentity()
    {
        string ridPrefix = RuntimeInformation.IsOSPlatform(OSPlatform.Linux)
            ? "linux"
            : RuntimeInformation.IsOSPlatform(OSPlatform.OSX)
                ? "osx"
                : throw Unavailable("AreaMatrix Linux fixtures require a Linux or macOS test host.");
        return RuntimeInformation.ProcessArchitecture switch
        {
            Architecture.X64 => ($"{ridPrefix}-x64", "x64"),
            Architecture.Arm64 => ($"{ridPrefix}-arm64", "arm64"),
            _ => throw Unavailable("AreaMatrix Linux fixtures do not support this process architecture.")
        };
    }

    private static bool IsSha256(string? value)
    {
        return value?.Length == 64 && IsHex(value);
    }

    private static bool IsHex(string value)
    {
        foreach (char character in value)
        {
            if (!Uri.IsHexDigit(character))
            {
                return false;
            }
        }

        return true;
    }

    private static bool IsFileAccessError(Exception error)
    {
        return error is IOException
            or UnauthorizedAccessException
            or ArgumentException
            or NotSupportedException;
    }

    private static StringComparison PathComparison =>
        OperatingSystem.IsWindows() ? StringComparison.OrdinalIgnoreCase : StringComparison.Ordinal;

    private static LinuxRepositoryCoreException Unavailable(string message)
    {
        return new LinuxRepositoryCoreException(LinuxRepositoryErrorKind.Unavailable, message);
    }

    private sealed class NativeCoreManifest
    {
        public int SchemaVersion { get; init; }

        public string Status { get; init; } = string.Empty;

        public string SourceCommit { get; init; } = string.Empty;

        public string BuildCommand { get; init; } = string.Empty;

        public string License { get; init; } = string.Empty;

        public string Sbom { get; init; } = string.Empty;

        public List<NativeCoreArtifact>? Artifacts { get; init; }
    }

    private sealed class NativeCoreArtifact
    {
        public string Rid { get; init; } = string.Empty;

        public string Architecture { get; init; } = string.Empty;

        public string FileName { get; init; } = string.Empty;

        public string Sha256 { get; init; } = string.Empty;
    }
}
