using AreaMatrix.Core;
using AreaMatrix.Features.Conflicts;
using AreaMatrix.Features.Help;
using AreaMatrix.Features.Import;
using AreaMatrix.Features.Library;
using AreaMatrix.Features.Onboarding;
using AreaMatrix.Features.Recovery;
using AreaMatrix.Features.Settings;
using Microsoft.UI.Xaml;
using WinRT.Interop;
using System.ComponentModel;

namespace AreaMatrix;

public sealed partial class MainWindow : Window
{
    private readonly LazyAreaMatrixWindowsCoreClient coreClient = new();
    private readonly IWindowsRepositoryCoreBridge repositoryBridge;
    private readonly WindowsWatcherDiagnostics watcherDiagnostics = new();
    private bool oneDriveNoticeOpenedFromMainWindow;

    public MainWindow()
    {
        InitializeComponent();
        Title = "AreaMatrix";
        repositoryBridge = new WindowsRepositoryCoreBridge(coreClient);
        ChooseRepositoryPage.ViewModel = new ChooseRepositoryViewModel(repositoryBridge);
        ChooseRepositoryPage.ViewModel.PropertyChanged += ChooseRepositoryViewModel_PropertyChanged;
        RepositoryInitConfirmPage.ViewModel = new RepositoryInitConfirmViewModel(repositoryBridge);
        RepositoryInitConfirmPage.CancelRequested += RepositoryInitConfirmPage_CloseRequested;
        RepositoryInitConfirmPage.ChooseAnotherFolderRequested += RepositoryInitConfirmPage_CloseRequested;
        RepositoryInitConfirmPage.RepositoryOpenedRequested += RepositoryInitConfirmPage_RepositoryOpenedRequested;
        RepositoryAdoptConfirmPage.ViewModel = new RepositoryAdoptConfirmViewModel(repositoryBridge);
        RepositoryAdoptConfirmPage.CancelRequested += RepositoryAdoptConfirmPage_CloseRequested;
        RepositoryAdoptConfirmPage.ChooseAnotherFolderRequested += RepositoryAdoptConfirmPage_CloseRequested;
        RepositoryAdoptConfirmPage.RepositoryOpenedRequested += RepositoryAdoptConfirmPage_RepositoryOpenedRequested;
        OneDriveNoticePage.ViewModel = new OneDriveNoticeViewModel(repositoryBridge);
        OneDriveNoticePage.ChooseLocalFolderRequested += OneDriveNoticePage_ChooseLocalFolderRequested;
        OneDriveNoticePage.CloseRequested += OneDriveNoticePage_CloseRequested;
        OneDriveNoticePage.ContinueWithOneDriveRequested += OneDriveNoticePage_ContinueWithOneDriveRequested;
        OneDriveNoticePage.OpenWatcherStatusRequested += OneDriveNoticePage_OpenWatcherStatusRequested;
        WindowsMainWindowPage.ViewModel = new WindowsMainWindowViewModel(
            new DesktopMainQueryCoreBridge(coreClient),
            new SyncConflictEntryCoreBridge(coreClient));
        WindowsMainWindowPage.OpenSyncConflictReviewRequested += WindowsMainWindowPage_OpenSyncConflictReviewRequested;
        WindowsMainWindowPage.OpenOneDriveStatusRequested += WindowsMainWindowPage_OpenOneDriveStatusRequested;
        WindowsMainWindowPage.OpenWatcherStatusRequested += WindowsMainWindowPage_OpenWatcherStatusRequested;
        WindowsMainWindowPage.OpenImportRequested += WindowsMainWindowPage_OpenImportRequested;
        WindowsMainWindowPage.OpenImportDroppedSourcesRequested += WindowsMainWindowPage_OpenImportDroppedSourcesRequested;
        WindowsMainWindowPage.OpenPlatformDifferencesRequested += WindowsMainWindowPage_OpenPlatformDifferencesRequested;
        WindowsMainWindowPage.OpenMissingFileRecoveryRequested += WindowsMainWindowPage_OpenMissingFileRecoveryRequested;
        WindowsImportPage.ViewModel = new WindowsImportViewModel(
            new DesktopImportCoreBridge(coreClient, new WindowsImportFileProbe()));
        WindowsImportPage.ParentWindowHandle = WindowNative.GetWindowHandle(this);
        WindowsImportPage.CloseRequested += WindowsImportPage_CloseRequested;
        MissingFileRecoveryPage.ViewModel = new MissingFileRecoveryViewModel(
            new MissingFileRecoveryCoreBridge(coreClient));
        MissingFileRecoveryPage.ParentWindowHandle = WindowNative.GetWindowHandle(this);
        MissingFileRecoveryPage.CloseRequested += MissingFileRecoveryPage_CloseRequested;
        WatcherStatusPage.ViewModel = new WatcherStatusViewModel(
            new WatcherStatusCoreBridge(coreClient),
            watcherDiagnostics);
        WatcherStatusPage.CloseRequested += WatcherStatusPage_CloseRequested;
        WatcherStatusPage.OpenRescanConfirmRequested += WatcherStatusPage_OpenRescanConfirmRequested;
        RescanConfirmPage.ViewModel = new RescanConfirmViewModel(new WatcherStatusCoreBridge(coreClient));
        PlatformDifferencesPage.ViewModel = new PlatformDifferencesViewModel(
            new PlatformDifferencesCoreBridge(coreClient));
        PlatformDifferencesPage.CloseRequested += PlatformDifferencesPage_CloseRequested;
        PlatformDifferencesPage.OpenRepositorySettingsRequested += PlatformDifferencesPage_OpenRepositorySettingsRequested;
        RepositorySettingsPage.ReconnectRepositoryRequested += RepositorySettingsPage_ChangeRepositoryRequested;
        RepositorySettingsPage.ChooseAnotherFolderRequested += RepositorySettingsPage_ChangeRepositoryRequested;
        RepositorySettingsPage.PlatformCapabilitiesRequested += RepositorySettingsPage_PlatformCapabilitiesRequested;
        RepositorySettingsPage.ExportDiagnosticsRequested += RepositorySettingsPage_ExportDiagnosticsRequested;
        RescanConfirmPage.CloseRequested += RescanConfirmPage_CloseRequested;
        Closed += MainWindow_Closed;
    }

