using AreaMatrixTests.ChooseRepository;
using AreaMatrixTests.DesktopMainQuery;
using AreaMatrixTests.Import;
using AreaMatrixTests.WatcherStatus;

await ChooseRepositoryViewModelTests.RunAllAsync();
await ChooseRepositoryPageIntegrationTests.RunAllAsync();
await OneDriveNoticeViewModelTests.RunAllAsync();
ChooseRepositoryViewSmokeTests.RunAll();
OneDriveNoticeViewSmokeTests.RunAll();
await DesktopMainQueryViewModelTests.RunAllAsync();
DesktopMainQuerySmokeTests.RunAll();
await WindowsImportViewModelTests.RunAllAsync();
await WindowsImportReplaceViewModelTests.RunAllAsync();
WindowsImportSmokeTests.RunAll();
await WatcherStatusViewModelTests.RunAllAsync();
WatcherStatusSmokeTests.RunAll();
Console.WriteLine("AreaMatrix Windows tests passed.");
