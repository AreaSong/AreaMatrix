using System;
using System.Collections.Generic;
using System.Linq;
using System.Threading;
using System.Threading.Tasks;
using AreaMatrix.Features.Onboarding;

namespace AreaMatrix.Features.Library;

public interface IDesktopMainQueryCoreBridge
{
    Task<IReadOnlyList<DesktopFileEntry>> ListFilesAsync(
        string repoPath,
        DesktopFileFilter filter,
        CancellationToken cancellationToken = default);

    Task<DesktopFileEntry> GetFileAsync(
        string repoPath,
        long fileId,
        CancellationToken cancellationToken = default);

    Task<IReadOnlyList<DesktopCategoryNode>> ListCategoriesAsync(
        string repoPath,
        string locale,
        CancellationToken cancellationToken = default);

    Task<DesktopSearchResultPage> SearchFilesAsync(
        string repoPath,
        string query,
        DesktopSearchFilter filter,
        DesktopSearchSort sort,
        DesktopSearchPagination pagination,
        CancellationToken cancellationToken = default);
}

public interface IAreaMatrixDesktopQueryCoreClient
{
    Task<IReadOnlyList<CoreDesktopFileEntry>> ListFilesAsync(
        string repoPath,
        CoreDesktopFileFilter filter,
        CancellationToken cancellationToken = default);

    Task<CoreDesktopFileEntry> GetFileAsync(
        string repoPath,
        long fileId,
        CancellationToken cancellationToken = default);

    Task<string> ListTreeJsonAsync(
        string repoPath,
        string locale,
        CancellationToken cancellationToken = default);

    Task<CoreDesktopSearchResultPage> SearchFilesAsync(
        string repoPath,
        string query,
        CoreDesktopSearchFilter filter,
        string sort,
        CoreDesktopSearchPagination pagination,
        CancellationToken cancellationToken = default);
}

public sealed class DesktopMainQueryCoreBridge : IDesktopMainQueryCoreBridge
{
    private readonly IAreaMatrixDesktopQueryCoreClient coreClient;

    public DesktopMainQueryCoreBridge(IAreaMatrixDesktopQueryCoreClient coreClient)
    {
        this.coreClient = coreClient;
    }

    public async Task<IReadOnlyList<DesktopFileEntry>> ListFilesAsync(
        string repoPath,
        DesktopFileFilter filter,
        CancellationToken cancellationToken = default)
    {
        IReadOnlyList<CoreDesktopFileEntry> entries = await coreClient
            .ListFilesAsync(repoPath, filter.ToCoreFilter(), cancellationToken)
            .ConfigureAwait(false);
        return entries.Select(entry => entry.ToDesktopEntry()).ToArray();
    }

    public async Task<DesktopFileEntry> GetFileAsync(
        string repoPath,
        long fileId,
        CancellationToken cancellationToken = default)
    {
        CoreDesktopFileEntry entry = await coreClient
            .GetFileAsync(repoPath, fileId, cancellationToken)
            .ConfigureAwait(false);
        return entry.ToDesktopEntry();
    }

    public async Task<IReadOnlyList<DesktopCategoryNode>> ListCategoriesAsync(
        string repoPath,
        string locale,
        CancellationToken cancellationToken = default)
    {
        string treeJson = await coreClient
            .ListTreeJsonAsync(repoPath, locale, cancellationToken)
            .ConfigureAwait(false);
        return DesktopTreeJsonParser.ParseVisibleCategories(treeJson);
    }

    public async Task<DesktopSearchResultPage> SearchFilesAsync(
        string repoPath,
        string query,
        DesktopSearchFilter filter,
        DesktopSearchSort sort,
        DesktopSearchPagination pagination,
        CancellationToken cancellationToken = default)
    {
        CoreDesktopSearchResultPage page = await coreClient
            .SearchFilesAsync(
                repoPath,
                query,
                filter.ToCoreFilter(),
                sort.ToCoreSort(),
                pagination.ToCorePagination(),
                cancellationToken)
            .ConfigureAwait(false);
        return page.ToDesktopPage();
    }
}

public sealed record CoreDesktopFileFilter(
    string? Category,
    bool? IncludeDeleted,
    long? ImportedAfter,
    long? ImportedBefore,
    long Limit,
    long Offset);

public sealed record CoreDesktopSearchFilter(
    string Scope,
    string? CurrentPath,
    string? Category,
    string? FileKind,
    IReadOnlyList<string> Tags,
    string TagMatchMode,
    long? ImportedAfter,
    long? ImportedBefore,
    long? ModifiedAfter,
    long? ModifiedBefore,
    string? StorageMode,
    bool? IncludeDeleted);