    private async void ChooseRepositoryViewModel_PropertyChanged(
        object? sender,
        PropertyChangedEventArgs e)
    {
        if (e.PropertyName != nameof(ChooseRepositoryViewModel.Route)
            || ChooseRepositoryPage.ViewModel?.Route is not { } route)
        {
            return;
        }

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
            await OneDriveNoticePage.OpenRouteAsync(route);
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
            await RepositoryInitConfirmPage.OpenRouteAsync(route);
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
            await RepositoryAdoptConfirmPage.OpenRouteAsync(route);
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
        await WindowsMainWindowPage.OpenRepositoryAsync(route);
    }

    private void OneDriveNoticePage_ChooseLocalFolderRequested()
    {
        oneDriveNoticeOpenedFromMainWindow = false;
        ChooseRepositoryPage.ViewModel?.ResetRoute();
        OneDriveNoticePage.Visibility = Visibility.Collapsed;
        RepositoryInitConfirmPage.Visibility = Visibility.Collapsed;
        RepositoryAdoptConfirmPage.Visibility = Visibility.Collapsed;
        WindowsMainWindowPage.Visibility = Visibility.Collapsed;
        WindowsImportPage.Visibility = Visibility.Collapsed;
        WatcherStatusPage.Visibility = Visibility.Collapsed;
        RescanConfirmPage.Visibility = Visibility.Collapsed;
        PlatformDifferencesPage.Visibility = Visibility.Collapsed;
        ChooseRepositoryPage.Visibility = Visibility.Visible;
    }

