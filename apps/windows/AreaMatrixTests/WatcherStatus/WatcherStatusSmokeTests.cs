using System.Xml.Linq;
using AreaMatrixTests.ChooseRepository;

namespace AreaMatrixTests.WatcherStatus;

public static class WatcherStatusSmokeTests
{
    private static readonly XNamespace Xaml = "http://schemas.microsoft.com/winfx/2006/xaml";

    public static void RunAll()
    {
        WatcherStatusPageExposesC412StatusSnapshotControls();
        NativeClientBindsC412RecordWatcherHealthOnly();
    }

    private static void WatcherStatusPageExposesC412StatusSnapshotControls()
    {
        XElement page = LoadXml(RepositoryPath(
            "apps/windows/AreaMatrix/Features/Library/WatcherStatusView.xaml"));

        TestAssert.Equal(
            "AreaMatrix.Features.Library.WatcherStatusView",
            AttributeValue(page, Xaml + "Class"),
            "WatcherStatusView x:Class");
        AssertNamedElement(page, "TextBlock", "WatcherRouteTextBlock");
        AssertNamedElement(page, "TextBlock", "WatcherStatusTextBlock");
        AssertNamedElement(page, "TextBlock", "WatcherLastEventTextBlock");
        AssertNamedElement(page, "TextBlock", "WatcherPendingEventsTextBlock");
        AssertNamedElement(page, "TextBlock", "WatcherLastRescanTextBlock");
        AssertNamedElement(page, "ItemsControl", "WatcherRecentEventsList");
        AssertButton(page, "Restart watcher", "RestartWatcherButton_Click");
        AssertButton(page, "Run rescan now", "RunRescanNowButton_Click");
        AssertButton(page, "Export diagnostics", "ExportDiagnosticsButton_Click");
        AssertButton(page, "Open repository folder", "OpenRepositoryFolderButton_Click");
        AssertButton(page, "Close", "CloseWatcherStatusButton_Click");

        string codeBehind = File.ReadAllText(RepositoryPath(
            "apps/windows/AreaMatrix/Features/Library/WatcherStatusView.xaml.cs"));
        TestAssert.Contains("OpenRouteAsync", codeBehind, "watcher status route load");
        TestAssert.Contains("RestartWatcherAsync", codeBehind, "restart watcher trigger");
        TestAssert.Contains("OpenRescanConfirmRequested", codeBehind, "rescan confirmation handoff");
        TestAssert.DoesNotContain("ReindexFromFilesystem", codeBehind, "C4-12 must not run rescan");
        TestAssert.DoesNotContain("SyncExternalChanges", codeBehind, "C4-12 must not sync events");
    }

    private static void NativeClientBindsC412RecordWatcherHealthOnly()
    {
        string nativeLibrary = File.ReadAllText(RepositoryPath(
            "apps/windows/AreaMatrix/Core/NativeCoreLibrary.cs"));
        TestAssert.Contains(
            "uniffi_area_matrix_core_fn_func_record_watcher_health",
            nativeLibrary,
            "record_watcher_health native binding");
        TestAssert.Contains(
            "uniffi_area_matrix_core_checksum_func_record_watcher_health",
            nativeLibrary,
            "record_watcher_health checksum");

        string watcherClient = File.ReadAllText(RepositoryPath(
            "apps/windows/AreaMatrix/Core/AreaMatrixNativeCoreClient.WatcherStatus.cs"));
        TestAssert.Contains("RecordWatcherHealthAsync", watcherClient, "CoreBridge watcher call");
        TestAssert.Contains("LowerWatcherHealthSignal", watcherClient, "watcher signal lowering");
        TestAssert.Contains("ReadWatcherStatusSnapshot", watcherClient, "watcher snapshot reading");
        TestAssert.DoesNotContain("sync_external_changes", watcherClient, "C4-12 must not consume sync API");
        TestAssert.DoesNotContain("set_fs_event_cursor", watcherClient, "C4-12 must not advance cursor");
    }

    private static void AssertButton(XElement root, string content, string clickHandler)
    {
        XElement button = Descendants(root, "Button")
            .FirstOrDefault(element => AttributeValue(element, "Content") == content)
            ?? throw new InvalidOperationException($"Button `{content}` was not found.");

        TestAssert.Equal(clickHandler, AttributeValue(button, "Click"), $"{content} click handler");
    }

    private static void AssertNamedElement(XElement root, string localName, string name)
    {
        _ = Descendants(root, localName)
            .FirstOrDefault(element => AttributeValue(element, Xaml + "Name") == name)
            ?? throw new InvalidOperationException($"{localName} `{name}` was not found.");
    }

    private static IEnumerable<XElement> Descendants(XElement root, string localName)
    {
        return root.Descendants().Where(element => element.Name.LocalName == localName);
    }

    private static XElement LoadXml(string path)
    {
        return XDocument.Load(path).Root
            ?? throw new InvalidOperationException($"XML root was not found in `{path}`.");
    }

    private static string AttributeValue(XElement element, XName name)
    {
        return element.Attribute(name)?.Value ?? string.Empty;
    }

    private static string AttributeValue(XElement element, string localName)
    {
        return element.Attributes().FirstOrDefault(attribute => attribute.Name.LocalName == localName)?.Value
            ?? string.Empty;
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

        throw new InvalidOperationException($"Repository file `{relativePath}` was not found.");
    }
}
