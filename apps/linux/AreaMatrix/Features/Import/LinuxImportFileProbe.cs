using System.Security.Cryptography;

namespace AreaMatrix.Linux.Features.Import;

public interface ILinuxImportFileProbe
{
    LinuxImportFileProbeResult Probe(string sourcePath);

    LinuxImportFileProbeResult ResolvePreviewProbe(
        string repoPath,
        LinuxImportFileProbeResult source,
        string suggestedCategory,
        string suggestedName);

    DesktopImportMovePreflight CheckMovePreflight(
        string repoPath,
        IReadOnlyList<DesktopImportPreviewItem> previewItems);

    IReadOnlyList<DesktopImportSource> ExpandSources(IEnumerable<string> sourcePaths);
}

public sealed record LinuxImportFileProbeResult(
    string SourcePath,
    string FileName,
    string TypeText,
    string SizeText,
    bool IsReadable,
    bool CanRemove,
    DesktopImportPreviewStatus Status,
    string MountText,
    string? ReadFailure = null,
    string? RemoveFailure = null,
    string? ExistingConflictPath = null,
    string? TargetPath = null);

public sealed class LinuxImportFileProbe : ILinuxImportFileProbe
{
    private const string MountInfoPath = "/proc/self/mountinfo";

    private static readonly HashSet<string> SkippedDirectoryNames = new(StringComparer.Ordinal)
    {
        ".areamatrix",
        ".git",
        "node_modules"
    };

    public LinuxImportFileProbeResult Probe(string sourcePath)
    {
        string fullPath = Path.GetFullPath(sourcePath);
        string fileName = Path.GetFileName(fullPath);
        if (string.IsNullOrWhiteSpace(fileName))
        {
            throw new DesktopImportCoreException(
                DesktopImportErrorKind.InvalidPath,
                "Select a file before importing.",
                sourcePath);
        }

        FileInfo file = new(fullPath);
        if (!file.Exists)
        {
            return new LinuxImportFileProbeResult(
                fullPath,
                fileName,
                "Unavailable",
                "-",
                false,
                false,
                DesktopImportPreviewStatus.Unreadable,
                "unknown",
                "Source file is missing.",
                "Source file is missing.");
        }

        bool readable = CanRead(file, out string? readFailure);
        bool canRemove = CanRemoveSource(file, out string? removeFailure);
        DesktopImportPreviewStatus status = readable
            ? DesktopImportPreviewStatus.Ready
            : DesktopImportPreviewStatus.PermissionDenied;
        return new LinuxImportFileProbeResult(
            file.FullName,
            fileName,
            FileTypeText(file.Extension),
            FormatBytes(file.Length),
            readable,
            canRemove,
            status,
            "unknown",
            readFailure,
            removeFailure);
    }

    public LinuxImportFileProbeResult ResolvePreviewProbe(
        string repoPath,
        LinuxImportFileProbeResult source,
        string suggestedCategory,
        string suggestedName)
    {
        if (!source.IsReadable)
        {
            return source;
        }

        try
        {
            string sourceHash = HashFile(source.SourcePath);
            string targetPath = TargetPath(repoPath, suggestedCategory, suggestedName, source.FileName);
            if (File.Exists(targetPath))
            {
                return source with
                {
                    Status = FilesHaveSameHash(source.SourcePath, targetPath, sourceHash)
                        ? DesktopImportPreviewStatus.Duplicate
                        : DesktopImportPreviewStatus.NameConflict,
                    ExistingConflictPath = targetPath,
                    TargetPath = targetPath
                };
            }

            DesktopImportPreviewStatus status = RepositoryContainsHash(repoPath, source.SourcePath, sourceHash)
                ? DesktopImportPreviewStatus.Duplicate
                : DesktopImportPreviewStatus.Ready;
            return source with
            {
                Status = status,
                TargetPath = targetPath
            };
        }
        catch (Exception exception) when (exception is IOException or UnauthorizedAccessException)
        {
            return source with
            {
                Status = DesktopImportPreviewStatus.PermissionDenied,
                ReadFailure = exception.Message
            };
        }
    }

