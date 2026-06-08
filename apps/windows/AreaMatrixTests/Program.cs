using AreaMatrixTests.ChooseRepository;
using AreaMatrixTests.DesktopMainQuery;

await ChooseRepositoryViewModelTests.RunAllAsync();
await ChooseRepositoryPageIntegrationTests.RunAllAsync();
await OneDriveNoticeViewModelTests.RunAllAsync();
ChooseRepositoryViewSmokeTests.RunAll();
OneDriveNoticeViewSmokeTests.RunAll();
await DesktopMainQueryViewModelTests.RunAllAsync();
DesktopMainQuerySmokeTests.RunAll();
Console.WriteLine("AreaMatrix Windows tests passed.");
