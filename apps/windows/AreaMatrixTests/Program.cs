using AreaMatrixTests.ChooseRepository;
using AreaMatrixTests.DesktopMainQuery;

await ChooseRepositoryViewModelTests.RunAllAsync();
await ChooseRepositoryPageIntegrationTests.RunAllAsync();
ChooseRepositoryViewSmokeTests.RunAll();
await DesktopMainQueryViewModelTests.RunAllAsync();
DesktopMainQuerySmokeTests.RunAll();
Console.WriteLine("AreaMatrix Windows tests passed.");