    public DesktopImportMovePreflight CheckMovePreflight(
        string repoPath,
        IReadOnlyList<DesktopImportPreviewItem> previewItems)
    {
        List<string> reasons = [];
        if (!DirectoryAllowsWrite(repoPath))
        {
            reasons.Add("target repository is not writable");
        }

        string stagingPath = Path.Combine(repoPath, ".areamatrix", "staging");
        if (!DirectoryAllowsWrite(stagingPath))
        {
            reasons.Add("staging directory is not available");
        }

        foreach (DesktopImportPreviewItem item in previewItems)
        {
            LinuxImportFileProbeResult source = Probe(item.SourcePath);
            if (!source.IsReadable)
            {
                reasons.Add($"{item.FileName}: {source.ReadFailure ?? "source file is not readable"}");
                continue;
            }

            if (!source.CanRemove)
            {
                reasons.Add($"{item.FileName}: {source.RemoveFailure ?? "source folder does not allow removal"}");
            }
        }

        return new DesktopImportMovePreflight(
            reasons.Count == 0,
            reasons.Distinct(StringComparer.Ordinal).ToArray(),
            MountText(repoPath, previewItems));
    }

    public IReadOnlyList<DesktopImportSource> ExpandSources(IEnumerable<string> sourcePaths)
    {
        List<DesktopImportSource> sources = [];
        foreach (string sourcePath in sourcePaths)
        {
            string trimmed = sourcePath.Trim();
            if (File.Exists(trimmed))
            {
                sources.Add(new DesktopImportSource(Path.GetFullPath(trimmed)));
                continue;
            }

            if (Directory.Exists(trimmed))
            {
                sources.AddRange(EnumerateFolderSources(trimmed));
                continue;
            }

            sources.Add(new DesktopImportSource(trimmed));
        }

        return sources
            .DistinctBy(source => source.SourcePath, StringComparer.Ordinal)
            .ToArray();
    }

    private static string FileTypeText(string extension)
    {
        return string.IsNullOrWhiteSpace(extension)
            ? "File"
            : extension.TrimStart('.').ToUpperInvariant();
    }

    private static string FormatBytes(long bytes)
    {
        if (bytes < 1024)
        {
            return $"{bytes} B";
        }

        if (bytes < 1024 * 1024)
        {
            return $"{bytes / 1024.0:0.#} KB";
        }

        if (bytes < 1024L * 1024 * 1024)
        {
            return $"{bytes / (1024.0 * 1024):0.#} MB";
        }

        return $"{bytes / (1024.0 * 1024 * 1024):0.#} GB";
    }

    private static bool CanRead(FileInfo file, out string? failure)
    {
        try
        {
            using FileStream stream = file.Open(FileMode.Open, FileAccess.Read, FileShare.Read);
            failure = null;
            return true;
        }
        catch (Exception exception) when (exception is IOException or UnauthorizedAccessException)
        {
            failure = exception.Message;
            return false;
        }
    }

    private static bool CanRemoveSource(FileInfo file, out string? failure)
    {
        DirectoryInfo? directory = file.Directory;
        if (directory is null || !directory.Exists)
        {
            failure = "source folder is unavailable";
            return false;
        }

        if (!DirectoryAllowsWrite(directory.FullName))
        {
            failure = "source folder is not writable";
            return false;
        }

        failure = null;
        return true;
    }

    private static bool DirectoryAllowsWrite(string directoryPath)
    {
        if (string.IsNullOrWhiteSpace(directoryPath) || !Directory.Exists(directoryPath))
        {
            return false;
        }

        if (OperatingSystem.IsWindows())
        {
            return false;
        }

        try
        {
            UnixFileMode mode = File.GetUnixFileMode(directoryPath);
            return (mode & (UnixFileMode.UserWrite | UnixFileMode.GroupWrite | UnixFileMode.OtherWrite)) != 0;
        }
        catch (Exception exception) when (exception is IOException or UnauthorizedAccessException or PlatformNotSupportedException)
        {
            return false;
        }
    }

