using System.ComponentModel;
using System.Threading;
using AreaMatrix.Features.Library;
using AreaMatrix.Features.Onboarding;
using AreaMatrix.Features.Recovery;
using Microsoft.UI.Xaml;

namespace AreaMatrix;

public sealed partial class MainWindow
{
    private CancellationTokenSource? routeTransitionCancellation;
    private long routeGeneration;

    private async void ChooseRepositoryViewModel_PropertyChanged(
        object? sender,
        PropertyChangedEventArgs e)
    {
        if (e.PropertyName != nameof(ChooseRepositoryViewModel.Route))
        {
            return;
        }

        if (ChooseRepositoryPage.ViewModel?.Route is not { } route
            || route.Kind == WindowsRepositoryRouteKind.None)
        {
            CancelRouteTransition();
            return;
        }

        RouteTransition transition = BeginRouteTransition();
        try
        {
            if (route.Kind == WindowsRepositoryRouteKind.OneDriveNotice)
            {
                oneDriveNoticeOpenedFromMainWindow = false;
                ChooseRepositoryPage.Visibility = Visibility.Collapsed;
                RepositoryInitConfirmPage.Visibility = Visibility.Collapsed;
                RepositoryAdoptConfirmPage.Visibility = Visibility.Collapsed;
                WindowsMainWindowPage.Visibility = Visibility.Collapsed;
                WindowsImportPage.Visibility = Visibility.Collapsed;
                WatcherStatusPage.Visibility = Visibility.Collapsed;
                RescanConfirmPage.Visibility = Visibility.Collapsed;
                PlatformDifferencesPage.Visibility = Visibility.Collapsed;
                OneDriveNoticePage.Visibility = Visibility.Visible;
                await OneDriveNoticePage.OpenRouteAsync(route, transition.Token);
                if (!IsCurrentRoute(transition))
                {
                    return;
                }

                return;
            }

            if (route.Kind == WindowsRepositoryRouteKind.RepositoryInitConfirm)
            {
                ChooseRepositoryPage.Visibility = Visibility.Collapsed;
                OneDriveNoticePage.Visibility = Visibility.Collapsed;
                RepositoryAdoptConfirmPage.Visibility = Visibility.Collapsed;
                WindowsMainWindowPage.Visibility = Visibility.Collapsed;
                WindowsImportPage.Visibility = Visibility.Collapsed;
                WatcherStatusPage.Visibility = Visibility.Collapsed;
                RescanConfirmPage.Visibility = Visibility.Collapsed;
                PlatformDifferencesPage.Visibility = Visibility.Collapsed;
                RepositoryInitConfirmPage.Visibility = Visibility.Visible;
                await RepositoryInitConfirmPage.OpenRouteAsync(route, transition.Token);
                if (!IsCurrentRoute(transition))
                {
                    return;
                }

                return;
            }

            if (route.Kind == WindowsRepositoryRouteKind.RepositoryAdoptConfirm)
            {
                ChooseRepositoryPage.Visibility = Visibility.Collapsed;
                OneDriveNoticePage.Visibility = Visibility.Collapsed;
                RepositoryInitConfirmPage.Visibility = Visibility.Collapsed;
                WindowsMainWindowPage.Visibility = Visibility.Collapsed;
                WindowsImportPage.Visibility = Visibility.Collapsed;
                WatcherStatusPage.Visibility = Visibility.Collapsed;
                RescanConfirmPage.Visibility = Visibility.Collapsed;
                PlatformDifferencesPage.Visibility = Visibility.Collapsed;
                RepositoryAdoptConfirmPage.Visibility = Visibility.Visible;
                await RepositoryAdoptConfirmPage.OpenRouteAsync(route, transition.Token);
                if (!IsCurrentRoute(transition))
                {
                    return;
                }

                return;
            }

            if (route.Kind != WindowsRepositoryRouteKind.MainWindow)
            {
                return;
            }

            ChooseRepositoryPage.Visibility = Visibility.Collapsed;
            OneDriveNoticePage.Visibility = Visibility.Collapsed;
            RepositoryInitConfirmPage.Visibility = Visibility.Collapsed;
            RepositoryAdoptConfirmPage.Visibility = Visibility.Collapsed;
            WindowsImportPage.Visibility = Visibility.Collapsed;
            WatcherStatusPage.Visibility = Visibility.Collapsed;
            RescanConfirmPage.Visibility = Visibility.Collapsed;
            PlatformDifferencesPage.Visibility = Visibility.Collapsed;
            WindowsMainWindowPage.Visibility = Visibility.Visible;
            await WindowsMainWindowPage.OpenRepositoryAsync(route, transition.Token);
            if (!IsCurrentRoute(transition))
            {
                return;
            }
        }
        catch (OperationCanceledException) when (transition.Token.IsCancellationRequested)
        {
        }
        finally
        {
            EndRouteTransition(transition);
        }
    }

