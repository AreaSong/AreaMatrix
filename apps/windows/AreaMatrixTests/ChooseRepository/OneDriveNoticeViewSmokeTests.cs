using System.Xml.Linq;

namespace AreaMatrixTests.ChooseRepository;

public static class OneDriveNoticeViewSmokeTests
{
    private static readonly XNamespace Xaml = "http://schemas.microsoft.com/winfx/2006/xaml";

    public static void RunAll()
    {
        OneDriveNoticePageExposesC408StatusControls();
        MainWindowHostsOneDriveNoticeRoute();
    }

    private static void OneDriveNoticePageExposesC408StatusControls()
    {
        XElement page = LoadXml(RepositoryPath(
            "apps/windows/AreaMatrix/Features/Onboarding/OneDriveNoticeDialog.xaml"));

        TestAssert.Equal(
            "AreaMatrix.Features.Onboarding.OneDriveNoticeDialog",
            AttributeValue(page, Xaml + "Class"),
            "OneDriveNoticeDialog x:Class");
        AssertNamedElement(page, "TextBlock", "FolderTextBlock");
        AssertNamedElement(page, "TextBlock", "SyncProviderTextBlock");
        AssertNamedElement(page, "TextBlock", "CloudStatusTextBlock");
        AssertNamedElement(page, "TextBlock", "StatusSummaryTextBlock");
        AssertNamedElement(page, "ItemsControl", "RiskReasonsList");
        AssertButton(page, "Retry status check", "RetryStatusButton_Click");
        AssertButton(page, "Open OneDrive folder", "OpenOneDriveFolderButton_Click");
        AssertButton(page, "Choose Local Folder", "ChooseLocalFolderButton_Click");
        AssertButton(page, "Close", "CloseButton_Click");

        string viewModel = File.ReadAllText(RepositoryPath(
            "apps/windows/AreaMatrix/Features/Onboarding/OneDriveNoticeViewModel.cs"));
        TestAssert.Contains("DetectCloudStorageStateAsync", viewModel, "C4-08 CoreBridge call");
        TestAssert.Contains("WindowsCloudPermissionState.PermissionDenied", viewModel, "permission mapping");
    }

    private static void MainWindowHostsOneDriveNoticeRoute()
    {
        XElement window = LoadXml(RepositoryPath("apps/windows/AreaMatrix/MainWindow.xaml"));
        AssertNamedElement(window, "OneDriveNoticeDialog", "OneDriveNoticePage");

        string codeBehind = File.ReadAllText(RepositoryPath("apps/windows/AreaMatrix/MainWindow.xaml.cs"));
        TestAssert.Contains("WindowsRepositoryRouteKind.OneDriveNotice", codeBehind, "OneDrive route handling");
        TestAssert.Contains("new OneDriveNoticeViewModel(repositoryBridge)", codeBehind, "real bridge injection");
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
