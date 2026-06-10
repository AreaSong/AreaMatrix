using AreaMatrix.Linux.Core;
using AreaMatrix.Linux.Features.Conflicts;
using AreaMatrix.Linux.Features.Help;
using AreaMatrix.Linux.Features.Import;
using AreaMatrix.Linux.Features.Onboarding;
using AreaMatrix.Linux.Features.Recovery;
using AreaMatrix.Linux.Features.Settings;
using AreaMatrix.Linux.Features.System;

namespace AreaMatrix.Linux.Features.Library;

public interface ILinuxMainWindowFactory
{
    LinuxMainWindow Create(LinuxRepositoryRoute route);
}

public interface ILinuxWatcherStatusViewFactory
{
    LinuxWatcherStatusView Create(LinuxRepositoryRoute route);
}

public interface ILinuxRescanConfirmViewFactory
{
    LinuxRescanConfirmView Create(LinuxRescanConfirmRequest request);
}

public interface ILinuxImportDialogFactory
{
    LinuxImportDialog Create(LinuxRepositoryRoute route);
}

public interface ILinuxMissingFileRecoveryViewFactory
{
    MissingFileRecoveryView Create(MissingFileRecoveryRoute route);
}

public interface ILinuxPlatformDifferencesViewFactory
{
    PlatformDifferencesView Create(string? repositoryPath = null);
}

public interface ILinuxRepositorySettingsViewFactory
{
    RepositorySettingsView Create(string? repositoryPath = null);
}

public interface ILinuxLocalFolderNoticeFactory
{
    LocalFolderNoticeView Create(LinuxRepositoryRoute route);
}

public interface ILinuxRepositoryInitConfirmFactory
{
    RepositoryInitConfirmView Create(LinuxRepositoryRoute route);
}

public interface ILinuxRepositoryAdoptConfirmFactory
{
    RepositoryAdoptConfirmView Create(LinuxRepositoryRoute route);
}

public sealed class LinuxDesktopShell : IDisposable
{
    private readonly LinuxChooseRepositoryView chooseRepositoryView;
    private readonly ILinuxLocalFolderNoticeFactory? localFolderNoticeFactory;
    private readonly ILinuxRepositoryInitConfirmFactory? repositoryInitConfirmFactory;
    private readonly ILinuxRepositoryAdoptConfirmFactory? repositoryAdoptConfirmFactory;
    private readonly ILinuxImportDialogFactory? importDialogFactory;
    private readonly ILinuxMissingFileRecoveryViewFactory? missingFileRecoveryViewFactory;
    private readonly ILinuxMainWindowFactory mainWindowFactory;
    private readonly ILinuxPlatformDifferencesViewFactory? platformDifferencesViewFactory;
    private readonly ILinuxRepositorySettingsViewFactory? repositorySettingsViewFactory;
    private readonly ILinuxWatcherStatusViewFactory? watcherStatusViewFactory;
    private readonly ILinuxRescanConfirmViewFactory? rescanConfirmViewFactory;
    private readonly IDisposable? ownedResources;
    private LocalFolderNoticeView? localFolderNoticeView;
    private RepositoryInitConfirmView? repositoryInitConfirmView;
    private RepositoryAdoptConfirmView? repositoryAdoptConfirmView;
    private LinuxImportDialog? importDialog;
    private MissingFileRecoveryView? missingFileRecoveryView;
    private LinuxMainWindow? mainWindow;
    private PlatformDifferencesView? platformDifferencesView;
    private RepositorySettingsView? repositorySettingsView;
    private LinuxWatcherStatusView? watcherStatusView;
    private LinuxRescanConfirmView? rescanConfirmView;
    private bool disposed;

