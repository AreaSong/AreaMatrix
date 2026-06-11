using System.Buffers.Binary;
using AreaMatrix.Linux.Features.Library;
using AreaMatrix.Linux.Features.Onboarding;

namespace AreaMatrix.Linux.Core;

public sealed partial class AreaMatrixNativeCoreClient
{
    public Task<IReadOnlyList<CoreDesktopFileEntry>> ListFilesAsync(
        string repoPath,
        CoreDesktopFileFilter filter,
        CancellationToken cancellationToken = default)
    {
        cancellationToken.ThrowIfCancellationRequested();
        IReadOnlyList<CoreDesktopFileEntry> files = CallWithResult(
            (ref RustCallStatus status) => native.ListFiles(
                LowerString(repoPath),
                LowerFileFilter(filter),
                ref status),
            ReadFileEntries);
        return Task.FromResult(files);
    }

    public Task<CoreDesktopFileEntry> GetFileAsync(
        string repoPath,
        long fileId,
        CancellationToken cancellationToken = default)
    {
        cancellationToken.ThrowIfCancellationRequested();
        CoreDesktopFileEntry entry = CallWithResult(
            (ref RustCallStatus status) => native.GetFile(LowerString(repoPath), fileId, ref status),
            ReadFileEntry);
        return Task.FromResult(entry);
    }

    public Task<string> ListTreeJsonAsync(
        string repoPath,
        string locale,
        CancellationToken cancellationToken = default)
    {
        cancellationToken.ThrowIfCancellationRequested();
        string treeJson = CallWithResult(
            (ref RustCallStatus status) => native.ListTreeJson(
                LowerString(repoPath),
                LowerString(locale),
                ref status),
            reader => reader.ReadStringOrRemainingUtf8());
        return Task.FromResult(treeJson);
    }

    public Task<CoreDesktopSearchResultPage> SearchFilesAsync(
        string repoPath,
        string query,
        CoreDesktopSearchFilter filter,
        string sort,
        CoreDesktopSearchPagination pagination,
        CancellationToken cancellationToken = default)
    {
        cancellationToken.ThrowIfCancellationRequested();
        CoreDesktopSearchResultPage page = CallWithResult(
            (ref RustCallStatus status) => native.SearchFiles(
                LowerString(repoPath),
                LowerString(query),
                LowerSearchFilter(filter),
                LowerSearchSort(sort),
                LowerSearchPagination(pagination),
                ref status),
            ReadSearchResultPage);
        return Task.FromResult(page);
    }

    private IReadOnlyList<CoreDesktopFileEntry> ReadFileEntries(UniFfiReader reader)
    {
        int count = reader.ReadInt32();
        List<CoreDesktopFileEntry> entries = new(count);
        for (int index = 0; index < count; index += 1)
        {
            entries.Add(ReadFileEntry(reader));
        }

        return entries;
    }

    private CoreDesktopFileEntry ReadFileEntry(UniFfiReader reader)
    {
        return new CoreDesktopFileEntry(
            reader.ReadInt64(),
            reader.ReadString(),
            reader.ReadString(),
            reader.ReadString(),
            reader.ReadString(),
            reader.ReadInt64(),
            reader.ReadString(),
            ReadStorageMode(reader),
            ReadFileOrigin(reader),
            ReadOptionalString(reader),
            ReadFileAvailabilityStatus(reader),
            reader.ReadInt64(),
            reader.ReadInt64());
    }

    private CoreDesktopSearchResultPage ReadSearchResultPage(UniFfiReader reader)
    {
        return new CoreDesktopSearchResultPage(
            reader.ReadString(),
            reader.ReadInt64(),
            ReadSearchFileResults(reader),
            ReadSearchDiagnostics(reader),
            ReadSearchIndexStatus(reader));
    }

    private IReadOnlyList<CoreDesktopSearchFileResult> ReadSearchFileResults(UniFfiReader reader)
    {
        int count = reader.ReadInt32();
        List<CoreDesktopSearchFileResult> results = new(count);
        for (int index = 0; index < count; index += 1)
        {
            results.Add(new CoreDesktopSearchFileResult(
                ReadFileEntry(reader),
                reader.ReadSingle(),
                ReadSearchMatches(reader),
                ReadOptionalString(reader)));
        }

        return results;
    }

