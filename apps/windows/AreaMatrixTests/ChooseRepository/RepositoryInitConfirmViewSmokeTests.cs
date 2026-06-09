using System.Xml.Linq;

namespace AreaMatrixTests.ChooseRepository;

public static class RepositoryInitConfirmViewSmokeTests
{
    private static readonly XNamespace Xaml = "http://schemas.microsoft.com/winfx/2006/xaml";

    public static void RunAll()
    {
        RepositoryInitConfirmPageExposesRequiredActions();
        MainWindowRoutesRepositoryInitConfirmToDedicatedPage();
    }

    private static void RepositoryInitConfirmPageExposesRequiredActions()
    {
        XElement page = LoadXml(RepositoryPath(
            "apps/windows/AreaMatrix/Features/Onboarding/RepositoryInitConfirmDialog.xaml"));

        TestAssert.Equal(
            "AreaMatrix.Features.Onboarding.RepositoryInitConfirmDialog",
            AttributeValue(page, Xaml + "Class"),
            "RepositoryInitConfirmDialog x:Class");
        AssertButton(page, "Create Repository", "CreateRepositoryButton_Click");
        AssertButton(page, "Try Again", "TryAgainButton_Click");
        AssertButton(page, "Choose Another Folder", "ChooseAnotherFolderButton_Click");
        AssertButton(page, "Cancel", "CancelButton_Click");
        AssertNamedElement(page, "TextBlock", "StatusTextBlock");
        AssertNamedElement(page, "TextBlock", "FolderTextBlock");
        AssertNamedElement(page, "TextBlock", "PathTypeTextBlock");
        AssertNamedElement(page, "TextBlock", "WritableTextBlock");
        AssertNamedElement(page, "ProgressRing", "RepositoryInitProgressRing");

        string codeBehind = File.ReadAllText(RepositoryPath(
            "apps/windows/AreaMatrix/Features/Onboarding/RepositoryInitConfirmDialog.xaml.cs"));
        TestAssert.Contains("CreateRepositoryAsync", codeBehind, "create repository action");
        TestAssert.Contains("RepositoryOpenedRequested", codeBehind, "main window handoff");
    }

    private static void MainWindowRoutesRepositoryInitConfirmToDedicatedPage()
    {
        XElement window = LoadXml(RepositoryPath("apps/windows/AreaMatrix/MainWindow.xaml"));
        AssertNamedElement(window, "RepositoryInitConfirmDialog", "RepositoryInitConfirmPage");

        string codeBehind = File.ReadAllText(RepositoryPath("apps/windows/AreaMatrix/MainWindow.xaml.cs"));
        TestAssert.Contains(
            "new RepositoryInitConfirmViewModel(repositoryBridge)",
            codeBehind,
            "real core bridge connection");
        TestAssert.Contains(
            "WindowsRepositoryRouteKind.RepositoryInitConfirm",
            codeBehind,
            "init confirm route handling");
        TestAssert.Contains(
            "RepositoryInitConfirmPage.OpenRouteAsync(route)",
            codeBehind,
            "open route handoff");
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