    public LinuxDesktopShell(
        LinuxChooseRepositoryView chooseRepositoryView,
        ILinuxMainWindowFactory mainWindowFactory,
        ILinuxLocalFolderNoticeFactory? localFolderNoticeFactory = null,
        ILinuxRepositoryInitConfirmFactory? repositoryInitConfirmFactory = null,
        ILinuxRepositoryAdoptConfirmFactory? repositoryAdoptConfirmFactory = null,
        ILinuxImportDialogFactory? importDialogFactory = null,
        ILinuxMissingFileRecoveryViewFactory? missingFileRecoveryViewFactory = null,
        ILinuxPlatformDifferencesViewFactory? platformDifferencesViewFactory = null,
        ILinuxRepositorySettingsViewFactory? repositorySettingsViewFactory = null,
        ILinuxWatcherStatusViewFactory? watcherStatusViewFactory = null,
        ILinuxRescanConfirmViewFactory? rescanConfirmViewFactory = null,
        IDisposable? ownedResources = null)
    {
        this.chooseRepositoryView = chooseRepositoryView;
        this.mainWindowFactory = mainWindowFactory;
        this.localFolderNoticeFactory = localFolderNoticeFactory;
        this.repositoryInitConfirmFactory = repositoryInitConfirmFactory;
        this.repositoryAdoptConfirmFactory = repositoryAdoptConfirmFactory;
        this.importDialogFactory = importDialogFactory;
        this.missingFileRecoveryViewFactory = missingFileRecoveryViewFactory;
        this.platformDifferencesViewFactory = platformDifferencesViewFactory;
        this.repositorySettingsViewFactory = repositorySettingsViewFactory;
        this.watcherStatusViewFactory = watcherStatusViewFactory;
        this.rescanConfirmViewFactory = rescanConfirmViewFactory;
        this.ownedResources = ownedResources;
    }

    public LinuxChooseRepositoryView ChooseRepositoryView => chooseRepositoryView;

    public LocalFolderNoticeView? LocalFolderNoticeView => localFolderNoticeView;

    public RepositoryInitConfirmView? RepositoryInitConfirmView => repositoryInitConfirmView;

    public RepositoryAdoptConfirmView? RepositoryAdoptConfirmView => repositoryAdoptConfirmView;

    public LinuxImportDialog? ImportDialog => importDialog;

    public MissingFileRecoveryView? MissingFileRecoveryView => missingFileRecoveryView;

    public PlatformDifferencesView? PlatformDifferencesView => platformDifferencesView;

    public RepositorySettingsView? RepositorySettingsView => repositorySettingsView;

    public LinuxMainWindow? MainWindow => mainWindow;

    public LinuxWatcherStatusView? WatcherStatusView => watcherStatusView;

    public LinuxRescanConfirmView? RescanConfirmView => rescanConfirmView;

    public static LinuxDesktopShell CreateDefault(string locale = "en-US")
    {
        AreaMatrixNativeCoreClient nativeCoreClient = new();
        LinuxRepositoryCoreBridge repositoryBridge = new(nativeCoreClient);
        DesktopMainQueryCoreBridge queryBridge = new(nativeCoreClient);
        SyncConflictEntryCoreBridge syncConflictBridge = new(nativeCoreClient);
        DesktopImportCoreBridge importBridge = new(nativeCoreClient, new LinuxImportFileProbe());
        MissingFileRecoveryCoreBridge recoveryBridge = new(nativeCoreClient);
        LinuxWatcherStatusCoreBridge watcherBridge = new(nativeCoreClient);
        LinuxWatcherDiagnostics watcherDiagnostics = new();
        LinuxChooseRepositoryView chooseRepositoryView = new(
            new LinuxChooseRepositoryViewModel(repositoryBridge),
            new LinuxSystemFolderPickerAdapter());
        return new LinuxDesktopShell(
            chooseRepositoryView,
            new LinuxMainWindowFactory(queryBridge, locale, syncConflictBridge),
            new LinuxLocalFolderNoticeFactory(repositoryBridge),
            new LinuxRepositoryInitConfirmFactory(repositoryBridge),
            new LinuxRepositoryAdoptConfirmFactory(repositoryBridge),
            new LinuxImportDialogFactory(importBridge),
            new LinuxMissingFileRecoveryViewFactory(recoveryBridge),
            new LinuxPlatformDifferencesViewFactory(new PlatformDifferencesCoreBridge(nativeCoreClient)),
            new LinuxRepositorySettingsViewFactory(repositoryBridge, repositoryBridge),
            new LinuxWatcherStatusViewFactory(watcherBridge, watcherDiagnostics),
            new LinuxRescanConfirmViewFactory(watcherBridge),
            nativeCoreClient);
    }

