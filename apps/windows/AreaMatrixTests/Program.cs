using AreaMatrixTests.ChooseRepository;

await ChooseRepositoryViewModelTests.RunAllAsync();
await ChooseRepositoryPageIntegrationTests.RunAllAsync();
ChooseRepositoryViewSmokeTests.RunAll();
Console.WriteLine("AreaMatrix Windows choose-repository tests passed.");
