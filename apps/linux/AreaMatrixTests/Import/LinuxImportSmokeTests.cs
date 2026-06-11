using System.Xml.Linq;
using AreaMatrix.Linux.Tests.ChooseRepository;

namespace AreaMatrix.Linux.Tests.Import;

public static class LinuxImportSmokeTests
{
    public static void RunAll()
    {
        ImportDialogExposesS4Lnx05C413UserActions();
        LinuxDesktopShellWiresImportDialogToRealCoreBridge();
        NativeClientExportsDesktopImportContract();
    }

    private static void ImportDialogExposesS4Lnx05C413UserActions()
    {
        XElement dialogRoot = LoadXml(RepositoryPath(
            "apps/linux/AreaMatrix/Features/Import/LinuxImportDialog.ui"));
        string dialog = File.ReadAllText(RepositoryPath(
            "apps/linux/AreaMatrix/Features/Import/LinuxImportDialog.cs"));
        string viewModel = File.ReadAllText(RepositoryPath(
            "apps/linux/AreaMatrix/Features/Import/LinuxImportViewModel.cs"));
        string requestModel = File.ReadAllText(RepositoryPath(
            "apps/linux/AreaMatrix/Features/Import/LinuxImportViewModel.Requests.cs"));
        string resultModel = File.ReadAllText(RepositoryPath(
            "apps/linux/AreaMatrix/Features/Import/LinuxImportViewModel.Results.cs"));

        AssertObject(dialogRoot, "GtkDialog", "S4Lnx05ImportDialog");
        AssertProperty(dialogRoot, "S4Lnx05ImportDialog", "title", "Import to AreaMatrix");
        AssertObject(dialogRoot, "GtkDropTarget", "ImportDropTarget");
        AssertProperty(dialogRoot, "ImportDropTarget", "actions", "copy");
        AssertButton(dialogRoot, "AddFilesButton", "Add files...", "import.add-files");
        AssertButton(dialogRoot, "AddFolderButton", "Add folder...", "import.add-folder");
        AssertButton(dialogRoot, "UseCopyInsteadButton", "Use Copy instead", "import.use-copy-instead");
        AssertButton(dialogRoot, "ImportButton", "Import", "import.commit");
        AssertObject(dialogRoot, "GtkColumnView", "PreviewListView");
        AssertObject(dialogRoot, "GtkBox", "MoveConfirmationSection");
        AssertObject(dialogRoot, "GtkListView", "ResultsListView");
        AssertLabel(dialogRoot, "MoveConfirmationTitle", "Move originals after import?");
        AssertLabel(dialogRoot, "MovePermissionText", "AreaMatrix will not ask for sudo or change permissions.");
        AssertLabel(dialogRoot, "MoveRetainedText", "Imported, original retained");

        TestAssert.Contains("AddFilesAsync", dialog, "add files action");
        TestAssert.Contains("AddFolderAsync", dialog, "add folder action");
        TestAssert.Contains("DropPathsAsync", dialog, "drop action");
        TestAssert.Contains("PreparePreviewAsync", dialog, "preview action");
        TestAssert.Contains("ImportAsync", dialog, "import action");
        TestAssert.Contains("RetryFailedAsync", dialog, "retry action");
        TestAssert.Contains("ConfirmMoveOriginals", dialog, "move confirmation action");
        TestAssert.Contains("MovePreflight.CanMove", viewModel, "move gate");
        TestAssert.Contains("DesktopImportDuplicateStrategy.KeepBoth", requestModel, "name conflict keep both");
        TestAssert.Contains("ImportFileWithResultAsync", resultModel, "committed import bridge");
        AssertObject(dialogRoot, "GtkBox", "ReplaceConfirmationSection");
        AssertButton(dialogRoot, "PreviewReplaceButton", "Preview Replace", "import.preview-replace");
        AssertButton(dialogRoot, "ApplyReplaceButton", "Apply Replace", "import.apply-replace");
        AssertButton(dialogRoot, "CancelReplaceButton", "Cancel Replace", "import.cancel-replace");
        AssertLabel(dialogRoot, "ReplaceConfirmationTitle", "Replace existing file?");
        AssertLabel(dialogRoot, "ReplaceTrashText", "Trash before replacement");
        TestAssert.Contains("PreviewReplaceAsync", dialog, "replace preview action");
        TestAssert.Contains("ApplyReplaceAsync", dialog, "replace apply action");
        TestAssert.Contains("ConfirmReplace", dialog, "replace confirmation action");
        TestAssert.Contains("ReplaceConfirmed", File.ReadAllText(RepositoryPath(
            "apps/linux/AreaMatrix/Features/Import/LinuxImportViewModel.Replace.cs")), "replace second confirmation gate");
        TestAssert.Contains(
            "ApplyReplaceConflictAsync",
            File.ReadAllText(RepositoryPath("apps/linux/AreaMatrix/Features/Import/LinuxImportViewModel.Replace.cs")),
            "confirmed replace core apply path");
        TestAssert.NotContains("MakeReplaceRequest", requestModel, "no replace overwrite request");
    }