public sealed record CoreDesktopSearchPagination(long Limit, long Offset);

public sealed record CoreDesktopFileEntry(
    long Id,
    string Path,
    string OriginalName,
    string CurrentName,
    string Category,
    long SizeBytes,
    string HashSha256,
    string StorageMode,
    string Origin,
    string? SourcePath,
    string AvailabilityStatus,
    long ImportedAt,
    long UpdatedAt);

public sealed record CoreDesktopSearchMatch(
    string Field,
    string Kind,
    string Snippet,
    long? Start,
    long? End);

public sealed record CoreDesktopSearchFileResult(
    CoreDesktopFileEntry Entry,
    float Score,
    IReadOnlyList<CoreDesktopSearchMatch> Matches,
    string? NoteSnippet);

public sealed record CoreDesktopSearchDiagnostic(
    string Kind,
    string Severity,
    string Message,
    string? Token,
    long? Start,
    long? End,
    string? Suggestion);

public sealed record CoreDesktopSearchResultPage(
    string Query,
    long TotalCount,
    IReadOnlyList<CoreDesktopSearchFileResult> Results,
    IReadOnlyList<CoreDesktopSearchDiagnostic> Diagnostics,
    string IndexStatus);

internal static class DesktopMainQueryCoreMapping
{
    public static CoreDesktopFileFilter ToCoreFilter(this DesktopFileFilter filter)
    {
        return new CoreDesktopFileFilter(
            filter.Category,
            filter.IncludeDeleted,
            filter.ImportedAfter,
            filter.ImportedBefore,
            filter.Limit,
            filter.Offset);
    }

    public static CoreDesktopSearchFilter ToCoreFilter(this DesktopSearchFilter filter)
    {
        return new CoreDesktopSearchFilter(
            filter.Scope.ToCoreScope(),
            filter.CurrentPath,
            filter.Category,
            filter.FileKind,
            filter.Tags,
            filter.TagMatchMode.ToCoreTagMatchMode(),
            filter.ImportedAfter,
            filter.ImportedBefore,
            filter.ModifiedAfter,
            filter.ModifiedBefore,
            filter.StorageMode?.ToCoreStorageMode(),
            filter.IncludeDeleted);
    }

    public static CoreDesktopSearchPagination ToCorePagination(this DesktopSearchPagination pagination)
    {
        return new CoreDesktopSearchPagination(pagination.Limit, pagination.Offset);
    }

    public static string ToCoreSort(this DesktopSearchSort sort)
    {
        return sort switch
        {
            DesktopSearchSort.Relevance => "Relevance",
            DesktopSearchSort.NewestImported => "NewestImported",
            DesktopSearchSort.NewestModified => "NewestModified",
            DesktopSearchSort.NameAsc => "NameAsc",
            _ => throw new DesktopQueryCoreException(
                DesktopQueryErrorKind.Config,
                $"Unsupported desktop search sort `{sort}`.")
        };
    }

    public static DesktopFileEntry ToDesktopEntry(this CoreDesktopFileEntry entry)
    {
        return new DesktopFileEntry(
            entry.Id,
            entry.Path,
            entry.OriginalName,
            entry.CurrentName,
            entry.Category,
            entry.SizeBytes,
            entry.HashSha256,
            ParseStorageMode(entry.StorageMode),
            ParseOrigin(entry.Origin),
            entry.SourcePath,
            ParseAvailabilityStatus(entry.AvailabilityStatus),
            entry.ImportedAt,
            entry.UpdatedAt);
    }

    public static DesktopSearchResultPage ToDesktopPage(this CoreDesktopSearchResultPage page)
    {
        return new DesktopSearchResultPage(
            page.Query,
            page.TotalCount,
            page.Results.Select(result => result.ToDesktopResult()).ToArray(),
            page.Diagnostics.Select(diagnostic => diagnostic.ToDesktopDiagnostic()).ToArray(),
            ParseIndexStatus(page.IndexStatus));
    }

