using System.ComponentModel;
using System.Diagnostics;

namespace AreaMatrix.Linux.Features.Onboarding;

public interface ILinuxFolderOpener
{
    Task OpenFolderAsync(
        string folderPath,
        CancellationToken cancellationToken = default);
}

public sealed class LinuxSystemFolderOpener : ILinuxFolderOpener
{
    private readonly ILinuxFolderOpenCommandRunner commandRunner;
    private readonly IReadOnlyList<LinuxFolderOpenCommand> commands;

    public LinuxSystemFolderOpener()
        : this(new LinuxProcessFolderOpenCommandRunner(), LinuxFolderOpenCommand.DefaultCommands)
    {
    }

    public LinuxSystemFolderOpener(
        ILinuxFolderOpenCommandRunner commandRunner,
        IReadOnlyList<LinuxFolderOpenCommand> commands)
    {
        this.commandRunner = commandRunner;
        this.commands = commands;
    }

    public async Task OpenFolderAsync(
        string folderPath,
        CancellationToken cancellationToken = default)
    {
        if (string.IsNullOrWhiteSpace(folderPath))
        {
            throw new LinuxFolderOpenException("Choose a repository folder first.");
        }

        foreach (LinuxFolderOpenCommand command in commands)
        {
            if (!commandRunner.CanRun(command.Executable))
            {
                continue;
            }

            LinuxFolderOpenCommandResult result = await commandRunner
                .RunAsync(command.Executable, command.Arguments(folderPath), cancellationToken)
                .ConfigureAwait(false);
            ThrowIfFailed(command, result);
            return;
        }

        throw new LinuxFolderOpenException(
            "No supported Linux file manager command was found. Open the folder from your desktop environment.");
    }

    private static void ThrowIfFailed(
        LinuxFolderOpenCommand command,
        LinuxFolderOpenCommandResult result)
    {
        if (result.ExitCode == 0)
        {
            return;
        }

        string detail = string.IsNullOrWhiteSpace(result.StandardError)
            ? $"exit code {result.ExitCode}"
            : result.StandardError.Trim();
        throw new LinuxFolderOpenException(
            $"Linux folder open command `{command.Executable}` failed: {detail}");
    }
}

public interface ILinuxFolderOpenCommandRunner
{
    bool CanRun(string executable);

    Task<LinuxFolderOpenCommandResult> RunAsync(
        string executable,
        IReadOnlyList<string> arguments,
        CancellationToken cancellationToken);
}

public sealed record LinuxFolderOpenCommand(
    string Executable,
    Func<string, IReadOnlyList<string>> Arguments)
{
    public static IReadOnlyList<LinuxFolderOpenCommand> DefaultCommands { get; } =
    [
        new("xdg-open", path => [path]),
        new("gio", path => ["open", path]),
        new("kde-open", path => [path])
    ];
}

public sealed record LinuxFolderOpenCommandResult(
    int ExitCode,
    string StandardError);

public sealed class LinuxFolderOpenException : Exception
{
    public LinuxFolderOpenException(string message)
        : base(message)
    {
    }
}

public sealed class LinuxProcessFolderOpenCommandRunner : ILinuxFolderOpenCommandRunner
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

    public async Task<LinuxFolderOpenCommandResult> RunAsync(
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
            return new LinuxFolderOpenCommandResult(127, exception.Message);
        }

        using CancellationTokenRegistration registration = cancellationToken.Register(() => Kill(process));
        Task<string> stderr = process.StandardError.ReadToEndAsync(cancellationToken);
        await process.WaitForExitAsync(cancellationToken).ConfigureAwait(false);
        return new LinuxFolderOpenCommandResult(process.ExitCode, await stderr.ConfigureAwait(false));
    }

    private static Process CreateProcess(string executable, IReadOnlyList<string> arguments)
    {
        ProcessStartInfo startInfo = new(executable)
        {
            UseShellExecute = false,
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