    private static void LinuxDesktopShellWiresImportDialogToRealCoreBridge()
    {
        string shell = File.ReadAllText(RepositoryPath(
            "apps/linux/AreaMatrix/Features/Library/LinuxDesktopShell.cs"));

        TestAssert.Contains("DesktopImportCoreBridge importBridge = new(nativeCoreClient, new LinuxImportFileProbe())", shell, "real import bridge");
        TestAssert.Contains("new LinuxImportDialogFactory(importBridge)", shell, "import factory");
        TestAssert.Contains("OpenImportAsync", shell, "import route");
        TestAssert.Contains("OpenImportWithSourcesAsync", shell, "dropped sources route");
        TestAssert.Contains("dialog.OpenRepositoryWithSourcesAsync(route.RepoPath, sourcePaths", shell, "repository and source handoff");
        TestAssert.NotContains("FakeDesktopImportCoreBridge", shell, "no fake import bridge in production shell");
    }

    private static void NativeClientExportsDesktopImportContract()
    {
        string nativeLibrary = File.ReadAllText(RepositoryPath(
            "apps/linux/AreaMatrix/Core/NativeCoreLibrary.cs"));
        string nativeClient = File.ReadAllText(RepositoryPath(
            "apps/linux/AreaMatrix/Core/AreaMatrixNativeCoreClient.DesktopImport.cs"));
        string coreClient = File.ReadAllText(RepositoryPath(
            "apps/linux/AreaMatrix/Core/AreaMatrixNativeCoreClient.cs"));

        TestAssert.Contains(
            "uniffi_area_matrix_core_fn_func_predict_category",
            nativeLibrary,
            "predict_category native binding");
        TestAssert.Contains(
            "uniffi_area_matrix_core_fn_func_import_file_with_result",
            nativeLibrary,
            "import_file_with_result native binding");
        TestAssert.Contains("PredictCategoryChecksum = 65047", coreClient, "predict checksum");
        TestAssert.Contains("ImportFileWithResultChecksum = 52959", coreClient, "import checksum");
        TestAssert.Contains("PredictCategoryAsync", nativeClient, "predict bridge call");
        TestAssert.Contains("ImportFileWithResultAsync", nativeClient, "import result bridge call");
        TestAssert.Contains("PreviewImportConflictBatchAsync", nativeClient, "replace preview bridge call");
        TestAssert.Contains("ApplyImportConflictBatchAsync", nativeClient, "replace apply bridge call");
        TestAssert.Contains("ReadImportSourceRemovalStatus", nativeClient, "source removal status mapping");
        TestAssert.Contains("WriteDuplicateStrategy", nativeClient, "duplicate strategy mapping");
        TestAssert.Contains("\"Overwrite\" => 2", nativeClient, "overwrite duplicate strategy mapping");
        TestAssert.Contains(
            "uniffi_area_matrix_core_fn_func_preview_import_conflict_batch",
            nativeLibrary,
            "preview_import_conflict_batch native binding");
        TestAssert.Contains(
            "uniffi_area_matrix_core_fn_func_apply_import_conflict_batch",
            nativeLibrary,
            "apply_import_conflict_batch native binding");
        TestAssert.Contains("PreviewImportConflictBatchChecksum = 52321", coreClient, "replace preview checksum");
        TestAssert.Contains("ApplyImportConflictBatchChecksum = 14573", coreClient, "replace apply checksum");
    }

    private static void AssertButton(
        XElement root,
        string id,
        string label,
        string actionName)
    {
        XElement button = ObjectById(root, id);
        TestAssert.Equal("GtkButton", AttributeValue(button, "class"), $"{id} class");
        AssertProperty(button, "label", label);
        AssertProperty(button, "action-name", actionName);
    }

    private static void AssertLabel(XElement root, string id, string text)
    {
        XElement label = ObjectById(root, id);
        TestAssert.Equal("GtkLabel", AttributeValue(label, "class"), $"{id} class");
        TestAssert.Contains(text, PropertyValue(label, "label"), $"{id} label");
    }

    private static void AssertObject(XElement root, string className, string id)
    {
        XElement obj = ObjectById(root, id);
        TestAssert.Equal(className, AttributeValue(obj, "class"), $"{id} class");
    }

    private static void AssertProperty(XElement root, string id, string name, string value)
    {
        AssertProperty(ObjectById(root, id), name, value);
    }

    private static void AssertProperty(XElement element, string name, string value)
    {
        TestAssert.Equal(value, PropertyValue(element, name), $"{name} property");
    }

    private static XElement ObjectById(XElement root, string id)
    {
        return root.Descendants()
            .FirstOrDefault(element =>
                element.Name.LocalName == "object"
                && AttributeValue(element, "id") == id)
            ?? throw new InvalidOperationException($"GTK object `{id}` was not found.");
    }

    private static string PropertyValue(XElement element, string name)
    {
        return element.Elements()
            .FirstOrDefault(child =>
                child.Name.LocalName == "property"
                && AttributeValue(child, "name") == name)
            ?.Value
            ?? string.Empty;
    }

    private static XElement LoadXml(string path)
    {
        return XDocument.Load(path).Root
            ?? throw new InvalidOperationException($"XML root was not found in `{path}`.");
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
