using System;
using AreaMatrix.Features.Onboarding;
using Microsoft.UI.Xaml;
using Microsoft.UI.Xaml.Controls;

namespace AreaMatrix.Features.Library;

public sealed partial class WatcherStatusView : UserControl
{
    public WatcherStatusView()
    {
        InitializeComponent();
    }

    public event Action? CloseRequested;

    public WindowsRepositoryRoute? Route { get; private set; }

    public void OpenRoute(WindowsRepositoryRoute route)
    {
        Route = route;
        WatcherRouteTextBlock.Text = string.IsNullOrWhiteSpace(route.RepoPath)
            ? "File watcher is not available for this repository."
            : $"Watching: {route.RepoPath}";
    }

    private void CloseWatcherStatusButton_Click(object sender, RoutedEventArgs e)
    {
        CloseRequested?.Invoke();
    }
}