    private static string TargetPath(
        string repoPath,
        string suggestedCategory,
        string suggestedName,
        string fallbackName)
    {
        string category = string.IsNullOrWhiteSpace(suggestedCategory)
            ? "inbox"
            : suggestedCategory.Trim();
        string name = string.IsNullOrWhiteSpace(suggestedName)
            ? fallbackName
            : suggestedName.Trim();
        return Path.Combine(Path.GetFullPath(repoPath), category, name);
    }

    private static bool RepositoryContainsHash(string repoPath, string sourcePath, string sourceHash)
    {
        if (!Directory.Exists(repoPath))
        {
            return false;
        }

        string sourceFullPath = Path.GetFullPath(sourcePath);
        foreach (string filePath in Directory.EnumerateFiles(repoPath, "*", SearchOption.AllDirectories))
        {
            if (ShouldSkipRepositoryFile(repoPath, sourceFullPath, filePath))
            {
                continue;
            }

            if (FilesHaveSameHash(sourceFullPath, filePath, sourceHash))
            {
                return true;
            }
        }

        return false;
    }

    private static bool ShouldSkipRepositoryFile(string repoPath, string sourcePath, string filePath)
    {
        string fullPath = Path.GetFullPath(filePath);
        if (string.Equals(fullPath, sourcePath, StringComparison.Ordinal))
        {
            return true;
        }

        string metadataRoot = Path.Combine(Path.GetFullPath(repoPath), ".areamatrix");
        return fullPath.StartsWith(metadataRoot + Path.DirectorySeparatorChar, StringComparison.Ordinal);
    }

    private static bool FilesHaveSameHash(string sourcePath, string targetPath, string sourceHash)
    {
        FileInfo source = new(sourcePath);
        FileInfo target = new(targetPath);
        return target.Exists && source.Length == target.Length && HashFile(target.FullName) == sourceHash;
    }

    private static string HashFile(string path)
    {
        using FileStream stream = File.OpenRead(path);
        byte[] hash = SHA256.HashData(stream);
        return Convert.ToHexString(hash);
    }

    private static IEnumerable<DesktopImportSource> EnumerateFolderSources(string rootPath)
    {
        string fullRoot = Path.GetFullPath(rootPath);
        foreach (string filePath in Directory.EnumerateFiles(fullRoot, "*", SearchOption.AllDirectories))
        {
            if (ShouldSkipFolderFile(fullRoot, filePath))
            {
                continue;
            }

            string relative = Path.GetRelativePath(fullRoot, Path.GetDirectoryName(filePath) ?? fullRoot);
            yield return new DesktopImportSource(
                Path.GetFullPath(filePath),
                fullRoot,
                relative == "." ? null : relative);
        }
    }

    private static bool ShouldSkipFolderFile(string rootPath, string filePath)
    {
        string relative = Path.GetRelativePath(rootPath, filePath);
        return relative
            .Split(Path.DirectorySeparatorChar, Path.AltDirectorySeparatorChar)
            .Any(part => SkippedDirectoryNames.Contains(part));
    }

    private static string MountText(string repoPath, IReadOnlyList<DesktopImportPreviewItem> previewItems)
    {
        if (previewItems.Count == 0)
        {
            return "unknown";
        }

        IReadOnlyList<LinuxMountInfoEntry> mounts = LinuxMountInfoEntry.ReadAll(MountInfoPath);
        if (mounts.Count == 0)
        {
            return "unknown";
        }

        LinuxMountInfoEntry? repoMount = LinuxMountInfoEntry.FindForPath(mounts, repoPath);
        if (repoMount is null)
        {
            return "unknown";
        }

        bool hasUnknown = false;
        foreach (DesktopImportPreviewItem item in previewItems)
        {
            LinuxMountInfoEntry? sourceMount = LinuxMountInfoEntry.FindForPath(mounts, item.SourcePath);
            if (sourceMount is null)
            {
                hasUnknown = true;
                continue;
            }

            if (!repoMount.HasSameDevice(sourceMount))
            {
                return "different mount";
            }
        }

        return hasUnknown ? "unknown" : "same mount";
    }
}
