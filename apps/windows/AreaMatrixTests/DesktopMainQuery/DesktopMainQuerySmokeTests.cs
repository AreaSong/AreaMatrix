using System.Xml.Linq;
using AreaMatrixTests.ChooseRepository;

namespace AreaMatrixTests.DesktopMainQuery;

public static class DesktopMainQuerySmokeTests
{
    private static readonly XNamespace Xaml = "http://schemas.microsoft.com/winfx/2006/xaml";

    public static void RunAll()
    {
        MainWindowHostsWindowsMainWindowPage();
        WindowsMainWindowExposesC411UserTriggers();
        NativeClientBindsOnlyC411QueryFunctions();
    }

    private static void MainWindowHostsWindowsMainWindowPage()
    {
        XElement window = LoadXml(RepositoryPath("apps/windows/AreaMatrix/MainWindow.xaml"));
        AssertNamedElement(window, "ChooseRepositoryView", "ChooseRepositoryPage");
        AssertNamedElement(window, "WindowsMainWindow", "WindowsMainWindowPage");

        string codeBehind = File.ReadAllText(RepositoryPath("apps/windows/AreaMatrix/MainWindow.xaml.cs"));
        TestAssert.Contains("new DesktopMainQueryCoreBridge(coreClient)", codeBehind, "desktop query bridge");
        TestAssert.Contains("WindowsRepositoryRouteKind.MainWindow", codeBehind, "main window route");
        TestAssert.Contains("OpenRepositoryAsync(route)", codeBehind, "open repository handoff");
    }

    private static void WindowsMainWindowExposesC411UserTriggers()
    {
        XElement view = LoadXml(RepositoryPath(
            "apps/windows/AreaMatrix/Features/Library/WindowsMainWindow.xaml"));
        TestAssert.Equal(
            "AreaMatrix.Features.Library.WindowsMainWindow",
            AttributeValue(view, Xaml + "Class"),
            "WindowsMainWindow x:Class");
        AssertNamedElement(view, "ListView", "CategoryListView");
        AssertNamedElement(view, "ListView", "FileListView");
        AssertNamedElement(view, "TextBox", "SearchTextBox");
        AssertNamedElement(view, "AppBarButton", "RefreshButton");
        AssertNamedElement(view, "AppBarButton", "OneDriveStatusButton");
        AssertNamedElement(view, "AppBarButton", "WatcherStatusButton");
        AssertButton(view, "Search", "SearchButton_Click");

        string codeBehind = File.ReadAllText(RepositoryPath(
            "apps/windows/AreaMatrix/Features/Library/WindowsMainWindow.xaml.cs"));
        TestAssert.Contains("RefreshAsync", codeBehind, "refresh trigger");
        TestAssert.Contains("OpenOneDriveStatusRequested", codeBehind, "OneDrive status trigger");
        TestAssert.Contains("OpenWatcherStatusRequested", codeBehind, "watcher status trigger");
        TestAssert.Contains("RunSearchAsync", codeBehind, "search trigger");
        TestAssert.Contains("SelectCategoryAsync", codeBehind, "category trigger");
        TestAssert.Contains("SelectFileAsync", codeBehind, "detail trigger");
    }

    private static void NativeClientBindsOnlyC411QueryFunctions()
    {
        string nativeLibrary = File.ReadAllText(RepositoryPath(
            "apps/windows/AreaMatrix/Core/NativeCoreLibrary.cs"));
        TestAssert.Contains(
            "uniffi_area_matrix_core_fn_func_list_files",
            nativeLibrary,
            "list_files native binding");
        TestAssert.Contains(
            "uniffi_area_matrix_core_fn_func_get_file",
            nativeLibrary,
            "get_file native binding");
        TestAssert.Contains(
            "uniffi_area_matrix_core_fn_func_list_tree_json",
            nativeLibrary,
            "list_tree_json native binding");
        TestAssert.Contains(
            "uniffi_area_matrix_core_fn_func_search_files",
            nativeLibrary,
            "search_files native binding");

        string queryClient = File.ReadAllText(RepositoryPath(
            "apps/windows/AreaMatrix/Core/AreaMatrixNativeCoreClient.DesktopMainQuery.cs"));
        TestAssert.Contains("LowerFileFilter", queryClient, "file filter lowering");
        TestAssert.Contains("LowerSearchFilter", queryClient, "search filter lowering");
        TestAssert.Contains("ReadSearchResultPage", queryClient, "search result reading");
        TestAssert.Contains("ReadFileAvailabilityStatus", queryClient, "missing badge reading");
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
