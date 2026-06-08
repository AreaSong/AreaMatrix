using System;
using System.Collections.Generic;
using System.IO;
using System.Linq;
using System.Security.Cryptography;

namespace AreaMatrix.Features.Import;

public interface IWindowsImportFileProbe
{
    WindowsImportFileProbeResult Probe(string sourcePath);

    DesktopImportPreviewStatus ResolvePreviewStatus(
        string repoPath,
        WindowsImportFileProbeResult source,
        string suggestedCategory,
        string suggestedName);

    DesktopImportMovePreflight CheckMovePreflight(
        string repoPath,
        IReadOnlyList<DesktopImportPreviewItem> previewItems);

    WindowsImportFileProbeResult ResolveReplacePreflight(
        string repoPath,
        WindowsImportFileProbeResult source,
        string suggestedCategory,
        string suggestedName);

    IReadOnlyList<DesktopImportSource> ExpandSources(IEnumerable<string> sourcePaths);
}

public sealed record WindowsImportFileProbeResult(
    string SourcePath,
    string FileName,
    string TypeText,
    string SizeText,
    bool IsReadable,
    bool CanRemove,
    string? ReadFailure = null,
    string? RemoveFailure = null,
    string? ExistingConflictPath = null,
    string? TargetPath = null,
    bool ReplacePreflightAvailable = false,
    string? ReplaceBlockedReason = null);

public sealed class WindowsImportFileProbe : IWindowsImportFileProbe
{
    private static readonly HashSet<string> SkippedDirectoryNames = new(StringComparer.OrdinalIgnoreCase)
    {
        ".areamatrix",
        ".git",
        "node_modules"
    };

    public WindowsImportFileProbeResult Probe(string sourcePath)
    {
        string fileName = Path.GetFileName(sourcePath);
        if (string.IsNullOrWhiteSpace(fileName))
        {
            throw new DesktopImportCoreException(
                DesktopImportErrorKind.InvalidPath,
                "Select a file before importing.",
                sourcePath);
        }

        FileInfo file = new(Path.GetFullPath(sourcePath));
        if (!file.Exists)
        {
            return new WindowsImportFileProbeResult(
                sourcePath,
                fileName,
                "Unavailable",
                "-",
                false,
                false,
                "Source file is missing.",
                "Source file is missing.");
        }

        bool readable = CanRead(file, out string? readFailure);
        bool canRemove = CanRemoveSource(file, out string? removeFailure);
        return new WindowsImportFileProbeResult(
            file.FullName,
            fileName,
            FileTypeText(file.Extension),
            FormatBytes(file.Length),
            readable,
            canRemove,
            readFailure,
            removeFailure);
    }

    public DesktopImportPreviewStatus ResolvePreviewStatus(
        string repoPath,
        WindowsImportFileProbeResult source,
        string suggestedCategory,
        string suggestedName)
    {
        if (!source.IsReadable)
        {
            return DesktopImportPreviewStatus.Unreadable;
        }

        try
        {
            string sourceHash = HashFile(source.SourcePath);
            string targetPath = TargetPath(repoPath, suggestedCategory, suggestedName, source.FileName);
            if (File.Exists(targetPath))
            {
                return FilesHaveSameHash(source.SourcePath, targetPath, sourceHash)
                    ? DesktopImportPreviewStatus.Duplicate
                    : DesktopImportPreviewStatus.NameConflict;
            }

            return RepositoryContainsHash(repoPath, source.SourcePath, sourceHash)
                ? DesktopImportPreviewStatus.Duplicate
                : DesktopImportPreviewStatus.Ready;
        }
        catch (IOException)
        {
            return DesktopImportPreviewStatus.Unreadable;
        }
        catch (UnauthorizedAccessException)
        {
            return DesktopImportPreviewStatus.Unreadable;
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
            WindowsImportFileProbeResult source = Probe(item.SourcePath);
            if (!source.IsReadable)
            {
                reasons.Add($"{item.FileName}: {source.ReadFailure ?? "source file is not readable"}");
                continue;
            }

            if (!source.CanRemove)
            {
                reasons.Add($"{item.FileName}: {source.RemoveFailure ?? "source location does not allow removal"}");
            }
        }

        return new DesktopImportMovePreflight(reasons.Count == 0, reasons.Distinct().ToArray());
    }