    public async Task ContinueFromRepositorySelectionAsync(
        CancellationToken cancellationToken = default)
    {
        await chooseRepositoryView.ContinueAsync(cancellationToken).ConfigureAwait(false);
        await ConsumeRouteAsync(cancellationToken).ConfigureAwait(false);
    }

    public async Task OpenWatcherStatusAsync(CancellationToken cancellationToken = default)
    {
        if (mainWindow is null || string.IsNullOrWhiteSpace(mainWindow.ViewModel.RepoPath))
        {
            return;
        }

        if (watcherStatusViewFactory is null)
        {
            throw new InvalidOperationException("Linux watcher status route has no view factory.");
        }

        LinuxRepositoryRoute route = new(
            LinuxRepositoryRouteKind.MainWindow,
            mainWindow.ViewModel.RepoPath,
            null);
        LinuxWatcherStatusView view = watcherStatusViewFactory.Create(route);
        await view.OpenRouteAsync(route, cancellationToken).ConfigureAwait(false);
        view.OpenRescanConfirmRequested += WatcherStatusView_OpenRescanConfirmRequested;
        watcherStatusView = view;
    }

    public Task OpenImportAsync(CancellationToken cancellationToken = default)
    {
        return OpenImportWithSourcesAsync([], cancellationToken);
    }

    public async Task OpenPlatformDifferencesAsync(CancellationToken cancellationToken = default)
    {
        if (platformDifferencesViewFactory is null)
        {
            throw new InvalidOperationException("Linux platform differences route has no view factory.");
        }

        string? repositoryPath = repositorySettingsView?.ViewModel.RepositoryPath
            ?? mainWindow?.ViewModel.RepoPath;
        PlatformDifferencesView view = platformDifferencesViewFactory.Create(repositoryPath);
        view.OpenRepositorySettingsRequested += async () =>
            await OpenRepositorySettingsAsync(cancellationToken).ConfigureAwait(false);
        await view.OpenAsync(cancellationToken).ConfigureAwait(false);
        platformDifferencesView = view;
    }

    public async Task OpenRepositorySettingsAsync(CancellationToken cancellationToken = default)
    {
        if (repositorySettingsViewFactory is null)
        {
            throw new InvalidOperationException("Linux repository settings route has no view factory.");
        }

        string? repositoryPath = platformDifferencesView?.ViewModel.RepositoryPath
            ?? mainWindow?.ViewModel.RepoPath;
        RepositorySettingsView view = repositorySettingsViewFactory.Create(repositoryPath);
        view.ReconnectRepositoryRequested += ReturnToChooseRepository;
        view.ChooseAnotherFolderRequested += ReturnToChooseRepository;
        view.PlatformCapabilitiesRequested += async () =>
            await OpenPlatformDifferencesAsync(cancellationToken).ConfigureAwait(false);
        await view.OpenAsync(cancellationToken).ConfigureAwait(false);
        repositorySettingsView = view;
    }

    public async Task OpenImportWithSourcesAsync(
        IEnumerable<string> sourcePaths,
        CancellationToken cancellationToken = default)
    {
        cancellationToken.ThrowIfCancellationRequested();
        if (mainWindow is null || string.IsNullOrWhiteSpace(mainWindow.ViewModel.RepoPath))
        {
            return;
        }

        if (importDialogFactory is null)
        {
            throw new InvalidOperationException("Linux import route has no dialog factory.");
        }

        LinuxRepositoryRoute route = new(
            LinuxRepositoryRouteKind.MainWindow,
            mainWindow.ViewModel.RepoPath,
            null);
        LinuxImportDialog dialog = importDialogFactory.Create(route);
        await dialog.OpenRepositoryWithSourcesAsync(route.RepoPath, sourcePaths, cancellationToken)
            .ConfigureAwait(false);
        importDialog = dialog;
    }

