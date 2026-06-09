using AreaMatrix.Linux.Features.Conflicts;
using AreaMatrix.Linux.Features.Help;
using AreaMatrix.Linux.Features.Import;
using AreaMatrix.Linux.Features.Onboarding;
using AreaMatrix.Linux.Features.Recovery;
using AreaMatrix.Linux.Features.System;

namespace AreaMatrix.Linux.Features.Library;

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

public sealed class LinuxRepositoryInitConfirmFactory : ILinuxRepositoryInitConfirmFactory
{
    private readonly ILinuxRepositoryCoreBridge coreBridge;

    public LinuxRepositoryInitConfirmFactory(ILinuxRepositoryCoreBridge coreBridge)
    {
        this.coreBridge = coreBridge;
    }

    public RepositoryInitConfirmView Create(LinuxRepositoryRoute route)
    {
        return new RepositoryInitConfirmView(new RepositoryInitConfirmViewModel(coreBridge));
    }
}

public sealed class LinuxRepositoryAdoptConfirmFactory : ILinuxRepositoryAdoptConfirmFactory
{
    private readonly ILinuxRepositoryCoreBridge coreBridge;

    public LinuxRepositoryAdoptConfirmFactory(ILinuxRepositoryCoreBridge coreBridge)
    {
        this.coreBridge = coreBridge;
    }

    public RepositoryAdoptConfirmView Create(LinuxRepositoryRoute route)
    {
        return new RepositoryAdoptConfirmView(new RepositoryAdoptConfirmViewModel(coreBridge));
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

public sealed class LinuxMissingFileRecoveryViewFactory : ILinuxMissingFileRecoveryViewFactory
{
    private readonly IMissingFileRecoveryCoreBridge coreBridge;
    private readonly IMissingFileRecoveryFilePicker filePicker;

    public LinuxMissingFileRecoveryViewFactory(
        IMissingFileRecoveryCoreBridge coreBridge,
        IMissingFileRecoveryFilePicker? filePicker = null)
    {
        this.coreBridge = coreBridge;
        this.filePicker = filePicker ?? new LinuxMissingFileRecoveryFilePicker();
    }

    public MissingFileRecoveryView Create(MissingFileRecoveryRoute route)
    {
        return new MissingFileRecoveryView(new MissingFileRecoveryViewModel(coreBridge), filePicker);
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

public sealed class LinuxRescanConfirmViewFactory : ILinuxRescanConfirmViewFactory
{
    private readonly ILinuxWatcherStatusCoreBridge coreBridge;

    public LinuxRescanConfirmViewFactory(ILinuxWatcherStatusCoreBridge coreBridge)
    {
        this.coreBridge = coreBridge;
    }

    public LinuxRescanConfirmView Create(LinuxRescanConfirmRequest request)
    {
        return new LinuxRescanConfirmView(new LinuxRescanConfirmViewModel(coreBridge));
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
