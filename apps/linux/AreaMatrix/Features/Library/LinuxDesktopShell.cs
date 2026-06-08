using AreaMatrix.Linux.Core;
using AreaMatrix.Linux.Features.Onboarding;

namespace AreaMatrix.Linux.Features.Library;

public interface ILinuxMainWindowFactory
{
    LinuxMainWindow Create(LinuxRepositoryRoute route);
}

public interface ILinuxLocalFolderNoticeFactory
{
    LocalFolderNoticeView Create(LinuxRepositoryRoute route);
}

public sealed class LinuxDesktopShell : IDisposable
{
    private readonly LinuxChooseRepositoryView chooseRepositoryView;
    private readonly ILinuxLocalFolderNoticeFactory? localFolderNoticeFactory;
    private readonly ILinuxMainWindowFactory mainWindowFactory;
    private readonly IDisposable? ownedResources;
    private LocalFolderNoticeView? localFolderNoticeView;
    private LinuxMainWindow? mainWindow;
    private bool disposed;

    public LinuxDesktopShell(
        LinuxChooseRepositoryView chooseRepositoryView,
        ILinuxMainWindowFactory mainWindowFactory,
        ILinuxLocalFolderNoticeFactory? localFolderNoticeFactory = null,
        IDisposable? ownedResources = null)
    {
        this.chooseRepositoryView = chooseRepositoryView;
        this.mainWindowFactory = mainWindowFactory;
        this.localFolderNoticeFactory = localFolderNoticeFactory;
        this.ownedResources = ownedResources;
    }

    public LinuxChooseRepositoryView ChooseRepositoryView => chooseRepositoryView;

    public LocalFolderNoticeView? LocalFolderNoticeView => localFolderNoticeView;

    public LinuxMainWindow? MainWindow => mainWindow;

    public static LinuxDesktopShell CreateDefault(string locale = "en-US")
    {
        AreaMatrixNativeCoreClient nativeCoreClient = new();
        LinuxRepositoryCoreBridge repositoryBridge = new(nativeCoreClient);
        DesktopMainQueryCoreBridge queryBridge = new(nativeCoreClient);
        LinuxChooseRepositoryView chooseRepositoryView = new(
            new LinuxChooseRepositoryViewModel(repositoryBridge),
            new LinuxSystemFolderPickerAdapter());
        return new LinuxDesktopShell(
            chooseRepositoryView,
            new LinuxMainWindowFactory(queryBridge, locale),
            new LinuxLocalFolderNoticeFactory(repositoryBridge),
            nativeCoreClient);
    }

    public async Task ContinueFromRepositorySelectionAsync(
        CancellationToken cancellationToken = default)
    {
        await chooseRepositoryView.ContinueAsync(cancellationToken).ConfigureAwait(false);
        await ConsumeRouteAsync(cancellationToken).ConfigureAwait(false);
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
            return;
        }

        if (route.Kind != LinuxRepositoryRouteKind.MainWindow)
        {
            return;
        }

        LinuxMainWindow window = mainWindowFactory.Create(route);
        await window.OpenRepositoryAsync(route, cancellationToken).ConfigureAwait(false);
        mainWindow = window;
        localFolderNoticeView = null;
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
    private readonly string locale;

    public LinuxMainWindowFactory(IDesktopMainQueryCoreBridge coreBridge, string locale = "en-US")
    {
        this.coreBridge = coreBridge;
        this.locale = locale;
    }

    public LinuxMainWindow Create(LinuxRepositoryRoute route)
    {
        return new LinuxMainWindow(new LinuxMainWindowViewModel(coreBridge, locale));
    }
}