    public static WindowsRepositoryError ToRepositoryError(this DesktopQueryCoreException exception)
    {
        WindowsRepositoryErrorKind kind = exception.Kind switch
        {
            DesktopQueryErrorKind.Db => WindowsRepositoryErrorKind.Db,
            DesktopQueryErrorKind.RepoNotInitialized => WindowsRepositoryErrorKind.InvalidRepository,
            DesktopQueryErrorKind.FileNotFound => WindowsRepositoryErrorKind.FileNotFound,
            DesktopQueryErrorKind.InvalidPath => WindowsRepositoryErrorKind.InvalidPath,
            DesktopQueryErrorKind.PermissionDenied => WindowsRepositoryErrorKind.PermissionDenied,
            DesktopQueryErrorKind.Config => WindowsRepositoryErrorKind.Config,
            _ => WindowsRepositoryErrorKind.Unavailable
        };

        return new WindowsRepositoryError(kind, exception.Message, exception.Path);
    }

    private static DesktopSearchFileResult ToDesktopResult(this CoreDesktopSearchFileResult result)
    {
        return new DesktopSearchFileResult(
            result.Entry.ToDesktopEntry(),
            result.Score,
            result.Matches.Select(match => match.ToDesktopMatch()).ToArray(),
            result.NoteSnippet);
    }

    private static DesktopSearchMatch ToDesktopMatch(this CoreDesktopSearchMatch match)
    {
        return new DesktopSearchMatch(match.Field, match.Kind, match.Snippet, match.Start, match.End);
    }

    private static DesktopSearchDiagnostic ToDesktopDiagnostic(this CoreDesktopSearchDiagnostic diagnostic)
    {
        return new DesktopSearchDiagnostic(
            diagnostic.Kind,
            diagnostic.Severity,
            diagnostic.Message,
            diagnostic.Token,
            diagnostic.Start,
            diagnostic.End,
            diagnostic.Suggestion);
    }

    private static string ToCoreScope(this DesktopSearchScope scope)
    {
        return scope switch
        {
            DesktopSearchScope.AllRepo => "AllRepo",
            DesktopSearchScope.CurrentNode => "CurrentNode",
            _ => throw new DesktopQueryCoreException(
                DesktopQueryErrorKind.Config,
                $"Unsupported desktop search scope `{scope}`.")
        };
    }

    private static string ToCoreTagMatchMode(this DesktopSearchTagMatchMode mode)
    {
        return mode switch
        {
            DesktopSearchTagMatchMode.Any => "Any",
            DesktopSearchTagMatchMode.All => "All",
            _ => throw new DesktopQueryCoreException(
                DesktopQueryErrorKind.Config,
                $"Unsupported desktop tag match mode `{mode}`.")
        };
    }

    private static string ToCoreStorageMode(this DesktopStorageMode mode)
    {
        return mode switch
        {
            DesktopStorageMode.Moved => "Moved",
            DesktopStorageMode.Copied => "Copied",
            DesktopStorageMode.Indexed => "Indexed",
            _ => throw new DesktopQueryCoreException(
                DesktopQueryErrorKind.Config,
                $"Unsupported desktop storage mode `{mode}`.")
        };
    }

    private static DesktopStorageMode ParseStorageMode(string value)
    {
        return value switch
        {
            "Moved" => DesktopStorageMode.Moved,
            "Copied" => DesktopStorageMode.Copied,
            "Indexed" => DesktopStorageMode.Indexed,
            _ => throw UnknownCoreValue("storage mode", value)
        };
    }

    private static DesktopFileOrigin ParseOrigin(string value)
    {
        return value switch
        {
            "Imported" => DesktopFileOrigin.Imported,
            "Adopted" => DesktopFileOrigin.Adopted,
            "External" => DesktopFileOrigin.External,
            _ => throw UnknownCoreValue("file origin", value)
        };
    }

    private static DesktopFileAvailabilityStatus ParseAvailabilityStatus(string value)
    {
        return value switch
        {
            "Available" => DesktopFileAvailabilityStatus.Available,
            "Missing" => DesktopFileAvailabilityStatus.Missing,
            _ => throw UnknownCoreValue("file availability", value)
        };
    }

    private static DesktopSearchIndexStatus ParseIndexStatus(string value)
    {
        return value switch
        {
            "Ready" => DesktopSearchIndexStatus.Ready,
            "Indexing" => DesktopSearchIndexStatus.Indexing,
            "Unavailable" => DesktopSearchIndexStatus.Unavailable,
            _ => throw UnknownCoreValue("search index status", value)
        };
    }

    private static DesktopQueryCoreException UnknownCoreValue(string label, string value)
    {
        return new DesktopQueryCoreException(
            DesktopQueryErrorKind.Config,
            $"AreaMatrix Core returned an unknown {label} `{value}`.");
    }
}
