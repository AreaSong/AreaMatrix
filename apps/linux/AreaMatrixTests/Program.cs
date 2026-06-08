using AreaMatrix.Linux.Tests.ChooseRepository;
using AreaMatrix.Linux.Tests.Library;

await LinuxChooseRepositoryViewModelTests.RunAllAsync();
await LinuxNativeCoreBridgeSmokeTests.RunAllAsync();
LinuxChooseRepositorySmokeTests.RunAll();
await LinuxMainWindowViewModelTests.RunAllAsync();
LinuxMainWindowSmokeTests.RunAll();

Console.WriteLine("AreaMatrix Linux tests passed.");
