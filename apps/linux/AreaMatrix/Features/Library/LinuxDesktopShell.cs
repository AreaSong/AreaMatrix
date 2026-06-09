using AreaMatrix.Linux.Core;
using AreaMatrix.Linux.Features.Conflicts;
using AreaMatrix.Linux.Features.Help;
using AreaMatrix.Linux.Features.Import;
using AreaMatrix.Linux.Features.Onboarding;
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

public interface ILinuxImportDialogFactory
{
    LinuxImportDialog Create(LinuxRepositoryRoute route);
}

public interface ILinuxPlatformDifferencesViewFactory
{
    PlatformDifferencesView Create(string? repositoryPath = null);
}

public interface ILinuxLocalFolderNoticeFactory
{
    LocalFolderNoticeView Create(LinuxRepositoryRoute route);
}

public sealed class LinuxDesktopShell : IDisposable
{
    private readonly LinuxChooseRepositoryView chooseRepositoryView;
    private readonly ILinuxLocalFolderNoticeFactory? localFolderNoticeFactory;
    private readonly ILinuxImportDialogFactory? importDialogFactory;
    private readonly ILinuxMainWindowFactory mainWindowFactory;
    private readonly ILinuxPlatformDifferencesViewFactory? platformDifferencesViewFactory;
    private readonly ILinuxWatcherStatusViewFactory? watcherStatusViewFactory;
    private readonly IDisposable? ownedResources;
    private LocalFolderNoticeView? localFolderNoticeView;
    private LinuxImportDialog? importDialog;
    private LinuxMainWindow? mainWindow;
    private PlatformDifferencesView? platformDifferencesView;
    private LinuxWatcherStatusView? watcherStatusView;
    private bool disposed;

    public LinuxDesktopShell(
        LinuxChooseRepositoryView chooseRepositoryView,
        ILinuxMainWindowFactory mainWindowFactory,
        ILinuxLocalFolderNoticeFactory? localFolderNoticeFactory = null,
        ILinuxImportDialogFactory? importDialogFactory = null,
        ILinuxPlatformDifferencesViewFactory? platformDifferencesViewFactory = null,
        ILinuxWatcherStatusViewFactory? watcherStatusViewFactory = null,
        IDisposable? ownedResources = null)
    {
        this.chooseRepositoryView = chooseRepositoryView;
        this.mainWindowFactory = mainWindowFactory;
        this.localFolderNoticeFactory = localFolderNoticeFactory;
        this.importDialogFactory = importDialogFactory;
        this.platformDifferencesViewFactory = platformDifferencesViewFactory;
        this.watcherStatusViewFactory = watcherStatusViewFactory;
        this.ownedResources = ownedResources;
    }

    public LinuxChooseRepositoryView ChooseRepositoryView => chooseRepositoryView;

    public LocalFolderNoticeView? LocalFolderNoticeView => localFolderNoticeView;

    public LinuxImportDialog? ImportDialog => importDialog;

    public PlatformDifferencesView? PlatformDifferencesView => platformDifferencesView;

    public LinuxMainWindow? MainWindow => mainWindow;

    public LinuxWatcherStatusView? WatcherStatusView => watcherStatusView;

