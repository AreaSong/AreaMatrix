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
        AssertButton(page, "Show original", "ShowOriginalButton_Click");
        AssertButton(page, "Show imported file", "ShowImportedFileButton_Click");
        AssertButton(page, "Retry failed", "RetryFailedButton_Click");
        AssertButton(page, "Show details", "ShowDetailsButton_Click");
        AssertButton(page, "Show in Explorer", "ShowInExplorerButton_Click");
        AssertButton(page, "View imported files", "ViewImportedFilesButton_Click");
        AssertNamedElement(page, "ListView", "PreviewListView");
        AssertNamedElement(page, "StackPanel", "MoveConfirmationSection");
        AssertNamedElement(page, "ListView", "ResultsListView");

        string xaml = File.ReadAllText(RepositoryPath(
            "apps/windows/AreaMatrix/Features/Import/WindowsImportDialog.xaml"));
        TestAssert.Contains("Move originals after import?", xaml, "Move confirmation title");
        TestAssert.Contains("MovePreflightInfoBar", xaml, "Move preflight status");
        TestAssert.Contains("Preserve folder structure", xaml, "folder import option");
        TestAssert.Contains("Replace existing file", xaml, "C4-21 Replace confirmation title");
        TestAssert.Contains("ReplaceInfoBar", xaml, "replace status info bar");
        TestAssert.Contains("Preview Replace", xaml, "replace preview trigger");
        TestAssert.Contains("Apply Replace", xaml, "replace apply trigger");
        TestAssert.Contains("Close when done", File.ReadAllText(RepositoryPath(
            "apps/windows/AreaMatrix/Features/Import/WindowsImportDialog.xaml.cs")), "importing close semantics");
        TestAssert.Contains("closeWhenDoneRequested", File.ReadAllText(RepositoryPath(
            "apps/windows/AreaMatrix/Features/Import/WindowsImportDialog.xaml.cs")), "deferred close while importing");
        TestAssert.Contains("I understand the existing file will be moved to Recycle Bin", xaml, "replace second confirmation");
        TestAssert.DoesNotContain("Overwrite", xaml, "destructive overwrite wording must stay hidden");
        TestAssert.DoesNotContain("Index in place", xaml, "index mode is outside Windows MVP import task");
    }

    private static void MainWindowWiresImportDialogToRealCoreBridge()
    {
        XElement window = LoadXml(RepositoryPath("apps/windows/AreaMatrix/MainWindow.xaml"));
        AssertNamedElement(window, "WindowsImportDialog", "WindowsImportPage");

        string mainWindow = File.ReadAllText(RepositoryPath("apps/windows/AreaMatrix/MainWindow.xaml.cs"));
        TestAssert.Contains("new DesktopImportCoreBridge(coreClient, new WindowsImportFileProbe())", mainWindow, "real import bridge");
        TestAssert.Contains("OpenImportRequested", mainWindow, "main import route");
        TestAssert.Contains(
            "OpenImportDroppedSourcesRequested",
            mainWindow,
            "main window drag import route");
        TestAssert.Contains(
            "OpenRepositoryWithSourcesAsync(route.RepoPath, sourcePaths)",
            mainWindow,
            "dropped sources handoff");
        TestAssert.Contains("WindowsImportPage.OpenRepository(route.RepoPath)", mainWindow, "repository handoff");
        TestAssert.Contains("WindowsImportCloseRequest request", mainWindow, "import close request");
        TestAssert.Contains("RefreshAndSelectFileAsync(selectedFileId)", mainWindow, "refresh selected imported file");
        TestAssert.Contains("WindowNative.GetWindowHandle(this)", mainWindow, "picker window handle");

        string mainView = File.ReadAllText(RepositoryPath(
            "apps/windows/AreaMatrix/Features/Library/WindowsMainWindow.xaml"));
        TestAssert.Contains("Label=\"Import\"", mainView, "main window import button");
        TestAssert.Contains("AllowDrop=\"True\"", mainView, "main window drop target");
        TestAssert.Contains("DropOverlay", mainView, "main window drop overlay");
        TestAssert.Contains("Drop to import", mainView, "main window drop overlay copy");

        string mainViewCode = File.ReadAllText(RepositoryPath(
            "apps/windows/AreaMatrix/Features/Library/WindowsMainWindow.xaml.cs"));
        TestAssert.Contains("OpenImportRequested", mainViewCode, "main window import event");
        TestAssert.Contains(
            "OpenImportDroppedSourcesRequested",
            mainViewCode,
            "main window dropped source event");
        TestAssert.Contains("ImportButton_Click", mainViewCode, "import button handler");
        TestAssert.Contains("StandardDataFormats.StorageItems", mainViewCode, "Explorer storage item drop");
        TestAssert.Contains("DataPackageOperation.Copy", mainViewCode, "drop operation is copy");
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
        TestAssert.Contains(
            "uniffi_area_matrix_core_fn_func_preview_import_conflict_batch",
            nativeLibrary,
            "preview_import_conflict_batch native binding");
        TestAssert.Contains(
            "uniffi_area_matrix_core_fn_func_apply_import_conflict_batch",
            nativeLibrary,
            "apply_import_conflict_batch native binding");

        string nativeClient = File.ReadAllText(RepositoryPath(
            "apps/windows/AreaMatrix/Core/AreaMatrixNativeCoreClient.DesktopImport.cs"));
        TestAssert.Contains("PredictCategoryAsync", nativeClient, "predict bridge call");
        TestAssert.Contains("ImportFileWithResultAsync", nativeClient, "import result bridge call");
        TestAssert.Contains("ReadImportSourceRemovalStatus", nativeClient, "source removal status mapping");
        TestAssert.Contains("WriteDuplicateStrategy", nativeClient, "duplicate strategy mapping");
        TestAssert.Contains("\"Overwrite\" => 2", nativeClient, "desktop import duplicate strategy mapping");

        string conflictBatchClient = File.ReadAllText(RepositoryPath(
            "apps/windows/AreaMatrix/Core/AreaMatrixNativeCoreClient.ImportConflictBatch.cs"));
        TestAssert.Contains("PreviewImportConflictBatchAsync", conflictBatchClient, "replace preview Core call");
        TestAssert.Contains("ApplyImportConflictBatchAsync", conflictBatchClient, "replace apply Core call");
        TestAssert.Contains("\"Replace\" => 3", conflictBatchClient, "replace strategy lowering");
        TestAssert.Contains("ReplaceConfirmed", conflictBatchClient, "replace confirmation lowering");

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

        string replaceViewModel = File.ReadAllText(RepositoryPath(
            "apps/windows/AreaMatrix/Features/Import/WindowsImportViewModel.Replace.cs"));
        TestAssert.Contains("PreviewReplaceAsync", replaceViewModel, "replace preview action");
        TestAssert.Contains("ApplyReplaceAsync", replaceViewModel, "replace apply action");
        TestAssert.Contains("ReplaceConfirmed", replaceViewModel, "replace second confirmation gate");
        TestAssert.Contains("ApplyReplaceConflictAsync", replaceViewModel, "confirmed replace Core apply path");
        TestAssert.DoesNotContain(
            "DesktopImportDuplicateStrategy.Overwrite",
            replaceViewModel,
            "replace must not use direct desktop import overwrite fallback");
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
