using AreaMatrix.Linux.Tests.ChooseRepository;

await LinuxChooseRepositoryViewModelTests.RunAllAsync();
await LinuxNativeCoreBridgeSmokeTests.RunAllAsync();
LinuxChooseRepositorySmokeTests.RunAll();

Console.WriteLine("AreaMatrix Linux tests passed.");
