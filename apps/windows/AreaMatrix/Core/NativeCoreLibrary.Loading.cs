using System;
using System.Collections.Generic;
using System.IO;
using System.Runtime.InteropServices;
using System.Security.Cryptography;
using System.Text.Json;
using System.Text.Json.Serialization;
using AreaMatrix.Features.Onboarding;

namespace AreaMatrix.Core;

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

        (string rid, string architecture) = CurrentRuntimeIdentity();
        string nativeDirectory = Path.Combine(AppContext.BaseDirectory, "runtimes", rid, "native");
        return LoadVerified(
            Path.Combine(nativeDirectory, "area_matrix_core.dll"),
            Path.Combine(AppContext.BaseDirectory, "native-core.manifest.json"),
            rid,
            architecture,
            AppContext.BaseDirectory);
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
        string? allowedRoot = null,
        string expectedStatus = "development")
    {
        using FileStream library = OpenVerifiedLibrary(
            libraryPath,
            manifestPath,
            expectedRid,
            expectedArchitecture,
            allowedRoot,
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
        return LoadVerified(libraryPath, resolvedManifest, rid, architecture, allowedRoot: null);
    }

    private static NativeCoreLibrary LoadVerified(
        string libraryPath,
        string manifestPath,
        string expectedRid,
        string expectedArchitecture,
        string? allowedRoot)
    {
        using FileStream library = OpenVerifiedLibrary(
            libraryPath,
            manifestPath,
            expectedRid,
            expectedArchitecture,
            allowedRoot,
            allowedRoot is null ? "development" : "approved");

        // Keep a non-delete-sharing handle open until the Windows loader maps the verified bytes.
        return new NativeCoreLibrary(NativeLibrary.Load(library.Name));
    }

    private static FileStream OpenVerifiedLibrary(
        string libraryPath,
        string manifestPath,
        string expectedRid,
        string expectedArchitecture,
        string? allowedRoot,
        string expectedStatus)
    {
        string canonicalLibrary = CanonicalRegularFile(libraryPath, allowedRoot, "library");
        string canonicalManifest = CanonicalRegularFile(manifestPath, allowedRoot, "manifest");
        if (allowedRoot is null && !string.Equals(
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
        if (!HasApprovedProvenance(manifest, expectedStatus) || manifest.Artifacts is null)
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

    private static bool HasApprovedProvenance(NativeCoreManifest manifest, string expectedStatus)
    {
        if (manifest.SchemaVersion != ManifestSchemaVersion
            || !string.Equals(manifest.Status, expectedStatus, StringComparison.Ordinal)
            || !IsUsableProvenanceValue(manifest.SourceCommit)
            || !IsUsableProvenanceValue(manifest.BuildCommand)
            || !IsUsableProvenanceValue(manifest.License)
            || !IsUsableProvenanceValue(manifest.Sbom))
        {
            return false;
        }

        return !string.Equals(expectedStatus, "approved", StringComparison.Ordinal)
            || IsGitCommit(manifest.SourceCommit);
    }

    private static bool IsUsableProvenanceValue(string? value)
    {
        return !string.IsNullOrWhiteSpace(value)
            && !string.Equals(value, "unavailable", StringComparison.OrdinalIgnoreCase)
            && !string.Equals(value, "unknown", StringComparison.OrdinalIgnoreCase)
            && !string.Equals(value, "none", StringComparison.OrdinalIgnoreCase)
            && !string.Equals(value, "null", StringComparison.OrdinalIgnoreCase);
    }

    private static bool IsGitCommit(string value)
    {
        return (value.Length == 40 || value.Length == 64) && IsHex(value);
    }

    private static string CanonicalRegularFile(
        string path,
        string? allowedRoot,
        string label)
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

            RejectNonRegularPath(canonical, label);
            if (allowedRoot is not null)
            {
                EnsureAppLocal(canonical, allowedRoot);
            }

            return canonical;
        }
        catch (Exception error) when (IsFileAccessError(error))
        {
            throw Unavailable($"AreaMatrix Core {label} path could not be verified safely.");
        }
    }

    private static void RejectNonRegularPath(string path, string label)
    {
        FileAttributes attributes = File.GetAttributes(path);
        if ((attributes & (FileAttributes.Directory | FileAttributes.ReparsePoint | FileAttributes.Device)) != 0)
        {
            throw Unavailable($"AreaMatrix Core {label} must be a regular file, not a link or device.");
        }
    }

    private static void EnsureAppLocal(string path, string allowedRoot)
    {
        string root = Path.GetFullPath(allowedRoot);
        if (!Directory.Exists(root)
            || (File.GetAttributes(root) & FileAttributes.ReparsePoint) != 0)
        {
            throw Unavailable("AreaMatrix Core application root must be a regular local directory.");
        }

        string rootPrefix = Path.EndsInDirectorySeparator(root)
            ? root
            : root + Path.DirectorySeparatorChar;
        if (!path.StartsWith(rootPrefix, PathComparison))
        {
            throw Unavailable("AreaMatrix Core default asset must be app-local.");
        }

        string relative = Path.GetRelativePath(root, Path.GetDirectoryName(path)!);
        string current = root;
        foreach (string segment in relative.Split(
                     Path.DirectorySeparatorChar,
                     StringSplitOptions.RemoveEmptyEntries))
        {
            current = Path.Combine(current, segment);
            if ((File.GetAttributes(current) & FileAttributes.ReparsePoint) != 0)
            {
                throw Unavailable("AreaMatrix Core app-local asset path must not traverse links.");
            }
        }
    }

    private static (string Rid, string Architecture) CurrentRuntimeIdentity()
    {
        if (!RuntimeInformation.IsOSPlatform(OSPlatform.Windows))
        {
            throw Unavailable("AreaMatrix Windows Core can only load on Windows.");
        }

        return RuntimeInformation.ProcessArchitecture switch
        {
            Architecture.X64 => ("win-x64", "x64"),
            Architecture.Arm64 => ("win-arm64", "arm64"),
            _ => throw Unavailable("AreaMatrix Windows Core does not support this process architecture.")
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

    private static StringComparison PathComparison => StringComparison.OrdinalIgnoreCase;

    private static WindowsRepositoryCoreException Unavailable(string message)
    {
        return new WindowsRepositoryCoreException(WindowsRepositoryErrorKind.Unavailable, message);
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
