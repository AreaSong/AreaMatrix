using System.Xml.Linq;
using AreaMatrixTests.ChooseRepository;

namespace AreaMatrixTests.Import;

public static class WindowsImportSmokeTests
{
    private static readonly XNamespace Xaml = "http://schemas.microsoft.com/winfx/2006/xaml";

    public static void RunAll()
    {
        ImportDialogExposesS4Win05C413UserActions();
        MainWindowWiresImportDialogToRealCoreBridge();
        NativeCoreClientExportsDesktopImportContract();
    }

    private static void ImportDialogExposesS4Win05C413UserActions()
    {
        XElement page = LoadXml(RepositoryPath(
            "apps/windows/AreaMatrix/Features/Import/WindowsImportDialog.xaml"));

        TestAssert.Equal(
            "AreaMatrix.Features.Import.WindowsImportDialog",
            AttributeValue(page, Xaml + "Class"),
            "WindowsImportDialog x:Class");
        TestAssert.Equal("True", AttributeValue(page, "AllowDrop"), "drag drop enabled");
        TestAssert.Equal("ImportDialog_Drop", AttributeValue(page, "Drop"), "drop handler");
        AssertButton(page, "Add files...", "AddFilesButton_Click");
        AssertButton(page, "Add folder...", "AddFolderButton_Click");
        AssertButton(page, "Prepare preview", "PreparePreviewButton_Click");
        AssertButton(page, "Use Copy instead", "UseCopyInsteadButton_Click");
        AssertButton(page, "Import", "ImportButton_Click");
        AssertNamedElement(page, "ListView", "PreviewListView");
        AssertNamedElement(page, "StackPanel", "MoveConfirmationSection");
        AssertNamedElement(page, "ListView", "ResultsListView");

        string xaml = File.ReadAllText(RepositoryPath(
            "apps/windows/AreaMatrix/Features/Import/WindowsImportDialog.xaml"));
        TestAssert.Contains("Move originals after import?", xaml, "Move confirmation title");
        TestAssert.Contains("MovePreflightInfoBar", xaml, "Move preflight status");
        TestAssert.Contains("Preserve folder structure", xaml, "folder import option");
        TestAssert.DoesNotContain("Replace existing file", xaml, "C4-21 Replace must stay out of C4-13 task");
        TestAssert.DoesNotContain("Overwrite", xaml, "destructive overwrite must stay hidden");
        TestAssert.DoesNotContain("Index in place", xaml, "index mode is outside Windows MVP import task");
    }

    private static void MainWindowWiresImportDialogToRealCoreBridge()
    {
        XElement window = LoadXml(RepositoryPath("apps/windows/AreaMatrix/MainWindow.xaml"));
        AssertNamedElement(window, "WindowsImportDialog", "WindowsImportPage");

        string mainWindow = File.ReadAllText(RepositoryPath("apps/windows/AreaMatrix/MainWindow.xaml.cs"));
        TestAssert.Contains("new DesktopImportCoreBridge(coreClient, new WindowsImportFileProbe())", mainWindow, "real import bridge");
        TestAssert.Contains("OpenImportRequested", mainWindow, "main import route");
        TestAssert.Contains("WindowsImportPage.OpenRepository(route.RepoPath)", mainWindow, "repository handoff");
        TestAssert.Contains("WindowNative.GetWindowHandle(this)", mainWindow, "picker window handle");

        string mainView = File.ReadAllText(RepositoryPath(
            "apps/windows/AreaMatrix/Features/Library/WindowsMainWindow.xaml"));
        TestAssert.Contains("Label=\"Import\"", mainView, "main window import button");

        string mainViewCode = File.ReadAllText(RepositoryPath(
            "apps/windows/AreaMatrix/Features/Library/WindowsMainWindow.xaml.cs"));
        TestAssert.Contains("OpenImportRequested", mainViewCode, "main window import event");
        TestAssert.Contains("ImportButton_Click", mainViewCode, "import button handler");
    }

    private static void NativeCoreClientExportsDesktopImportContract()
    {
        string nativeLibrary = File.ReadAllText(RepositoryPath(
            "apps/windows/AreaMatrix/Core/NativeCoreLibrary.cs"));
        TestAssert.Contains(
            "uniffi_area_matrix_core_fn_func_predict_category",
            nativeLibrary,
            "predict_category native binding");
        TestAssert.Contains(
            "uniffi_area_matrix_core_fn_func_import_file_with_result",
            nativeLibrary,
            "import_file_with_result native binding");

        string nativeClient = File.ReadAllText(RepositoryPath(
            "apps/windows/AreaMatrix/Core/AreaMatrixNativeCoreClient.DesktopImport.cs"));
        TestAssert.Contains("PredictCategoryAsync", nativeClient, "predict bridge call");
        TestAssert.Contains("ImportFileWithResultAsync", nativeClient, "import result bridge call");
        TestAssert.Contains("ReadImportSourceRemovalStatus", nativeClient, "source removal status mapping");
        TestAssert.Contains("WriteDuplicateStrategy", nativeClient, "duplicate strategy mapping");
        TestAssert.DoesNotContain("\"Overwrite\" => 2", nativeClient, "C4-21 overwrite not exposed");

        string models = File.ReadAllText(RepositoryPath(
            "apps/windows/AreaMatrix/Features/Import/DesktopImportModels.cs"));
        TestAssert.Contains("Duplicate", models, "duplicate preview status");
        TestAssert.Contains("NameConflict", models, "name conflict preview status");

        string probe = File.ReadAllText(RepositoryPath(
            "apps/windows/AreaMatrix/Features/Import/WindowsImportFileProbe.cs"));
        TestAssert.Contains("HashFile", probe, "hash duplicate preflight");
        TestAssert.Contains("CanRemoveSource", probe, "move source removal preflight");
        TestAssert.Contains("staging", probe, "staging availability preflight");

        string viewModel = File.ReadAllText(RepositoryPath(
            "apps/windows/AreaMatrix/Features/Import/WindowsImportViewModel.cs"));
        TestAssert.Contains("MovePreflight.CanMove", viewModel, "move preflight gates import");
        TestAssert.Contains("item.IsImportable", viewModel, "non-importable conflict rows are skipped");
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
