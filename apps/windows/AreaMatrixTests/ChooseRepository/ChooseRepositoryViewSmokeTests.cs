using System.Xml.Linq;

namespace AreaMatrixTests.ChooseRepository;

public static class ChooseRepositoryViewSmokeTests
{
    private static readonly XNamespace Xaml = "http://schemas.microsoft.com/winfx/2006/xaml";

    public static void RunAll()
    {
        WindowsAppProjectBuildsS4Win01Page();
        ChooseRepositoryPageExposesRequiredUserActions();
        MainWindowConnectsPageToRealCoreBridge();
    }

    private static void WindowsAppProjectBuildsS4Win01Page()
    {
        XElement project = LoadXml(RepositoryPath("apps/windows/AreaMatrix/AreaMatrix.Windows.csproj"));

        TestAssert.Equal(
            "WinExe",
            ElementValue(project, "OutputType"),
            "Windows app output type");
        TestAssert.Equal(
            "net9.0-windows10.0.19041.0",
            ElementValue(project, "TargetFramework"),
            "Windows app target framework");
        TestAssert.Equal("true", ElementValue(project, "UseWinUI"), "UseWinUI");
        TestAssert.Equal("None", ElementValue(project, "WindowsPackageType"), "WindowsPackageType");
        TestAssert.Equal(
            "true",
            ElementValue(project, "WindowsAppSDKSelfContained"),
            "WindowsAppSDKSelfContained");
        TestAssert.Contains(
            "Microsoft.WindowsAppSDK",
            File.ReadAllText(RepositoryPath("apps/windows/AreaMatrix/AreaMatrix.Windows.csproj")),
            "Windows App SDK package reference");
    }

    private static void ChooseRepositoryPageExposesRequiredUserActions()
    {
        XElement page = LoadXml(RepositoryPath(
            "apps/windows/AreaMatrix/Features/Onboarding/ChooseRepositoryView.xaml"));

        TestAssert.Equal(
            "AreaMatrix.Features.Onboarding.ChooseRepositoryView",
            AttributeValue(page, Xaml + "Class"),
            "ChooseRepositoryView x:Class");
        TestAssert.Contains(
            "RepositoryFolderTextBox_LostFocus",
            File.ReadAllText(RepositoryPath(
                "apps/windows/AreaMatrix/Features/Onboarding/ChooseRepositoryView.xaml.cs")),
            "typed path validation handler");

        AssertButton(page, "Browse...", "BrowseButton_Click");
        AssertButton(page, "Continue", "ContinueButton_Click");
        AssertButton(page, "Cancel", "CancelButton_Click");
        AssertNamedElement(page, "TextBox", "RepositoryFolderTextBox");
        AssertNamedElement(page, "TextBlock", "StatusTextBlock");
        AssertNamedElement(page, "ProgressRing", "CheckingProgressRing");
    }

    private static void MainWindowConnectsPageToRealCoreBridge()
    {
        XElement window = LoadXml(RepositoryPath("apps/windows/AreaMatrix/MainWindow.xaml"));
        TestAssert.Equal(
            "AreaMatrix.MainWindow",
            AttributeValue(window, Xaml + "Class"),
            "MainWindow x:Class");
        AssertNamedElement(window, "ChooseRepositoryView", "ChooseRepositoryPage");

        string codeBehind = File.ReadAllText(RepositoryPath("apps/windows/AreaMatrix/MainWindow.xaml.cs"));
        TestAssert.Contains(
            "LazyAreaMatrixWindowsCoreClient",
            codeBehind,
            "lazy native core client");
        TestAssert.Contains(
            "new WindowsRepositoryCoreBridge(coreClient)",
            codeBehind,
            "real core bridge connection");
        TestAssert.Contains(
            "new ChooseRepositoryViewModel",
            codeBehind,
            "choose repository view model");
        TestAssert.Contains(
            "DetectCloudStorageStateAsync",
            File.ReadAllText(RepositoryPath(
                "apps/windows/AreaMatrix/Features/Onboarding/WindowsRepositoryCoreBridge.cs")),
            "C4-14 cloud storage bridge");
        TestAssert.Contains(
            "uniffi_area_matrix_core_fn_func_detect_cloud_storage_state",
            File.ReadAllText(RepositoryPath("apps/windows/AreaMatrix/Core/NativeCoreLibrary.cs")),
            "C4-14 native core binding");
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

    private static string ElementValue(XElement root, string localName)
    {
        return root.Descendants()
            .FirstOrDefault(element => element.Name.LocalName == localName)
            ?.Value
            ?? string.Empty;
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
