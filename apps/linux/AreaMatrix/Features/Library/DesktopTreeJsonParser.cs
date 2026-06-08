using System.Text.Json;

namespace AreaMatrix.Linux.Features.Library;

internal static class DesktopTreeJsonParser
{
    public static IReadOnlyList<DesktopCategoryNode> ParseVisibleCategories(string treeJson)
    {
        if (string.IsNullOrWhiteSpace(treeJson))
        {
            return [];
        }

        try
        {
            using JsonDocument document = JsonDocument.Parse(treeJson);
            DesktopCategoryNode root = ReadNode(document.RootElement);
            return root.Flatten().ToArray();
        }
        catch (JsonException exception)
        {
            throw new DesktopQueryCoreException(
                DesktopQueryErrorKind.Config,
                $"AreaMatrix Core returned invalid tree JSON: {exception.Message}");
        }
    }

    private static DesktopCategoryNode ReadNode(JsonElement element)
    {
        List<DesktopCategoryNode> children = [];
        if (element.TryGetProperty("children", out JsonElement childElements)
            && childElements.ValueKind == JsonValueKind.Array)
        {
            foreach (JsonElement child in childElements.EnumerateArray())
            {
                children.Add(ReadNode(child));
            }
        }

        return new DesktopCategoryNode(
            ReadString(element, "slug"),
            ReadString(element, "display_name"),
            ReadString(element, "kind"),
            ReadString(element, "relative_path"),
            ReadInt64(element, "file_count"),
            ReadInt64(element, "size_bytes"),
            checked((int)ReadInt64(element, "depth")),
            children);
    }

    private static string ReadString(JsonElement element, string name)
    {
        if (!element.TryGetProperty(name, out JsonElement property))
        {
            return string.Empty;
        }

        return property.ValueKind == JsonValueKind.String
            ? property.GetString() ?? string.Empty
            : property.ToString();
    }

    private static long ReadInt64(JsonElement element, string name)
    {
        if (!element.TryGetProperty(name, out JsonElement property))
        {
            return 0;
        }

        return property.ValueKind == JsonValueKind.Number && property.TryGetInt64(out long value)
            ? value
            : 0;
    }
}