    private IReadOnlyList<CoreDesktopSearchMatch> ReadSearchMatches(UniFfiReader reader)
    {
        int count = reader.ReadInt32();
        List<CoreDesktopSearchMatch> matches = new(count);
        for (int index = 0; index < count; index += 1)
        {
            matches.Add(new CoreDesktopSearchMatch(
                ReadSearchMatchField(reader),
                ReadSearchMatchKind(reader),
                reader.ReadString(),
                ReadOptionalInt64(reader),
                ReadOptionalInt64(reader)));
        }

        return matches;
    }

    private IReadOnlyList<CoreDesktopSearchDiagnostic> ReadSearchDiagnostics(UniFfiReader reader)
    {
        int count = reader.ReadInt32();
        List<CoreDesktopSearchDiagnostic> diagnostics = new(count);
        for (int index = 0; index < count; index += 1)
        {
            diagnostics.Add(new CoreDesktopSearchDiagnostic(
                ReadSearchDiagnosticKind(reader),
                ReadSearchDiagnosticSeverity(reader),
                reader.ReadString(),
                ReadOptionalString(reader),
                ReadOptionalInt64(reader),
                ReadOptionalInt64(reader),
                ReadOptionalString(reader)));
        }

        return diagnostics;
    }

    private RustBuffer LowerFileFilter(CoreDesktopFileFilter filter)
    {
        List<byte> bytes = [];
        WriteOptionalString(bytes, filter.Category);
        WriteOptionalBool(bytes, filter.IncludeDeleted);
        WriteOptionalInt64(bytes, filter.ImportedAfter);
        WriteOptionalInt64(bytes, filter.ImportedBefore);
        WriteInt64(bytes, filter.Limit);
        WriteInt64(bytes, filter.Offset);
        return RustBufferFromBytes(bytes.ToArray());
    }

    private RustBuffer LowerSearchFilter(CoreDesktopSearchFilter filter)
    {
        List<byte> bytes = [];
        WriteEnum(bytes, filter.Scope switch
        {
            "AllRepo" => 1,
            "CurrentNode" => 2,
            _ => throw UnsupportedQueryValue("search scope", filter.Scope)
        });
        WriteOptionalString(bytes, filter.CurrentPath);
        WriteOptionalString(bytes, filter.Category);
        WriteOptionalString(bytes, filter.FileKind);
        WriteStrings(bytes, filter.Tags);
        WriteEnum(bytes, filter.TagMatchMode switch
        {
            "Any" => 1,
            "All" => 2,
            _ => throw UnsupportedQueryValue("tag match mode", filter.TagMatchMode)
        });
        WriteOptionalInt64(bytes, filter.ImportedAfter);
        WriteOptionalInt64(bytes, filter.ImportedBefore);
        WriteOptionalInt64(bytes, filter.ModifiedAfter);
        WriteOptionalInt64(bytes, filter.ModifiedBefore);
        WriteOptionalStorageMode(bytes, filter.StorageMode);
        WriteOptionalBool(bytes, filter.IncludeDeleted);
        return RustBufferFromBytes(bytes.ToArray());
    }

    private RustBuffer LowerSearchSort(string sort)
    {
        List<byte> bytes = [];
        WriteEnum(bytes, sort switch
        {
            "Relevance" => 1,
            "NewestImported" => 2,
            "NewestModified" => 3,
            "NameAsc" => 4,
            _ => throw UnsupportedQueryValue("search sort", sort)
        });
        return RustBufferFromBytes(bytes.ToArray());
    }

    private RustBuffer LowerSearchPagination(CoreDesktopSearchPagination pagination)
    {
        List<byte> bytes = [];
        WriteInt64(bytes, pagination.Limit);
        WriteInt64(bytes, pagination.Offset);
        return RustBufferFromBytes(bytes.ToArray());
    }

    private static string? ReadOptionalString(UniFfiReader reader)
    {
        return reader.ReadByte() switch
        {
            0 => null,
            1 => reader.ReadString(),
            _ => throw BindingConfigError("AreaMatrix Core returned an invalid optional string tag.")
        };
    }

    private static long? ReadOptionalInt64(UniFfiReader reader)
    {
        return reader.ReadByte() switch
        {
            0 => null,
            1 => reader.ReadInt64(),
            _ => throw BindingConfigError("AreaMatrix Core returned an invalid optional int64 tag.")
        };
    }

    private static string ReadFileOrigin(UniFfiReader reader)
    {
        return reader.ReadInt32() switch
        {
            1 => "Imported",
            2 => "Adopted",
            3 => "External",
            _ => throw BindingConfigError("AreaMatrix Core returned an unknown file origin.")
        };
    }

