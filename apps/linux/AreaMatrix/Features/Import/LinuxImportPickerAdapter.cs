using System.ComponentModel;
using System.Diagnostics;

namespace AreaMatrix.Linux.Features.Import;

public interface ILinuxImportPickerAdapter
{
    Task<IReadOnlyList<string>> PickFilesAsync(CancellationToken cancellationToken = default);

    Task<string?> PickFolderAsync(CancellationToken cancellationToken = default);
}

public sealed class LinuxSystemImportPickerAdapter : ILinuxImportPickerAdapter
{
    private readonly ILinuxImportPickerCommandRunner commandRunner;
    private readonly IReadOnlyList<LinuxImportPickerCommand> fileCommands;
    private readonly IReadOnlyList<LinuxImportPickerCommand> folderCommands;

    public LinuxSystemImportPickerAdapter()
        : this(
            new LinuxImportPickerCommandRunner(),
            LinuxImportPickerCommand.FileCommands,
            LinuxImportPickerCommand.FolderCommands)
    {
    }

    public LinuxSystemImportPickerAdapter(
        ILinuxImportPickerCommandRunner commandRunner,
        IReadOnlyList<LinuxImportPickerCommand> fileCommands,
        IReadOnlyList<LinuxImportPickerCommand> folderCommands)
    {
        this.commandRunner = commandRunner;
        this.fileCommands = fileCommands;
        this.folderCommands = folderCommands;
    }

    public Task<IReadOnlyList<string>> PickFilesAsync(CancellationToken cancellationToken = default)
    {
        return PickManyAsync(fileCommands, cancellationToken);
    }

    public async Task<string?> PickFolderAsync(CancellationToken cancellationToken = default)
    {
        IReadOnlyList<string> paths = await PickManyAsync(folderCommands, cancellationToken)
            .ConfigureAwait(false);
        return paths.Count == 0 ? null : paths[0];
    }

    private async Task<IReadOnlyList<string>> PickManyAsync(
        IReadOnlyList<LinuxImportPickerCommand> commands,
        CancellationToken cancellationToken)
    {
        foreach (LinuxImportPickerCommand command in commands)
        {
            if (!commandRunner.CanRun(command.Executable))
            {
                continue;
            }

            LinuxImportPickerCommandResult result = await commandRunner
                .RunAsync(command.Executable, command.Arguments, cancellationToken)
                .ConfigureAwait(false);
            return SelectedPathsOrThrow(command, result);
        }

        throw new DesktopImportCoreException(
            DesktopImportErrorKind.Unavailable,
            "No supported Linux file picker was found. Install zenity or kdialog, then retry.");
    }

    private static IReadOnlyList<string> SelectedPathsOrThrow(
        LinuxImportPickerCommand command,
        LinuxImportPickerCommandResult result)
    {
        if (result.ExitCode == 0)
        {
            return result.StandardOutput
                .Split(['\r', '\n'], StringSplitOptions.RemoveEmptyEntries | StringSplitOptions.TrimEntries)
                .Where(path => !string.IsNullOrWhiteSpace(path))
                .ToArray();
        }

        if (result.ExitCode == 1)
        {
            return [];
        }

        string detail = string.IsNullOrWhiteSpace(result.StandardError)
            ? $"exit code {result.ExitCode}"
            : result.StandardError.Trim();
        throw new DesktopImportCoreException(
            DesktopImportErrorKind.Unavailable,
            $"Linux file picker `{command.Executable}` failed: {detail}");
    }
}

public interface ILinuxImportPickerCommandRunner
{
    bool CanRun(string executable);

    Task<LinuxImportPickerCommandResult> RunAsync(
        string executable,
        IReadOnlyList<string> arguments,
        CancellationToken cancellationToken);
}

public sealed record LinuxImportPickerCommand(
    string Executable,
    IReadOnlyList<string> Arguments)
{
    public static IReadOnlyList<LinuxImportPickerCommand> FileCommands { get; } =
    [
        new("zenity", ["--file-selection", "--multiple", "--separator=\n", "--title=Add files to AreaMatrix"]),
        new("kdialog", ["--getopenfilename", Environment.GetFolderPath(Environment.SpecialFolder.UserProfile)])
    ];

    public static IReadOnlyList<LinuxImportPickerCommand> FolderCommands { get; } =
    [
        new("zenity", ["--file-selection", "--directory", "--title=Add folder to AreaMatrix"]),
        new("kdialog", ["--getexistingdirectory", Environment.GetFolderPath(Environment.SpecialFolder.UserProfile)])
    ];
}

public sealed record LinuxImportPickerCommandResult(
    int ExitCode,
    string StandardOutput,
    string StandardError);

public sealed class LinuxImportPickerCommandRunner : ILinuxImportPickerCommandRunner
{
    public bool CanRun(string executable)
    {
        if (Path.IsPathRooted(executable))
        {
            return File.Exists(executable);
        }

        string? path = Environment.GetEnvironmentVariable("PATH");
        return path?.Split(Path.PathSeparator)
            .Where(directory => !string.IsNullOrWhiteSpace(directory))
            .Any(directory => File.Exists(Path.Combine(directory, executable))) == true;
    }

    public async Task<LinuxImportPickerCommandResult> RunAsync(
        string executable,
        IReadOnlyList<string> arguments,
        CancellationToken cancellationToken)
    {
        using Process process = CreateProcess(executable, arguments);
        try
        {
            process.Start();
        }
        catch (Win32Exception exception)
        {
            return new LinuxImportPickerCommandResult(127, string.Empty, exception.Message);
        }

        using CancellationTokenRegistration registration = cancellationToken.Register(() => Kill(process));
        Task<string> stdout = process.StandardOutput.ReadToEndAsync(cancellationToken);
        Task<string> stderr = process.StandardError.ReadToEndAsync(cancellationToken);
        await process.WaitForExitAsync(cancellationToken).ConfigureAwait(false);
        return new LinuxImportPickerCommandResult(process.ExitCode, await stdout, await stderr);
    }

    private static Process CreateProcess(string executable, IReadOnlyList<string> arguments)
    {
        ProcessStartInfo startInfo = new(executable)
        {
            UseShellExecute = false,
            RedirectStandardOutput = true,
            RedirectStandardError = true,
            CreateNoWindow = true
        };
        foreach (string argument in arguments)
        {
            startInfo.ArgumentList.Add(argument);
        }

        return new Process { StartInfo = startInfo };
    }

    private static void Kill(Process process)
    {
        if (!process.HasExited)
        {
            process.Kill(entireProcessTree: true);
        }
    }
}
