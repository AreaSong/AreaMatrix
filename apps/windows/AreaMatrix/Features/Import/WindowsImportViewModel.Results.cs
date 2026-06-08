using System.Collections.Generic;
using System.Linq;

namespace AreaMatrix.Features.Import;

public sealed partial class WindowsImportViewModel
{
    private static string ResultSummaryFor(IReadOnlyList<DesktopImportResult> currentResults)
    {
        if (currentResults.Any(result => result.IsReplace))
        {
            return currentResults.Count == 1
                ? currentResults[0].SummaryText
                : $"Replaced {currentResults.Count(result => result.IsReplace)} item(s).";
        }

        int retained = currentResults.Count(result =>
            result.SourceRemovalStatus == DesktopImportSourceRemovalStatus.Retained);
        return retained > 0
            ? $"Imported {currentResults.Count} item(s), {retained} original(s) retained"
            : $"Imported {currentResults.Count} item(s)";
    }
}
