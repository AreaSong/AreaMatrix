using System.Globalization;

namespace AreaMatrix.Linux.Features.Library;

public enum DesktopStorageMode
{
    Moved,
    Copied,
    Indexed
}

public enum DesktopFileOrigin
{
    Imported,
    Adopted,
    External
}

public enum DesktopFileAvailabilityStatus
{
    Available,
    Missing
}

public enum DesktopSearchScope
{
    AllRepo,
    CurrentNode
}

public enum DesktopSearchTagMatchMode
{
    Any,
    All
}

public enum DesktopSearchSort
{
    Relevance,
    NewestImported,
    NewestModified,
    NameAsc
}

public enum DesktopSearchIndexStatus
{
    Ready,
    Indexing,
    Unavailable
}

public enum DesktopQueryErrorKind
{
    Db,
    RepoNotInitialized,
    FileNotFound,
    InvalidPath,
    PermissionDenied,
    Config,
    Unavailable
}

public sealed record DesktopFileFilter(
    string? Category,
    bool? IncludeDeleted,
    long? ImportedAfter,
    long? ImportedBefore,
    long Limit,
    long Offset)
{
    public static DesktopFileFilter Page(string? category, long limit, long offset)
    {
        return new DesktopFileFilter(category, false, null, null, limit, offset);
    }

    public static DesktopFileFilter FirstPage(string? category = null)
    {
        return Page(category, 50, 0);
    }
}

public sealed record DesktopSearchFilter(
    DesktopSearchScope Scope,
    string? CurrentPath,
    string? Category,
    string? FileKind,
    IReadOnlyList<string> Tags,
    DesktopSearchTagMatchMode TagMatchMode,
    long? ImportedAfter,
    long? ImportedBefore,
    long? ModifiedAfter,
    long? ModifiedBefore,
    DesktopStorageMode? StorageMode,
    bool? IncludeDeleted)
{
    public static DesktopSearchFilter AllRepository(string? category = null)
    {
        return new DesktopSearchFilter(
            DesktopSearchScope.AllRepo,
            null,
            category,
            null,
            [],
            DesktopSearchTagMatchMode.Any,
            null,
            null,
            null,
            null,
            null,
            false);
    }
}

public sealed record DesktopSearchPagination(long Limit, long Offset);

public sealed record DesktopFileEntry(
    long Id,
    string Path,
    string OriginalName,
    string CurrentName,
    string Category,
    long SizeBytes,
    string HashSha256,
    DesktopStorageMode StorageMode,
    DesktopFileOrigin Origin,
    string? SourcePath,
    DesktopFileAvailabilityStatus AvailabilityStatus,
    long ImportedAt,
    long UpdatedAt)
{
    public string DisplayName => string.IsNullOrWhiteSpace(CurrentName) ? OriginalName : CurrentName;

    public string SizeText => FormatSize(SizeBytes);

    public string StatusText => AvailabilityStatus == DesktopFileAvailabilityStatus.Missing
        ? "Missing"
        : "Available";

    public string ImportedAtText => FormatTimestamp(ImportedAt);

    public string UpdatedAtText => FormatTimestamp(UpdatedAt);

    private static string FormatSize(long bytes)
    {
        if (bytes < 1024)
        {
            return $"{bytes} B";
        }

        double value = bytes;
        string[] units = ["KB", "MB", "GB", "TB"];
        foreach (string unit in units)
        {
            value /= 1024;
            if (value < 1024)
            {
                return $"{value:0.#} {unit}";
            }
        }

        return $"{value:0.#} PB";
    }

    private static string FormatTimestamp(long unixSeconds)
    {
        if (unixSeconds <= 0)
        {
            return "Unknown";
        }

        return DateTimeOffset
            .FromUnixTimeSeconds(unixSeconds)
            .ToLocalTime()
            .ToString("g", CultureInfo.CurrentCulture);
    }
}

public sealed record DesktopSearchMatch(
    string Field,
    string Kind,
    string Snippet,
    long? Start,
    long? End);

public sealed record DesktopSearchFileResult(
    DesktopFileEntry Entry,
    float Score,
    IReadOnlyList<DesktopSearchMatch> Matches,
    string? NoteSnippet);

public sealed record DesktopSearchDiagnostic(
    string Kind,
    string Severity,
    string Message,
    string? Token,
    long? Start,
    long? End,
    string? Suggestion);

public sealed record DesktopSearchResultPage(
    string Query,
    long TotalCount,
    IReadOnlyList<DesktopSearchFileResult> Results,
    IReadOnlyList<DesktopSearchDiagnostic> Diagnostics,
    DesktopSearchIndexStatus IndexStatus);

public sealed record DesktopCategoryNode(
    string Slug,
    string DisplayName,
    string Kind,
    string RelativePath,
    long FileCount,
    long SizeBytes,
    int Depth,
    IReadOnlyList<DesktopCategoryNode> Children)
{
    public string CountText => FileCount.ToString(CultureInfo.CurrentCulture);

    public IEnumerable<DesktopCategoryNode> Flatten()
    {
        yield return this;
        foreach (DesktopCategoryNode child in Children.SelectMany(child => child.Flatten()))
        {
            yield return child;
        }
    }
}

public sealed record DesktopMainQuerySnapshot(
    IReadOnlyList<DesktopFileEntry> Files,
    IReadOnlyList<DesktopCategoryNode> Categories,
    DesktopFileEntry? SelectedFile,
    long TotalCount,
    string Query,
    DesktopSearchIndexStatus? SearchIndexStatus,
    long Limit,
    long Offset,
    bool HasMore)
{
    public long NextOffset => Offset + Files.Count;

    public string PageText
    {
        get
        {
            if (TotalCount > Files.Count)
            {
                return $"{Files.Count} of {TotalCount} item(s) loaded";
            }

            return HasMore
                ? $"{Files.Count}+ item(s) loaded"
                : $"{Files.Count} item(s) loaded";
        }
    }

    public static DesktopMainQuerySnapshot Empty { get; } = new(
        [],
        [],
        null,
        0,
        string.Empty,
        null,
        50,
        0,
        false);
}

public sealed class DesktopQueryCoreException : Exception
{
    public DesktopQueryCoreException(
        DesktopQueryErrorKind kind,
        string message,
        string? path = null)
        : base(message)
    {
        Kind = kind;
        Path = path;
    }

    public DesktopQueryErrorKind Kind { get; }

    public string? Path { get; }
}
