using AreaMatrix.Linux.Core;
using AreaMatrix.Linux.Features.Onboarding;

namespace AreaMatrix.Linux.Features.Library;

public interface ILinuxMainWindowFactory
{
    LinuxMainWindow Create(LinuxRepositoryRoute route);
}

public sealed class LinuxDesktopShell : IDisposable
{
    private readonly LinuxChooseRepositoryView chooseRepositoryView;
    private readonly ILinuxMainWindowFactory mainWindowFactory;
    private readonly IDisposable? ownedResources;
    private LinuxMainWindow? mainWindow;
    private bool disposed;

    public LinuxDesktopShell(
        LinuxChooseRepositoryView chooseRepositoryView,
        ILinuxMainWindowFactory mainWindowFactory,
        IDisposable? ownedResources = null)
    {
        this.chooseRepositoryView = chooseRepositoryView;
        this.mainWindowFactory = mainWindowFactory;
        this.ownedResources = ownedResources;
    }

    public LinuxChooseRepositoryView ChooseRepositoryView => chooseRepositoryView;

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
            nativeCoreClient);
    }

    public async Task ContinueFromRepositorySelectionAsync(
        CancellationToken cancellationToken = default)
    {
        await chooseRepositoryView.ContinueAsync(cancellationToken).ConfigureAwait(false);
        await ConsumeRouteAsync(cancellationToken).ConfigureAwait(false);
    }

    public async Task ConsumeRouteAsync(CancellationToken cancellationToken = default)
    {
        LinuxRepositoryRoute route = chooseRepositoryView.ViewModel.Route;
        if (route.Kind != LinuxRepositoryRouteKind.MainWindow)
        {
            return;
        }

        LinuxMainWindow window = mainWindowFactory.Create(route);
        await window.OpenRepositoryAsync(route, cancellationToken).ConfigureAwait(false);
        mainWindow = window;
        chooseRepositoryView.ViewModel.ResetRoute();
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