    private static string ReadStorageMode(UniFfiReader reader)
    {
        return reader.ReadInt32() switch
        {
            1 => "Moved",
            2 => "Copied",
            3 => "Indexed",
            _ => throw BindingConfigError("AreaMatrix Core returned an unknown storage mode.")
        };
    }

    private static string ReadFileAvailabilityStatus(UniFfiReader reader)
    {
        return reader.ReadInt32() switch
        {
            1 => "Available",
            2 => "Missing",
            _ => throw BindingConfigError("AreaMatrix Core returned an unknown availability status.")
        };
    }

    private static string ReadSearchMatchField(UniFfiReader reader)
    {
        return reader.ReadInt32() switch
        {
            1 => "Name",
            2 => "Path",
            3 => "Note",
            4 => "Category",
            5 => "ChangeLog",
            _ => throw BindingConfigError("AreaMatrix Core returned an unknown search match field.")
        };
    }

    private static string ReadSearchMatchKind(UniFfiReader reader)
    {
        return reader.ReadInt32() switch
        {
            1 => "Exact",
            2 => "Fuzzy",
            3 => "PinyinInitials",
            _ => throw BindingConfigError("AreaMatrix Core returned an unknown search match kind.")
        };
    }

    private static string ReadSearchDiagnosticKind(UniFfiReader reader)
    {
        return reader.ReadInt32() switch
        {
            1 => "UnclosedQuote",
            2 => "UnknownField",
            3 => "InvalidDate",
            4 => "UnbalancedParentheses",
            5 => "InvalidOperator",
            _ => throw BindingConfigError("AreaMatrix Core returned an unknown search diagnostic kind.")
        };
    }

    private static string ReadSearchDiagnosticSeverity(UniFfiReader reader)
    {
        return reader.ReadInt32() switch
        {
            1 => "Info",
            2 => "Warning",
            3 => "Error",
            _ => throw BindingConfigError("AreaMatrix Core returned an unknown search diagnostic severity.")
        };
    }

    private static string ReadSearchIndexStatus(UniFfiReader reader)
    {
        return reader.ReadInt32() switch
        {
            1 => "Ready",
            2 => "Indexing",
            3 => "Unavailable",
            _ => throw BindingConfigError("AreaMatrix Core returned an unknown search index status.")
        };
    }

    private static void WriteOptionalString(List<byte> bytes, string? value)
    {
        if (value is null)
        {
            bytes.Add(0);
            return;
        }

        bytes.Add(1);
        WriteString(bytes, value);
    }

    private static void WriteOptionalBool(List<byte> bytes, bool? value)
    {
        if (value is null)
        {
            bytes.Add(0);
            return;
        }

        bytes.Add(1);
        WriteBool(bytes, value.Value);
    }

    private static void WriteOptionalInt64(List<byte> bytes, long? value)
    {
        if (value is null)
        {
            bytes.Add(0);
            return;
        }

        bytes.Add(1);
        WriteInt64(bytes, value.Value);
    }

    private static void WriteOptionalStorageMode(List<byte> bytes, string? mode)
    {
        if (mode is null)
        {
            bytes.Add(0);
            return;
        }

        bytes.Add(1);
        WriteStorageMode(bytes, mode);
    }

    private static void WriteStrings(List<byte> bytes, IReadOnlyList<string> values)
    {
        WriteInt32(bytes, values.Count);
        foreach (string value in values)
        {
            WriteString(bytes, value);
        }
    }

    private static void WriteString(List<byte> bytes, string value)
    {
        byte[] utf8 = System.Text.Encoding.UTF8.GetBytes(value);
        WriteInt32(bytes, utf8.Length);
        bytes.AddRange(utf8);
    }

    private static void WriteStorageMode(List<byte> bytes, string mode)
    {
        WriteEnum(bytes, mode switch
        {
            "Moved" => 1,
            "Copied" => 2,
            "Indexed" => 3,
            _ => throw UnsupportedQueryValue("storage mode", mode)
        });
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

    private static LinuxRepositoryCoreException BindingConfigError(string message)
    {
        return new LinuxRepositoryCoreException(LinuxRepositoryErrorKind.Config, message);
    }

    private static LinuxRepositoryCoreException UnsupportedQueryValue(string label, string value)
    {
        return BindingConfigError($"Unsupported desktop query {label} `{value}`.");
    }
}