    public async Task<bool> OpenMissingFileRecoveryAsync(CancellationToken cancellationToken = default)
    {
        if (mainWindow?.ViewModel.SelectedMissingFileRecoveryRoute is not { } route)
        {
            return false;
        }

        if (missingFileRecoveryViewFactory is null)
        {
            throw new InvalidOperationException("Linux missing-file recovery route has no view factory.");
        }

        MissingFileRecoveryView view = missingFileRecoveryViewFactory.Create(route);
        await view.OpenRouteAsync(route, cancellationToken).ConfigureAwait(false);
        missingFileRecoveryView = view;
        return true;
    }

    public async Task ContinueFromLocalFolderNoticeAsync(
        CancellationToken cancellationToken = default)
    {
        if (localFolderNoticeView is null)
        {
            return;
        }

        await localFolderNoticeView.ContinueAsync(cancellationToken).ConfigureAwait(false);
        await ConsumeRouteAsync(cancellationToken).ConfigureAwait(false);
    }

    public async Task ContinueFromRepositoryInitConfirmAsync(
        CancellationToken cancellationToken = default)
    {
        if (repositoryInitConfirmView is null)
        {
            return;
        }

        await repositoryInitConfirmView
            .CreateRepositoryAsync(cancellationToken)
            .ConfigureAwait(false);
        await ConsumeRouteAsync(cancellationToken).ConfigureAwait(false);
    }

    public async Task ContinueFromRepositoryAdoptConfirmAsync(
        CancellationToken cancellationToken = default)
    {
        if (repositoryAdoptConfirmView is null)
        {
            return;
        }

        await repositoryAdoptConfirmView
            .UseThisFolderAsync(cancellationToken)
            .ConfigureAwait(false);
        await ConsumeRouteAsync(cancellationToken).ConfigureAwait(false);
    }

    public async Task ConsumeRouteAsync(CancellationToken cancellationToken = default)
    {
        LinuxRepositoryRoute route = ActiveRoute();
        if (route.Kind == LinuxRepositoryRouteKind.LocalFolderNotice)
        {
            await ShowLocalFolderNoticeAsync(route, cancellationToken).ConfigureAwait(false);
            return;
        }

        if (route.Kind == LinuxRepositoryRouteKind.RepositoryInitConfirm)
        {
            await ShowRepositoryInitConfirmAsync(route, cancellationToken).ConfigureAwait(false);
            return;
        }

        if (route.Kind == LinuxRepositoryRouteKind.RepositoryAdoptConfirm)
        {
            await ShowRepositoryAdoptConfirmAsync(route, cancellationToken).ConfigureAwait(false);
            return;
        }

        if (route.Kind == LinuxRepositoryRouteKind.ChooseRepository)
        {
            localFolderNoticeView = null;
            repositoryInitConfirmView = null;
            repositoryAdoptConfirmView = null;
            watcherStatusView = null;
            importDialog = null;
            missingFileRecoveryView = null;
            platformDifferencesView = null;
            repositorySettingsView = null;
            return;
        }

        if (route.Kind != LinuxRepositoryRouteKind.MainWindow)
        {
            return;
        }

        await ShowMainWindowAsync(route, cancellationToken).ConfigureAwait(false);
    }

    private async Task ShowLocalFolderNoticeAsync(
        LinuxRepositoryRoute route,
        CancellationToken cancellationToken)
    {
        if (localFolderNoticeFactory is null)
        {
            throw new InvalidOperationException("Linux local folder notice route has no view factory.");
        }

        LocalFolderNoticeView noticeView = localFolderNoticeFactory.Create(route);
        await noticeView.LoadAsync(route, cancellationToken).ConfigureAwait(false);
        localFolderNoticeView = noticeView;
        repositoryInitConfirmView = null;
        repositoryAdoptConfirmView = null;
        chooseRepositoryView.ViewModel.ResetRoute();
    }