    private void OneDriveNoticePage_CloseRequested()
    {
        if (!oneDriveNoticeOpenedFromMainWindow)
        {
            OneDriveNoticePage_ChooseLocalFolderRequested();
            return;
        }

        oneDriveNoticeOpenedFromMainWindow = false;
        OneDriveNoticePage.Visibility = Visibility.Collapsed;
        RepositoryInitConfirmPage.Visibility = Visibility.Collapsed;
        RepositoryAdoptConfirmPage.Visibility = Visibility.Collapsed;
        WatcherStatusPage.Visibility = Visibility.Collapsed;
        WindowsImportPage.Visibility = Visibility.Collapsed;
        RescanConfirmPage.Visibility = Visibility.Collapsed;
        PlatformDifferencesPage.Visibility = Visibility.Collapsed;
        ChooseRepositoryPage.Visibility = Visibility.Collapsed;
        WindowsMainWindowPage.Visibility = Visibility.Visible;
    }

    private async Task OneDriveNoticePage_ContinueWithOneDriveRequested(WindowsCloudStorageState? state)
    {
        if (ChooseRepositoryPage.ViewModel is not { } viewModel)
        {
            return;
        }

        await viewModel.ContinueAfterOneDriveNoticeAsync(state);
        if (viewModel.Route.Kind == WindowsRepositoryRouteKind.RepositoryInitConfirm)
        {
            return;
        }

        if (viewModel.Route.Kind == WindowsRepositoryRouteKind.RepositoryAdoptConfirm)
        {
            return;
        }
    }