    public IReadOnlyList<DesktopImportSource> ExpandSources(IEnumerable<string> sourcePaths)
    {
        List<DesktopImportSource> sources = [];
        foreach (string sourcePath in sourcePaths)
        {
            string trimmed = sourcePath.Trim();
            if (File.Exists(trimmed))
            {
                sources.Add(new DesktopImportSource(trimmed));
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
            .DistinctBy(source => source.SourcePath, StringComparer.OrdinalIgnoreCase)
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
        if ((file.Attributes & FileAttributes.ReadOnly) != 0)
        {
            failure = "source file is read-only";
            return false;
        }

        if (file.Directory is null || !file.Directory.Exists)
        {
            failure = "source folder is unavailable";
            return false;
        }

        if ((file.Directory.Attributes & FileAttributes.ReadOnly) != 0)
        {
            failure = "source folder is read-only";
            return false;
        }

        failure = null;
        return true;
    }

    private static bool DirectoryAllowsWrite(string directoryPath)
    {
        if (string.IsNullOrWhiteSpace(directoryPath))
        {
            return false;
        }

        DirectoryInfo directory = new(Path.GetFullPath(directoryPath));
        return directory.Exists && (directory.Attributes & FileAttributes.ReadOnly) == 0;
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

    public WindowsImportFileProbeResult ResolveReplacePreflight(
        string repoPath,
        WindowsImportFileProbeResult source,
        string suggestedCategory,
        string suggestedName)
    {
        if (!source.IsReadable)
        {
            return source;
        }

        string targetPath = TargetPath(repoPath, suggestedCategory, suggestedName, source.FileName);
        if (!File.Exists(targetPath))
        {
            return source with
            {
                TargetPath = targetPath
            };
        }

        return source with
        {
            ExistingConflictPath = targetPath,
            TargetPath = targetPath,
            ReplacePreflightAvailable = false,
            ReplaceBlockedReason = "Replace requires Core import conflict preview with Recycle Bin safety state."
        };
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
        if (string.Equals(fullPath, sourcePath, StringComparison.OrdinalIgnoreCase))
        {
            return true;
        }

        string metadataRoot = Path.Combine(Path.GetFullPath(repoPath), ".areamatrix");
        return fullPath.StartsWith(metadataRoot + Path.DirectorySeparatorChar, StringComparison.OrdinalIgnoreCase);
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
        string normalizedRoot = Path.GetFullPath(rootPath);
        foreach (string filePath in Directory.EnumerateFiles(normalizedRoot, "*", SearchOption.AllDirectories)
                     .Where(IsSupportedFolderFile))
        {
            string? relativeDirectory = RelativeDirectory(normalizedRoot, filePath);
            yield return new DesktopImportSource(filePath, normalizedRoot, relativeDirectory);
        }
    }

    private static bool IsSupportedFolderFile(string filePath)
    {
        string[] parts = filePath.Split(Path.DirectorySeparatorChar, Path.AltDirectorySeparatorChar);
        if (parts.Any(part => SkippedDirectoryNames.Contains(part)))
        {
            return false;
        }

        return !string.Equals(Path.GetFileName(filePath), ".DS_Store", StringComparison.OrdinalIgnoreCase);
    }

    private static string? RelativeDirectory(string rootPath, string filePath)
    {
        string relativePath = Path.GetRelativePath(rootPath, filePath);
        string? directory = Path.GetDirectoryName(relativePath);
        return string.IsNullOrWhiteSpace(directory) ? null : directory;
    }
}
