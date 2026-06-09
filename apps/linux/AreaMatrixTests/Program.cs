using AreaMatrix.Linux.Tests.ChooseRepository;
using AreaMatrix.Linux.Tests.Help;
using AreaMatrix.Linux.Tests.Import;
using AreaMatrix.Linux.Tests.Library;
using AreaMatrix.Linux.Tests.System;

await LinuxChooseRepositoryViewModelTests.RunAllAsync();
await LinuxNativeCoreBridgeSmokeTests.RunAllAsync();
LinuxChooseRepositorySmokeTests.RunAll();
await LocalFolderNoticeViewModelTests.RunAllAsync();
LocalFolderNoticeSmokeTests.RunAll();
await LinuxMainWindowViewModelTests.RunAllAsync();
LinuxMainWindowSmokeTests.RunAll();
await LinuxSyncConflictEntryPageFeatureTests.RunAllAsync();
await LinuxImportViewModelTests.RunAllAsync();
await LinuxImportReplaceViewModelTests.RunAllAsync();
LinuxImportSmokeTests.RunAll();
await LinuxWatcherStatusViewModelTests.RunAllAsync();
LinuxWatcherStatusSmokeTests.RunAll();
await PlatformDifferencesTests.RunAllAsync();

Console.WriteLine("AreaMatrix Linux tests passed.");