    public static LinuxDesktopShell CreateDefault(string locale = "en-US")
    {
        AreaMatrixNativeCoreClient nativeCoreClient = new();
        LinuxRepositoryCoreBridge repositoryBridge = new(nativeCoreClient);
        DesktopMainQueryCoreBridge queryBridge = new(nativeCoreClient);
        SyncConflictEntryCoreBridge syncConflictBridge = new(nativeCoreClient);
        DesktopImportCoreBridge importBridge = new(nativeCoreClient, new LinuxImportFileProbe());
        LinuxWatcherStatusCoreBridge watcherBridge = new(nativeCoreClient);
        LinuxWatcherDiagnostics watcherDiagnostics = new();
        LinuxChooseRepositoryView chooseRepositoryView = new(
            new LinuxChooseRepositoryViewModel(repositoryBridge),
            new LinuxSystemFolderPickerAdapter());
        return new LinuxDesktopShell(
            chooseRepositoryView,
            new LinuxMainWindowFactory(queryBridge, locale, syncConflictBridge),
            new LinuxLocalFolderNoticeFactory(repositoryBridge),
            new LinuxImportDialogFactory(importBridge),
            new LinuxPlatformDifferencesViewFactory(new PlatformDifferencesCoreBridge(nativeCoreClient)),
            new LinuxWatcherStatusViewFactory(watcherBridge, watcherDiagnostics),
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

        PlatformDifferencesView view = platformDifferencesViewFactory.Create(mainWindow?.ViewModel.RepoPath);
        await view.OpenAsync(cancellationToken).ConfigureAwait(false);
        platformDifferencesView = view;
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

    public async Task ConsumeRouteAsync(CancellationToken cancellationToken = default)
    {
        LinuxRepositoryRoute route = ActiveRoute();
        if (route.Kind == LinuxRepositoryRouteKind.LocalFolderNotice)
        {
            if (localFolderNoticeFactory is null)
            {
                throw new InvalidOperationException("Linux local folder notice route has no view factory.");
            }

            LocalFolderNoticeView noticeView = localFolderNoticeFactory.Create(route);
            await noticeView.LoadAsync(route, cancellationToken).ConfigureAwait(false);
            localFolderNoticeView = noticeView;
            chooseRepositoryView.ViewModel.ResetRoute();
            return;
        }

        if (route.Kind == LinuxRepositoryRouteKind.ChooseRepository)
        {
            localFolderNoticeView = null;
            watcherStatusView = null;
            importDialog = null;
            platformDifferencesView = null;
            return;
        }

        if (route.Kind != LinuxRepositoryRouteKind.MainWindow)
        {
            return;
        }

        LinuxMainWindow window = mainWindowFactory.Create(route);
        await window.OpenRepositoryAsync(route, cancellationToken).ConfigureAwait(false);
        mainWindow = window;
        watcherStatusView = null;
        localFolderNoticeView = null;
        importDialog = null;
        platformDifferencesView = null;
        chooseRepositoryView.ViewModel.ResetRoute();
    }

    private LinuxRepositoryRoute ActiveRoute()
    {
        LinuxRepositoryRoute noticeRoute = localFolderNoticeView?.ViewModel.Route
            ?? LinuxRepositoryRoute.None;
        return noticeRoute.Kind == LinuxRepositoryRouteKind.None
            ? chooseRepositoryView.ViewModel.Route
            : noticeRoute;
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

public sealed class LinuxLocalFolderNoticeFactory : ILinuxLocalFolderNoticeFactory
{
    private readonly ILinuxRepositoryCoreBridge coreBridge;

    public LinuxLocalFolderNoticeFactory(ILinuxRepositoryCoreBridge coreBridge)
    {
        this.coreBridge = coreBridge;
    }

    public LocalFolderNoticeView Create(LinuxRepositoryRoute route)
    {
        return new LocalFolderNoticeView(new LocalFolderNoticeViewModel(coreBridge));
    }
}

public sealed class LinuxMainWindowFactory : ILinuxMainWindowFactory
{
    private readonly IDesktopMainQueryCoreBridge coreBridge;
    private readonly ISyncConflictEntryCoreBridge? syncConflictBridge;
    private readonly string locale;

    public LinuxMainWindowFactory(
        IDesktopMainQueryCoreBridge coreBridge,
        string locale = "en-US",
        ISyncConflictEntryCoreBridge? syncConflictBridge = null)
    {
        this.coreBridge = coreBridge;
        this.syncConflictBridge = syncConflictBridge;
        this.locale = locale;
    }

    public LinuxMainWindow Create(LinuxRepositoryRoute route)
    {
        return new LinuxMainWindow(new LinuxMainWindowViewModel(coreBridge, syncConflictBridge, locale));
    }
}

public sealed class LinuxImportDialogFactory : ILinuxImportDialogFactory
{
    private readonly IDesktopImportCoreBridge coreBridge;

    public LinuxImportDialogFactory(IDesktopImportCoreBridge coreBridge)
    {
        this.coreBridge = coreBridge;
    }

    public LinuxImportDialog Create(LinuxRepositoryRoute route)
    {
        LinuxImportFileProbe fileProbe = new();
        return new LinuxImportDialog(new LinuxImportViewModel(coreBridge), fileProbe);
    }
}

public sealed class LinuxWatcherStatusViewFactory : ILinuxWatcherStatusViewFactory
{
    private readonly ILinuxWatcherStatusCoreBridge coreBridge;
    private readonly ILinuxWatcherDiagnostics diagnostics;

    public LinuxWatcherStatusViewFactory(
        ILinuxWatcherStatusCoreBridge coreBridge,
        ILinuxWatcherDiagnostics diagnostics)
    {
        this.coreBridge = coreBridge;
        this.diagnostics = diagnostics;
    }

    public LinuxWatcherStatusView Create(LinuxRepositoryRoute route)
    {
        return new LinuxWatcherStatusView(new LinuxWatcherStatusViewModel(coreBridge, diagnostics));
    }
}

public sealed class LinuxPlatformDifferencesViewFactory : ILinuxPlatformDifferencesViewFactory
{
    private readonly IPlatformDifferencesCoreBridge coreBridge;

    public LinuxPlatformDifferencesViewFactory(IPlatformDifferencesCoreBridge coreBridge)
    {
        this.coreBridge = coreBridge;
    }

    public PlatformDifferencesView Create(string? repositoryPath = null)
    {
        return new PlatformDifferencesView(new PlatformDifferencesViewModel(
            coreBridge,
            repositoryPath: repositoryPath));
    }
}
