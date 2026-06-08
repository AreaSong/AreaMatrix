using System.ComponentModel;
using System.Diagnostics;

namespace AreaMatrix.Linux.Features.Onboarding;

public interface ILinuxFolderPickerAdapter
{
    Task<string?> PickFolderAsync(CancellationToken cancellationToken = default);
}

public sealed class LinuxSystemFolderPickerAdapter : ILinuxFolderPickerAdapter
{
    private readonly ILinuxFolderPickerCommandRunner commandRunner;
    private readonly IReadOnlyList<LinuxFolderPickerCommand> commands;

    public LinuxSystemFolderPickerAdapter()
        : this(new LinuxProcessFolderPickerCommandRunner(), LinuxFolderPickerCommand.DefaultCommands)
    {
    }

    public LinuxSystemFolderPickerAdapter(
        ILinuxFolderPickerCommandRunner commandRunner,
        IReadOnlyList<LinuxFolderPickerCommand> commands)
    {
        this.commandRunner = commandRunner;
        this.commands = commands;
    }

    public async Task<string?> PickFolderAsync(CancellationToken cancellationToken = default)
    {
        cancellationToken.ThrowIfCancellationRequested();

        foreach (LinuxFolderPickerCommand command in commands)
        {
            if (!commandRunner.CanRun(command.Executable))
            {
                continue;
            }

            LinuxFolderPickerCommandResult result = await commandRunner
                .RunAsync(command.Executable, command.Arguments, cancellationToken);
            return SelectedPathOrThrow(command, result);
        }

        throw new LinuxFolderPickerException(
            "No supported Linux folder picker was found. Install zenity or kdialog, then retry Browse.");
    }

    private static string? SelectedPathOrThrow(
        LinuxFolderPickerCommand command,
        LinuxFolderPickerCommandResult result)
    {
        if (result.ExitCode == 0)
        {
            string selectedPath = result.StandardOutput.Trim();
            return string.IsNullOrWhiteSpace(selectedPath) ? null : selectedPath;
        }

        if (result.ExitCode == 1)
        {
            return null;
        }

        string detail = string.IsNullOrWhiteSpace(result.StandardError)
            ? $"exit code {result.ExitCode}"
            : result.StandardError.Trim();
        throw new LinuxFolderPickerException(
            $"Linux folder picker `{command.Executable}` failed: {detail}");
    }
}

public sealed class LinuxDefaultRepositoryPathProvider
{
    public string SuggestedRepositoryPath
    {
        get
        {
            string home = Environment.GetFolderPath(Environment.SpecialFolder.UserProfile);
            return string.IsNullOrWhiteSpace(home)
                ? "~/AreaMatrix"
                : Path.Combine(home, "AreaMatrix");
        }
    }
}

public interface ILinuxFolderPickerCommandRunner
{
    bool CanRun(string executable);

    Task<LinuxFolderPickerCommandResult> RunAsync(
        string executable,
        IReadOnlyList<string> arguments,
        CancellationToken cancellationToken);
}

public sealed record LinuxFolderPickerCommand(
    string Executable,
    IReadOnlyList<string> Arguments)
{
    public static IReadOnlyList<LinuxFolderPickerCommand> DefaultCommands { get; } =
    [
        new("zenity", ["--file-selection", "--directory", "--title=Choose AreaMatrix Repository"]),
        new("kdialog", ["--getexistingdirectory", Environment.GetFolderPath(Environment.SpecialFolder.UserProfile)])
    ];
}

public sealed record LinuxFolderPickerCommandResult(
    int ExitCode,
    string StandardOutput,
    string StandardError);

public sealed class LinuxFolderPickerException : Exception
{
    public LinuxFolderPickerException(string message)
        : base(message)
    {
    }
}

public sealed class LinuxProcessFolderPickerCommandRunner : ILinuxFolderPickerCommandRunner
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

    public async Task<LinuxFolderPickerCommandResult> RunAsync(
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
            return new LinuxFolderPickerCommandResult(127, string.Empty, exception.Message);
        }

        using CancellationTokenRegistration registration = cancellationToken.Register(() => Kill(process));
        Task<string> stdout = process.StandardOutput.ReadToEndAsync(cancellationToken);
        Task<string> stderr = process.StandardError.ReadToEndAsync(cancellationToken);
        await process.WaitForExitAsync(cancellationToken);
        return new LinuxFolderPickerCommandResult(process.ExitCode, await stdout, await stderr);
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