    private async void WindowsMainWindowPage_OpenOneDriveStatusRequested(WindowsRepositoryRoute route)
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
        await OneDriveNoticePage.OpenRouteAsync(route);
    }

    private async void WindowsMainWindowPage_OpenWatcherStatusRequested(WindowsRepositoryRoute route)
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
        await WatcherStatusPage.OpenRouteAsync(route);
    }

    private void WindowsMainWindowPage_OpenImportRequested(WindowsRepositoryRoute route)
    {
        ShowImportPage();
        WindowsImportPage.OpenRepository(route.RepoPath);
    }

    private void WindowsMainWindowPage_OpenSyncConflictReviewRequested(SyncConflictEntryReviewRoute route)
    {
        WindowsMainWindowPage.Visibility = Visibility.Visible;
        WindowsMainWindowPage.ShowSyncConflictReviewRoute(route);
    }

    private async void WindowsMainWindowPage_OpenImportDroppedSourcesRequested(
        WindowsRepositoryRoute route,
        IReadOnlyList<string> sourcePaths)
    {
        ShowImportPage();
        await WindowsImportPage.OpenRepositoryWithSourcesAsync(route.RepoPath, sourcePaths);
    }

    private async void WindowsMainWindowPage_OpenMissingFileRecoveryRequested(MissingFileRecoveryRoute route)
    {
        ShowMissingFileRecoveryPage();
        await MissingFileRecoveryPage.OpenRouteAsync(route);
    }

    private async void WindowsImportPage_CloseRequested(WindowsImportCloseRequest request)
    {
        WindowsImportPage.Visibility = Visibility.Collapsed;
        OneDriveNoticePage.Visibility = Visibility.Collapsed;
        ChooseRepositoryPage.Visibility = Visibility.Collapsed;
        RepositoryInitConfirmPage.Visibility = Visibility.Collapsed;
        RepositoryAdoptConfirmPage.Visibility = Visibility.Collapsed;
        WatcherStatusPage.Visibility = Visibility.Collapsed;
        RescanConfirmPage.Visibility = Visibility.Collapsed;
        PlatformDifferencesPage.Visibility = Visibility.Collapsed;
        RepositorySettingsPage.Visibility = Visibility.Collapsed;
        WindowsMainWindowPage.Visibility = Visibility.Visible;
        if (request.ImportedFileIds.FirstOrDefault() is > 0 and long selectedFileId)
        {
            await WindowsMainWindowPage.RefreshAndSelectFileAsync(selectedFileId);
        }
    }

    private async void MissingFileRecoveryPage_CloseRequested(MissingFileRecoveryReport? report)
    {
        MissingFileRecoveryPage.Visibility = Visibility.Collapsed;
        OneDriveNoticePage.Visibility = Visibility.Collapsed;
        ChooseRepositoryPage.Visibility = Visibility.Collapsed;
        RepositoryInitConfirmPage.Visibility = Visibility.Collapsed;
        RepositoryAdoptConfirmPage.Visibility = Visibility.Collapsed;
        WindowsImportPage.Visibility = Visibility.Collapsed;
        WatcherStatusPage.Visibility = Visibility.Collapsed;
        RescanConfirmPage.Visibility = Visibility.Collapsed;
        PlatformDifferencesPage.Visibility = Visibility.Collapsed;
        RepositorySettingsPage.Visibility = Visibility.Collapsed;
        WindowsMainWindowPage.Visibility = Visibility.Visible;
        if (report?.FileId is > 0 and long fileId)
        {
            await WindowsMainWindowPage.RefreshAndSelectFileAsync(fileId);
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
        await WatcherStatusPage.OpenRouteAsync(route);
    }

    private void WatcherStatusPage_CloseRequested()
    {
        WatcherStatusPage.Visibility = Visibility.Collapsed;
        OneDriveNoticePage.Visibility = Visibility.Collapsed;
        RepositoryInitConfirmPage.Visibility = Visibility.Collapsed;
        RepositoryAdoptConfirmPage.Visibility = Visibility.Collapsed;
        RescanConfirmPage.Visibility = Visibility.Collapsed;
        WindowsImportPage.Visibility = Visibility.Collapsed;
        PlatformDifferencesPage.Visibility = Visibility.Collapsed;
        RepositorySettingsPage.Visibility = Visibility.Collapsed;
        ChooseRepositoryPage.Visibility = Visibility.Collapsed;
        WindowsMainWindowPage.Visibility = Visibility.Visible;
    }

    private void WatcherStatusPage_OpenRescanConfirmRequested(RescanConfirmRequest request)
    {
        OneDriveNoticePage.Visibility = Visibility.Collapsed;
        ChooseRepositoryPage.Visibility = Visibility.Collapsed;
        RepositoryInitConfirmPage.Visibility = Visibility.Collapsed;
        RepositoryAdoptConfirmPage.Visibility = Visibility.Collapsed;
        WindowsMainWindowPage.Visibility = Visibility.Collapsed;
        WindowsImportPage.Visibility = Visibility.Collapsed;
        WatcherStatusPage.Visibility = Visibility.Collapsed;
        PlatformDifferencesPage.Visibility = Visibility.Collapsed;
        RepositorySettingsPage.Visibility = Visibility.Collapsed;
        RescanConfirmPage.Visibility = Visibility.Visible;
        RescanConfirmPage.OpenRequest(request);
    }

    private async void WindowsMainWindowPage_OpenPlatformDifferencesRequested()
    {
        PlatformDifferencesPage.ViewModel = new PlatformDifferencesViewModel(
            new PlatformDifferencesCoreBridge(coreClient),
            repositoryPath: WindowsMainWindowPage.ViewModel?.RepoPath);
        ShowPlatformDifferencesPage();
        await PlatformDifferencesPage.OpenAsync();
    }

    private async void PlatformDifferencesPage_OpenRepositorySettingsRequested()
    {
        await ShowRepositorySettingsPageAsync();
    }

    private void PlatformDifferencesPage_CloseRequested()
    {
        PlatformDifferencesPage.Visibility = Visibility.Collapsed;
        OneDriveNoticePage.Visibility = Visibility.Collapsed;
        ChooseRepositoryPage.Visibility = Visibility.Collapsed;
        WindowsImportPage.Visibility = Visibility.Collapsed;
        WatcherStatusPage.Visibility = Visibility.Collapsed;
        RescanConfirmPage.Visibility = Visibility.Collapsed;
        RepositoryInitConfirmPage.Visibility = Visibility.Collapsed;
        RepositoryAdoptConfirmPage.Visibility = Visibility.Collapsed;
        RepositorySettingsPage.Visibility = Visibility.Collapsed;
        WindowsMainWindowPage.Visibility = Visibility.Visible;
    }

    private void RepositorySettingsPage_ChangeRepositoryRequested()
    {
        PlatformDifferencesPage.Visibility = Visibility.Collapsed;
        RepositorySettingsPage.Visibility = Visibility.Collapsed;
        WindowsMainWindowPage.Visibility = Visibility.Collapsed;
        WindowsImportPage.Visibility = Visibility.Collapsed;
        WatcherStatusPage.Visibility = Visibility.Collapsed;
        RescanConfirmPage.Visibility = Visibility.Collapsed;
        RepositoryInitConfirmPage.Visibility = Visibility.Collapsed;
        RepositoryAdoptConfirmPage.Visibility = Visibility.Collapsed;
        ChooseRepositoryPage.ViewModel?.ResetRoute();
        ChooseRepositoryPage.Visibility = Visibility.Visible;
    }

    private async void RepositorySettingsPage_PlatformCapabilitiesRequested()
    {
        PlatformDifferencesPage.ViewModel = new PlatformDifferencesViewModel(
            new PlatformDifferencesCoreBridge(coreClient),
            repositoryPath: RepositorySettingsPage.ViewModel?.RepositoryPath);
        ShowPlatformDifferencesPage();
        await PlatformDifferencesPage.OpenAsync();
    }

    private async void RepositorySettingsPage_ExportDiagnosticsRequested()
    {
        await RepositorySettingsPage.ExportDiagnosticsAsync();
    }

    private void RescanConfirmPage_CloseRequested()
    {
        RescanConfirmPage.Visibility = Visibility.Collapsed;
        OneDriveNoticePage.Visibility = Visibility.Collapsed;
        ChooseRepositoryPage.Visibility = Visibility.Collapsed;
        WindowsImportPage.Visibility = Visibility.Collapsed;
        WatcherStatusPage.Visibility = Visibility.Visible;
        WindowsMainWindowPage.Visibility = Visibility.Collapsed;
        PlatformDifferencesPage.Visibility = Visibility.Collapsed;
        RepositorySettingsPage.Visibility = Visibility.Collapsed;
        RepositoryInitConfirmPage.Visibility = Visibility.Collapsed;
        RepositoryAdoptConfirmPage.Visibility = Visibility.Collapsed;
    }

    private void RepositoryInitConfirmPage_CloseRequested()
    {
        RepositoryInitConfirmPage.Visibility = Visibility.Collapsed;
        RepositoryAdoptConfirmPage.Visibility = Visibility.Collapsed;
        OneDriveNoticePage.Visibility = Visibility.Collapsed;
        WindowsMainWindowPage.Visibility = Visibility.Collapsed;
        WindowsImportPage.Visibility = Visibility.Collapsed;
        WatcherStatusPage.Visibility = Visibility.Collapsed;
        RescanConfirmPage.Visibility = Visibility.Collapsed;
        PlatformDifferencesPage.Visibility = Visibility.Collapsed;
        RepositorySettingsPage.Visibility = Visibility.Collapsed;
        ChooseRepositoryPage.ViewModel?.ResetRoute();
        ChooseRepositoryPage.Visibility = Visibility.Visible;
    }

    private async Task RepositoryInitConfirmPage_RepositoryOpenedRequested(WindowsRepositoryRoute route)
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
        await WindowsMainWindowPage.OpenRepositoryAsync(route);
    }

    private void RepositoryAdoptConfirmPage_CloseRequested()
    {
        RepositoryAdoptConfirmPage.Visibility = Visibility.Collapsed;
        RepositoryInitConfirmPage.Visibility = Visibility.Collapsed;
        OneDriveNoticePage.Visibility = Visibility.Collapsed;
        WindowsMainWindowPage.Visibility = Visibility.Collapsed;
        WindowsImportPage.Visibility = Visibility.Collapsed;
        WatcherStatusPage.Visibility = Visibility.Collapsed;
        RescanConfirmPage.Visibility = Visibility.Collapsed;
        PlatformDifferencesPage.Visibility = Visibility.Collapsed;
        RepositorySettingsPage.Visibility = Visibility.Collapsed;
        ChooseRepositoryPage.ViewModel?.ResetRoute();
        ChooseRepositoryPage.Visibility = Visibility.Visible;
    }

    private async Task RepositoryAdoptConfirmPage_RepositoryOpenedRequested(WindowsRepositoryRoute route)
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
        await WindowsMainWindowPage.OpenRepositoryAsync(route);
    }

    private void MainWindow_Closed(object sender, WindowEventArgs args)
    {
        if (ChooseRepositoryPage.ViewModel is { } viewModel)
        {
            viewModel.PropertyChanged -= ChooseRepositoryViewModel_PropertyChanged;
        }

        OneDriveNoticePage.ChooseLocalFolderRequested -= OneDriveNoticePage_ChooseLocalFolderRequested;
        OneDriveNoticePage.CloseRequested -= OneDriveNoticePage_CloseRequested;
        OneDriveNoticePage.ContinueWithOneDriveRequested -= OneDriveNoticePage_ContinueWithOneDriveRequested;
        OneDriveNoticePage.OpenWatcherStatusRequested -= OneDriveNoticePage_OpenWatcherStatusRequested;
        RepositoryInitConfirmPage.CancelRequested -= RepositoryInitConfirmPage_CloseRequested;
        RepositoryInitConfirmPage.ChooseAnotherFolderRequested -= RepositoryInitConfirmPage_CloseRequested;
        RepositoryInitConfirmPage.RepositoryOpenedRequested -= RepositoryInitConfirmPage_RepositoryOpenedRequested;
        RepositoryAdoptConfirmPage.CancelRequested -= RepositoryAdoptConfirmPage_CloseRequested;
        RepositoryAdoptConfirmPage.ChooseAnotherFolderRequested -= RepositoryAdoptConfirmPage_CloseRequested;
        RepositoryAdoptConfirmPage.RepositoryOpenedRequested -= RepositoryAdoptConfirmPage_RepositoryOpenedRequested;
        WindowsMainWindowPage.OpenOneDriveStatusRequested -= WindowsMainWindowPage_OpenOneDriveStatusRequested;
        WindowsMainWindowPage.OpenWatcherStatusRequested -= WindowsMainWindowPage_OpenWatcherStatusRequested;
        WindowsMainWindowPage.OpenImportRequested -= WindowsMainWindowPage_OpenImportRequested;
        WindowsMainWindowPage.OpenSyncConflictReviewRequested -= WindowsMainWindowPage_OpenSyncConflictReviewRequested;
        WindowsMainWindowPage.OpenImportDroppedSourcesRequested -= WindowsMainWindowPage_OpenImportDroppedSourcesRequested;
        WindowsMainWindowPage.OpenPlatformDifferencesRequested -= WindowsMainWindowPage_OpenPlatformDifferencesRequested;
        WindowsMainWindowPage.OpenMissingFileRecoveryRequested -= WindowsMainWindowPage_OpenMissingFileRecoveryRequested;
        WindowsImportPage.CloseRequested -= WindowsImportPage_CloseRequested;
        MissingFileRecoveryPage.CloseRequested -= MissingFileRecoveryPage_CloseRequested;
        WatcherStatusPage.CloseRequested -= WatcherStatusPage_CloseRequested;
        WatcherStatusPage.OpenRescanConfirmRequested -= WatcherStatusPage_OpenRescanConfirmRequested;
        PlatformDifferencesPage.CloseRequested -= PlatformDifferencesPage_CloseRequested;
        PlatformDifferencesPage.OpenRepositorySettingsRequested -= PlatformDifferencesPage_OpenRepositorySettingsRequested;
        RepositorySettingsPage.ReconnectRepositoryRequested -= RepositorySettingsPage_ChangeRepositoryRequested;
        RepositorySettingsPage.ChooseAnotherFolderRequested -= RepositorySettingsPage_ChangeRepositoryRequested;
        RepositorySettingsPage.PlatformCapabilitiesRequested -= RepositorySettingsPage_PlatformCapabilitiesRequested;
        RepositorySettingsPage.ExportDiagnosticsRequested -= RepositorySettingsPage_ExportDiagnosticsRequested;
        RescanConfirmPage.CloseRequested -= RescanConfirmPage_CloseRequested;
        watcherDiagnostics.Dispose();
        coreClient.Dispose();
    }

    private void ShowImportPage()
    {
        OneDriveNoticePage.Visibility = Visibility.Collapsed;
        ChooseRepositoryPage.Visibility = Visibility.Collapsed;
        RepositoryInitConfirmPage.Visibility = Visibility.Collapsed;
        RepositoryAdoptConfirmPage.Visibility = Visibility.Collapsed;
        WindowsMainWindowPage.Visibility = Visibility.Collapsed;
        WatcherStatusPage.Visibility = Visibility.Collapsed;
        RescanConfirmPage.Visibility = Visibility.Collapsed;
        PlatformDifferencesPage.Visibility = Visibility.Collapsed;
        RepositorySettingsPage.Visibility = Visibility.Collapsed;
        MissingFileRecoveryPage.Visibility = Visibility.Collapsed;
        WindowsImportPage.Visibility = Visibility.Visible;
    }

    private void ShowMissingFileRecoveryPage()
    {
        OneDriveNoticePage.Visibility = Visibility.Collapsed;
        ChooseRepositoryPage.Visibility = Visibility.Collapsed;
        RepositoryInitConfirmPage.Visibility = Visibility.Collapsed;
        RepositoryAdoptConfirmPage.Visibility = Visibility.Collapsed;
        WindowsMainWindowPage.Visibility = Visibility.Collapsed;
        WindowsImportPage.Visibility = Visibility.Collapsed;
        WatcherStatusPage.Visibility = Visibility.Collapsed;
        RescanConfirmPage.Visibility = Visibility.Collapsed;
        PlatformDifferencesPage.Visibility = Visibility.Collapsed;
        RepositorySettingsPage.Visibility = Visibility.Collapsed;
        MissingFileRecoveryPage.Visibility = Visibility.Visible;
    }

    private void ShowPlatformDifferencesPage()
    {
        OneDriveNoticePage.Visibility = Visibility.Collapsed;
        ChooseRepositoryPage.Visibility = Visibility.Collapsed;
        RepositoryInitConfirmPage.Visibility = Visibility.Collapsed;
        RepositoryAdoptConfirmPage.Visibility = Visibility.Collapsed;
        WindowsMainWindowPage.Visibility = Visibility.Collapsed;
        WindowsImportPage.Visibility = Visibility.Collapsed;
        WatcherStatusPage.Visibility = Visibility.Collapsed;
        RescanConfirmPage.Visibility = Visibility.Collapsed;
        MissingFileRecoveryPage.Visibility = Visibility.Collapsed;
        RepositorySettingsPage.Visibility = Visibility.Collapsed;
        PlatformDifferencesPage.Visibility = Visibility.Visible;
    }

    private async Task ShowRepositorySettingsPageAsync()
    {
        string? repoPath = WindowsMainWindowPage.ViewModel?.RepoPath
            ?? PlatformDifferencesPage.ViewModel?.RepositoryPath;
        RepositorySettingsPage.ViewModel = new RepositorySettingsViewModel(
            new WindowsRepositorySettingsBridge(
                repositoryBridge,
                new PlatformDifferencesCoreBridge(coreClient),
                coreClient.GetVersionAsync),
            repoPath);
        OneDriveNoticePage.Visibility = Visibility.Collapsed;
        ChooseRepositoryPage.Visibility = Visibility.Collapsed;
        RepositoryInitConfirmPage.Visibility = Visibility.Collapsed;
        RepositoryAdoptConfirmPage.Visibility = Visibility.Collapsed;
        WindowsMainWindowPage.Visibility = Visibility.Collapsed;
        WindowsImportPage.Visibility = Visibility.Collapsed;
        WatcherStatusPage.Visibility = Visibility.Collapsed;
        RescanConfirmPage.Visibility = Visibility.Collapsed;
        MissingFileRecoveryPage.Visibility = Visibility.Collapsed;
        PlatformDifferencesPage.Visibility = Visibility.Collapsed;
        RepositorySettingsPage.Visibility = Visibility.Visible;
        await RepositorySettingsPage.OpenAsync();
    }
}