    private async void WindowsMainWindowPage_OpenOneDriveStatusRequested(WindowsRepositoryRoute route)
    {
        RouteTransition transition = BeginRouteTransition();
        try
        {
            oneDriveNoticeOpenedFromMainWindow = true;
            ChooseRepositoryPage.Visibility = Visibility.Collapsed;
            RepositoryInitConfirmPage.Visibility = Visibility.Collapsed;
            RepositoryAdoptConfirmPage.Visibility = Visibility.Collapsed;
            WindowsMainWindowPage.Visibility = Visibility.Collapsed;
            WindowsImportPage.Visibility = Visibility.Collapsed;
            WatcherStatusPage.Visibility = Visibility.Collapsed;
            RescanConfirmPage.Visibility = Visibility.Collapsed;
            PlatformDifferencesPage.Visibility = Visibility.Collapsed;
            OneDriveNoticePage.Visibility = Visibility.Visible;
            await OneDriveNoticePage.OpenRouteAsync(route, transition.Token);
            if (!IsCurrentRoute(transition))
            {
                return;
            }
        }
        catch (OperationCanceledException) when (transition.Token.IsCancellationRequested)
        {
        }
        finally
        {
            EndRouteTransition(transition);
        }
    }

    private async void WindowsMainWindowPage_OpenWatcherStatusRequested(WindowsRepositoryRoute route)
    {
        RouteTransition transition = BeginRouteTransition();
        try
        {
            OneDriveNoticePage.Visibility = Visibility.Collapsed;
            ChooseRepositoryPage.Visibility = Visibility.Collapsed;
            RepositoryInitConfirmPage.Visibility = Visibility.Collapsed;
            RepositoryAdoptConfirmPage.Visibility = Visibility.Collapsed;
            WindowsMainWindowPage.Visibility = Visibility.Collapsed;
            WindowsImportPage.Visibility = Visibility.Collapsed;
            RescanConfirmPage.Visibility = Visibility.Collapsed;
            PlatformDifferencesPage.Visibility = Visibility.Collapsed;
            WatcherStatusPage.Visibility = Visibility.Visible;
            await WatcherStatusPage.OpenRouteAsync(route, transition.Token);
            if (!IsCurrentRoute(transition))
            {
                return;
            }
        }
        catch (OperationCanceledException) when (transition.Token.IsCancellationRequested)
        {
        }
        finally
        {
            EndRouteTransition(transition);
        }
    }

    private async void WindowsMainWindowPage_OpenMissingFileRecoveryRequested(MissingFileRecoveryRoute route)
    {
        RouteTransition transition = BeginRouteTransition();
        try
        {
            ShowMissingFileRecoveryPage();
            await MissingFileRecoveryPage.OpenRouteAsync(route, transition.Token);
            if (!IsCurrentRoute(transition))
            {
                return;
            }
        }
        catch (OperationCanceledException) when (transition.Token.IsCancellationRequested)
        {
        }
        finally
        {
            EndRouteTransition(transition);
        }
    }

    private async void OneDriveNoticePage_OpenWatcherStatusRequested()
    {
        WindowsRepositoryRoute route = OneDriveNoticePage.ViewModel is { } model
            ? new WindowsRepositoryRoute(
                WindowsRepositoryRouteKind.WatcherStatus,
                model.RepositoryPath,
                null,
                null,
                model.CloudState)
            : WindowsRepositoryRoute.None;

        RouteTransition transition = BeginRouteTransition();
        try
        {
            OneDriveNoticePage.Visibility = Visibility.Collapsed;
            ChooseRepositoryPage.Visibility = Visibility.Collapsed;
            RepositoryInitConfirmPage.Visibility = Visibility.Collapsed;
            RepositoryAdoptConfirmPage.Visibility = Visibility.Collapsed;
            WindowsMainWindowPage.Visibility = Visibility.Collapsed;
            WindowsImportPage.Visibility = Visibility.Collapsed;
            RescanConfirmPage.Visibility = Visibility.Collapsed;
            PlatformDifferencesPage.Visibility = Visibility.Collapsed;
            RepositorySettingsPage.Visibility = Visibility.Collapsed;
            WatcherStatusPage.Visibility = Visibility.Visible;
            await WatcherStatusPage.OpenRouteAsync(route, transition.Token);
            if (!IsCurrentRoute(transition))
            {
                return;
            }
        }
        catch (OperationCanceledException) when (transition.Token.IsCancellationRequested)
        {
        }
        finally
        {
            EndRouteTransition(transition);
        }
    }

