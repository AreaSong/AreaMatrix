using System;
using System.Collections.Generic;
using System.Linq;

namespace AreaMatrix.Features.Import;

public sealed partial class WindowsImportViewModel
{
    private DesktopImportRequest MakeRequest(DesktopImportPreviewItem item)
    {
        DesktopImportSource? source = sources.FirstOrDefault(candidate =>
            string.Equals(candidate.SourcePath, item.SourcePath, StringComparison.OrdinalIgnoreCase));
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
            DuplicateStrategy,
            MoveConfirmed);
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

    private IReadOnlyList<string> SourcePaths()
    {
        return SourcePathsText
            .Split(['\r', '\n'], StringSplitOptions.RemoveEmptyEntries | StringSplitOptions.TrimEntries)
            .Where(path => !string.IsNullOrWhiteSpace(path))
            .Distinct(StringComparer.OrdinalIgnoreCase)
            .ToArray();
    }
}
