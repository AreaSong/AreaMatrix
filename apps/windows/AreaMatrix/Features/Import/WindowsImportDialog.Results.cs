using System;
using System.IO;
using System.Threading.Tasks;
using Microsoft.UI.Xaml;
using Microsoft.UI.Xaml.Controls;
using Windows.Storage;
using Windows.System;

namespace AreaMatrix.Features.Import;

public sealed partial class WindowsImportDialog
{
    private async void RetryFailedButton_Click(object sender, RoutedEventArgs e)
    {
        if (ViewModel is null || sender is not Button { DataContext: DesktopImportResult result })
        {
            return;
        }

        await ViewModel.RetryFailedAsync(result);
        RefreshState();
    }

    private async void ShowOriginalButton_Click(object sender, RoutedEventArgs e)
    {
        if (sender is Button { DataContext: DesktopImportResult result })
        {
            await LaunchPathAsync(result.SourcePath);
        }
    }

    private async void ShowImportedFileButton_Click(object sender, RoutedEventArgs e)
    {
        if (ViewModel is not { } model || sender is not Button { DataContext: DesktopImportResult result })
        {
            return;
        }

        await LaunchPathAsync(RepositoryPathForResult(model.RepoPath, result));
    }

    private async void ShowDetailsButton_Click(object sender, RoutedEventArgs e)
    {
        if (sender is Button { DataContext: DesktopImportResult result })
        {
            await ShowResultDetailsAsync(result);
        }
    }

    private async void ShowInExplorerButton_Click(object sender, RoutedEventArgs e)
    {
        if (ViewModel is { } model)
        {
            await LaunchPathAsync(model.RepoPath);
        }
    }

    private void ViewImportedFilesButton_Click(object sender, RoutedEventArgs e)
    {
        RequestClose();
    }

    private static string? RepositoryPathForResult(string repoPath, DesktopImportResult result)
    {
        if (result.Entry is not { } entry || string.IsNullOrWhiteSpace(repoPath))
        {
            return null;
        }

        return Path.Combine(repoPath, entry.Path);
    }

    private static async Task LaunchPathAsync(string? path)
    {
        if (string.IsNullOrWhiteSpace(path))
        {
            return;
        }

        if (Directory.Exists(path))
        {
            StorageFolder folder = await StorageFolder.GetFolderFromPathAsync(path);
            await Launcher.LaunchFolderAsync(folder);
            return;
        }

        if (!File.Exists(path))
        {
            return;
        }

        string? parentPath = Path.GetDirectoryName(path);
        if (string.IsNullOrWhiteSpace(parentPath))
        {
            return;
        }

        StorageFolder parent = await StorageFolder.GetFolderFromPathAsync(parentPath);
        StorageFile file = await StorageFile.GetFileFromPathAsync(path);
        FolderLauncherOptions options = new();
        options.ItemsToSelect.Add(file);
        await Launcher.LaunchFolderAsync(parent, options);
    }

    private async Task ShowResultDetailsAsync(DesktopImportResult result)
    {
        ContentDialog dialog = new()
        {
            XamlRoot = XamlRoot,
            Title = result.SummaryText,
            Content = result.DetailText,
            CloseButtonText = "Close"
        };
        await dialog.ShowAsync();
    }
}
