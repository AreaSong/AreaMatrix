using AreaMatrixTests.Architecture;
using AreaMatrixTests.ChooseRepository;
using AreaMatrixTests.Conflicts;
using AreaMatrixTests.DesktopMainQuery;
using AreaMatrixTests.Help;
using AreaMatrixTests.Import;
using AreaMatrixTests.Recovery;
using AreaMatrixTests.Settings;
using AreaMatrixTests.WatcherStatus;

if (args is ["native-loader-security"])
{
    NativeCoreLibrarySecurityTests.RunAll();
    Console.WriteLine("AreaMatrix Windows native loader security tests passed.");
    return;
}

ViewModelSynchronizationContextTests.RunAll();
NativeCoreLibrarySecurityTests.RunAll();
NativeCoreContractGoldenVectorTests.RunAll();
await ChooseRepositoryViewModelTests.RunAllAsync();
await ChooseRepositoryPageIntegrationTests.RunAllAsync();
await OneDriveNoticeViewModelTests.RunAllAsync();
await RepositoryInitConfirmViewModelTests.RunAllAsync();
await RepositoryAdoptConfirmViewModelTests.RunAllAsync();
ChooseRepositoryViewSmokeTests.RunAll();
OneDriveNoticeViewSmokeTests.RunAll();
RepositoryInitConfirmViewSmokeTests.RunAll();
RepositoryAdoptConfirmViewSmokeTests.RunAll();
await DesktopMainQueryViewModelTests.RunAllAsync();
DesktopMainQuerySmokeTests.RunAll();
await WindowsImportViewModelTests.RunAllAsync();
await WindowsImportReplaceViewModelTests.RunAllAsync();
WindowsImportSmokeTests.RunAll();
await WatcherStatusViewModelTests.RunAllAsync();
await RescanConfirmViewModelTests.RunAllAsync();
WatcherStatusSmokeTests.RunAll();
await PlatformDifferencesTests.RunAllAsync();
await RepositorySettingsViewModelTests.RunAllAsync();
await WindowsSyncConflictEntryPageFeatureTests.RunAllAsync();
await MissingFileRecoveryViewModelTests.RunAllAsync();
Console.WriteLine("AreaMatrix Windows tests passed.");
