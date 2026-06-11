using System.ComponentModel;
using System.Diagnostics;

namespace AreaMatrix.Linux.Features.Recovery;

public interface IMissingFileRecoveryFilePicker
{
    Task<string?> PickReplacementFileAsync(CancellationToken cancellationToken = default);
}

public sealed class LinuxMissingFileRecoveryFilePicker : IMissingFileRecoveryFilePicker
{
    private readonly IMissingFileRecoveryPickerCommandRunner commandRunner;
    private readonly IReadOnlyList<MissingFileRecoveryPickerCommand> commands;

    public LinuxMissingFileRecoveryFilePicker()
        : this(
            new MissingFileRecoveryPickerCommandRunner(),
            MissingFileRecoveryPickerCommand.DefaultCommands)
    {
    }

    public LinuxMissingFileRecoveryFilePicker(
        IMissingFileRecoveryPickerCommandRunner commandRunner,
        IReadOnlyList<MissingFileRecoveryPickerCommand> commands)
    {
        this.commandRunner = commandRunner;
        this.commands = commands;
    }

    public async Task<string?> PickReplacementFileAsync(
        CancellationToken cancellationToken = default)
    {
        foreach (MissingFileRecoveryPickerCommand command in commands)
        {
            if (!commandRunner.CanRun(command.Executable))
            {
                continue;
            }

            MissingFileRecoveryPickerCommandResult result = await commandRunner
                .RunAsync(command.Executable, command.Arguments, cancellationToken)
                .ConfigureAwait(false);
            return SelectedPathOrThrow(command, result);
        }

        throw new MissingFileRecoveryCoreException(
            MissingFileRecoveryErrorKind.Unavailable,
            "No supported Linux file picker was found. Install zenity or kdialog, then retry.");
    }

    private static string? SelectedPathOrThrow(
        MissingFileRecoveryPickerCommand command,
        MissingFileRecoveryPickerCommandResult result)
    {
        if (result.ExitCode == 0)
        {
            return result.StandardOutput
                .Split(['\r', '\n'], StringSplitOptions.RemoveEmptyEntries | StringSplitOptions.TrimEntries)
                .FirstOrDefault(path => !string.IsNullOrWhiteSpace(path));
        }

        if (result.ExitCode == 1)
        {
            return null;
        }

        string detail = string.IsNullOrWhiteSpace(result.StandardError)
            ? $"exit code {result.ExitCode}"
            : result.StandardError.Trim();
        throw new MissingFileRecoveryCoreException(
            MissingFileRecoveryErrorKind.Unavailable,
            $"Linux missing-file picker `{command.Executable}` failed: {detail}");
    }
}

public interface IMissingFileRecoveryPickerCommandRunner
{
    bool CanRun(string executable);

    Task<MissingFileRecoveryPickerCommandResult> RunAsync(
        string executable,
        IReadOnlyList<string> arguments,
        CancellationToken cancellationToken);
}

public sealed record MissingFileRecoveryPickerCommand(
    string Executable,
    IReadOnlyList<string> Arguments)
{
    public static IReadOnlyList<MissingFileRecoveryPickerCommand> DefaultCommands { get; } =
    [
        new("zenity", ["--file-selection", "--title=Locate missing file"]),
        new("kdialog", ["--getopenfilename", Environment.GetFolderPath(Environment.SpecialFolder.UserProfile)])
    ];
}

public sealed record MissingFileRecoveryPickerCommandResult(
    int ExitCode,
    string StandardOutput,
    string StandardError);

public sealed class MissingFileRecoveryPickerCommandRunner : IMissingFileRecoveryPickerCommandRunner
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

    public async Task<MissingFileRecoveryPickerCommandResult> RunAsync(
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
            return new MissingFileRecoveryPickerCommandResult(127, string.Empty, exception.Message);
        }

        using CancellationTokenRegistration registration = cancellationToken.Register(() => Kill(process));
        Task<string> stdout = process.StandardOutput.ReadToEndAsync(cancellationToken);
        Task<string> stderr = process.StandardError.ReadToEndAsync(cancellationToken);
        await process.WaitForExitAsync(cancellationToken).ConfigureAwait(false);
        return new MissingFileRecoveryPickerCommandResult(process.ExitCode, await stdout, await stderr);
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
