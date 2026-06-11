namespace AreaMatrix.Linux.Features.Import;

public sealed partial class LinuxImportViewModel
{
    private DesktopImportRequest MakeRequest(DesktopImportPreviewItem item)
    {
        DesktopImportSource? source = sources.FirstOrDefault(candidate =>
            string.Equals(candidate.SourcePath, item.SourcePath, StringComparison.Ordinal));
        DesktopImportDestination destination = DestinationForRequest();
        string? overrideCategoryValue = destination == DesktopImportDestination.Category
            ? TargetCategory
            : null;

        return new DesktopImportRequest(
            Mode,
            destination,
            TargetDirectoryForRequest(destination, source),
            overrideCategoryValue,
            item.SuggestedName,
            DuplicateStrategyForRequest(item),
            MoveConfirmed);
    }

    private DesktopImportDuplicateStrategy DuplicateStrategyForRequest(DesktopImportPreviewItem item)
    {
        if (item.Status == DesktopImportPreviewStatus.NameConflict)
        {
            return DesktopImportDuplicateStrategy.KeepBoth;
        }

        return DuplicateStrategy;
    }

    private string? TargetDirectoryForRequest(
        DesktopImportDestination destination,
        DesktopImportSource? source)
    {
        if (destination != DesktopImportDestination.SelectedDirectory)
        {
            return null;
        }

        string? baseDirectory = string.IsNullOrWhiteSpace(TargetDirectory)
            ? null
            : TargetDirectory.Trim();
        if (!PreserveFolderStructure || string.IsNullOrWhiteSpace(source?.RelativeDirectory))
        {
            return baseDirectory;
        }

        string relativeDirectory = source.RelativeDirectory.Trim();
        return string.IsNullOrWhiteSpace(baseDirectory)
            ? relativeDirectory
            : $"{baseDirectory.TrimEnd('/', '\\')}/{relativeDirectory.TrimStart('/', '\\')}";
    }

    private DesktopImportDestination DestinationForRequest()
    {
        if (!string.IsNullOrWhiteSpace(TargetDirectory))
        {
            return DesktopImportDestination.SelectedDirectory;
        }

        return string.IsNullOrWhiteSpace(TargetCategory)
            ? DesktopImportDestination.AutoClassify
            : DesktopImportDestination.Category;
    }

    private IReadOnlyList<DesktopImportSource> SourcesForPreview()
    {
        if (sources.Count > 0)
        {
            return sources;
        }

        return SourcePaths()
            .Select(path => new DesktopImportSource(path))
            .ToArray();
    }

    private IReadOnlyList<string> SourcePaths()
    {
        return SourcePathsText
            .Split(['\r', '\n'], StringSplitOptions.RemoveEmptyEntries | StringSplitOptions.TrimEntries)
            .Where(path => !string.IsNullOrWhiteSpace(path))
            .Distinct(StringComparer.Ordinal)
            .ToArray();
    }

    private bool CanImportPreviewItem(DesktopImportPreviewItem item)
    {
        return item.IsImportable
            || item.Status == DesktopImportPreviewStatus.Duplicate
                && DuplicateStrategy == DesktopImportDuplicateStrategy.KeepBoth;
    }
}