    private async Task RepositoryInitConfirmPage_RepositoryOpenedRequested(WindowsRepositoryRoute route)
    {
        RouteTransition transition = BeginRouteTransition();
        try
        {
            RepositoryInitConfirmPage.Visibility = Visibility.Collapsed;
            RepositoryAdoptConfirmPage.Visibility = Visibility.Collapsed;
            OneDriveNoticePage.Visibility = Visibility.Collapsed;
            ChooseRepositoryPage.Visibility = Visibility.Collapsed;
            WindowsImportPage.Visibility = Visibility.Collapsed;
            WatcherStatusPage.Visibility = Visibility.Collapsed;
            RescanConfirmPage.Visibility = Visibility.Collapsed;
            PlatformDifferencesPage.Visibility = Visibility.Collapsed;
            RepositorySettingsPage.Visibility = Visibility.Collapsed;
            WindowsMainWindowPage.Visibility = Visibility.Visible;
            await WindowsMainWindowPage.OpenRepositoryAsync(route, transition.Token);
            if (!IsCurrentRoute(transition))
            {
                return;
            }
        }
        catch (OperationCanceledException) when (transition.Token.IsCancellationRequested)
        {
        }
        finally
        {
            EndRouteTransition(transition);
        }
    }

    private async Task RepositoryAdoptConfirmPage_RepositoryOpenedRequested(WindowsRepositoryRoute route)
    {
        RouteTransition transition = BeginRouteTransition();
        try
        {
            RepositoryAdoptConfirmPage.Visibility = Visibility.Collapsed;
            RepositoryInitConfirmPage.Visibility = Visibility.Collapsed;
            OneDriveNoticePage.Visibility = Visibility.Collapsed;
            ChooseRepositoryPage.Visibility = Visibility.Collapsed;
            WindowsImportPage.Visibility = Visibility.Collapsed;
            WatcherStatusPage.Visibility = Visibility.Collapsed;
            RescanConfirmPage.Visibility = Visibility.Collapsed;
            PlatformDifferencesPage.Visibility = Visibility.Collapsed;
            RepositorySettingsPage.Visibility = Visibility.Collapsed;
            WindowsMainWindowPage.Visibility = Visibility.Visible;
            await WindowsMainWindowPage.OpenRepositoryAsync(route, transition.Token);
            if (!IsCurrentRoute(transition))
            {
                return;
            }
        }
        catch (OperationCanceledException) when (transition.Token.IsCancellationRequested)
        {
        }
        finally
        {
            EndRouteTransition(transition);
        }
    }

    private RouteTransition BeginRouteTransition()
    {
        if (routeTransitionCancellation is { } previous)
        {
            previous.Cancel();
        }

        routeGeneration += 1;
        CancellationTokenSource cancellation = new();
        routeTransitionCancellation = cancellation;
        return new RouteTransition(routeGeneration, cancellation, cancellation.Token);
    }

    private void EndRouteTransition(RouteTransition transition)
    {
        if (ReferenceEquals(routeTransitionCancellation, transition.Cancellation))
        {
            routeTransitionCancellation = null;
        }

        transition.Cancellation.Dispose();
    }

    private void CancelRouteTransition()
    {
        routeGeneration += 1;
        if (routeTransitionCancellation is not { } current)
        {
            return;
        }

        routeTransitionCancellation = null;
        current.Cancel();
    }

    private bool IsCurrentRoute(RouteTransition transition)
    {
        return transition.Generation == routeGeneration
            && ReferenceEquals(routeTransitionCancellation, transition.Cancellation)
            && !transition.Token.IsCancellationRequested;
    }

    private readonly record struct RouteTransition(
        long Generation,
        CancellationTokenSource Cancellation,
        CancellationToken Token);
}