    private async Task ShowRepositoryInitConfirmAsync(
        LinuxRepositoryRoute route,
        CancellationToken cancellationToken)
    {
        if (repositoryInitConfirmFactory is null)
        {
            throw new InvalidOperationException("Linux repository init confirm route has no view factory.");
        }

        RepositoryInitConfirmView initConfirmView = repositoryInitConfirmFactory.Create(route);
        await initConfirmView.OpenRouteAsync(route, cancellationToken).ConfigureAwait(false);
        repositoryInitConfirmView = initConfirmView;
        localFolderNoticeView = null;
        repositoryAdoptConfirmView = null;
        chooseRepositoryView.ViewModel.ResetRoute();
    }

    private async Task ShowRepositoryAdoptConfirmAsync(
        LinuxRepositoryRoute route,
        CancellationToken cancellationToken)
    {
        if (repositoryAdoptConfirmFactory is null)
        {
            throw new InvalidOperationException("Linux repository adopt confirm route has no view factory.");
        }

        RepositoryAdoptConfirmView adoptConfirmView = repositoryAdoptConfirmFactory.Create(route);
        await adoptConfirmView.OpenRouteAsync(route, cancellationToken).ConfigureAwait(false);
        repositoryAdoptConfirmView = adoptConfirmView;
        repositoryInitConfirmView = null;
        localFolderNoticeView = null;
        chooseRepositoryView.ViewModel.ResetRoute();
    }

    private async Task ShowMainWindowAsync(
        LinuxRepositoryRoute route,
        CancellationToken cancellationToken)
    {
        LinuxMainWindow window = mainWindowFactory.Create(route);
        await window.OpenRepositoryAsync(route, cancellationToken).ConfigureAwait(false);
        mainWindow = window;
        watcherStatusView = null;
        localFolderNoticeView = null;
        repositoryInitConfirmView = null;
        repositoryAdoptConfirmView = null;
        importDialog = null;
        missingFileRecoveryView = null;
        platformDifferencesView = null;
        repositorySettingsView = null;
        rescanConfirmView = null;
        chooseRepositoryView.ViewModel.ResetRoute();
    }

    private void ReturnToChooseRepository()
    {
        localFolderNoticeView = null;
        repositoryInitConfirmView = null;
        repositoryAdoptConfirmView = null;
        platformDifferencesView = null;
        repositorySettingsView = null;
        chooseRepositoryView.ViewModel.ResetRoute();
    }

    private void WatcherStatusView_OpenRescanConfirmRequested(LinuxRescanConfirmRequest request)
    {
        if (rescanConfirmViewFactory is null)
        {
            throw new InvalidOperationException("Linux rescan confirmation route has no view factory.");
        }

        LinuxRescanConfirmView view = rescanConfirmViewFactory.Create(request);
        view.OpenRequest(request);
        rescanConfirmView = view;
    }

    private LinuxRepositoryRoute ActiveRoute()
    {
        LinuxRepositoryRoute noticeRoute = localFolderNoticeView?.ViewModel.Route
            ?? LinuxRepositoryRoute.None;
        if (noticeRoute.Kind != LinuxRepositoryRouteKind.None)
        {
            return noticeRoute;
        }

        LinuxRepositoryRoute initConfirmRoute = repositoryInitConfirmView?.ViewModel.CompletedRoute
            ?? LinuxRepositoryRoute.None;
        if (initConfirmRoute.Kind != LinuxRepositoryRouteKind.None)
        {
            return initConfirmRoute;
        }

        LinuxRepositoryRoute adoptConfirmRoute = repositoryAdoptConfirmView?.ViewModel.CompletedRoute
            ?? LinuxRepositoryRoute.None;
        return adoptConfirmRoute.Kind == LinuxRepositoryRouteKind.None
            ? chooseRepositoryView.ViewModel.Route
            : adoptConfirmRoute;
    }

    public void Dispose()
    {
        if (disposed)
        {
            return;
        }

        if (mainWindowFactory is IDisposable disposableFactory)
        {
            disposableFactory.Dispose();
        }

        ownedResources?.Dispose();
        disposed = true;
    }
}
