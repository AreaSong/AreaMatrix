using AreaMatrix.Linux.Tests.ChooseRepository;
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
await LinuxImportViewModelTests.RunAllAsync();
LinuxImportSmokeTests.RunAll();
await LinuxWatcherStatusViewModelTests.RunAllAsync();
LinuxWatcherStatusSmokeTests.RunAll();

Console.WriteLine("AreaMatrix Linux tests passed.");
