using AreaMatrix.Linux.Tests.ChooseRepository;
using AreaMatrix.Linux.Tests.Help;
using AreaMatrix.Linux.Tests.Import;
using AreaMatrix.Linux.Tests.Library;
using AreaMatrix.Linux.Tests.Recovery;
using AreaMatrix.Linux.Tests.Settings;
using AreaMatrix.Linux.Tests.System;

if (args is ["native-loader-security"])
{
    LinuxNativeCoreLibrarySecurityTests.RunAll();
    Console.WriteLine("AreaMatrix Linux native loader security tests passed.");
    return;
}

await LinuxChooseRepositoryViewModelTests.RunAllAsync();
LinuxNativeCoreLibrarySecurityTests.RunAll();
LinuxNativeCoreContractGoldenVectorTests.RunAll();
await LinuxNativeCoreBridgeSmokeTests.RunAllAsync();
LinuxChooseRepositorySmokeTests.RunAll();
await LocalFolderNoticeViewModelTests.RunAllAsync();
LocalFolderNoticeSmokeTests.RunAll();
await RepositoryInitConfirmViewModelTests.RunAllAsync();
RepositoryInitConfirmSmokeTests.RunAll();
await RepositoryAdoptConfirmViewModelTests.RunAllAsync();
RepositoryAdoptConfirmSmokeTests.RunAll();
await LinuxMainWindowViewModelTests.RunAllAsync();
LinuxMainWindowSmokeTests.RunAll();
await LinuxSyncConflictEntryPageFeatureTests.RunAllAsync();
await LinuxImportViewModelTests.RunAllAsync();
await LinuxImportReplaceViewModelTests.RunAllAsync();
LinuxImportSmokeTests.RunAll();
await MissingFileRecoveryViewModelTests.RunAllAsync();
await LinuxWatcherStatusViewModelTests.RunAllAsync();
await LinuxRescanConfirmViewModelTests.RunAllAsync();
LinuxWatcherStatusSmokeTests.RunAll();
await PlatformDifferencesTests.RunAllAsync();
await RepositorySettingsViewModelTests.RunAllAsync();

Console.WriteLine("AreaMatrix Linux tests passed.");
