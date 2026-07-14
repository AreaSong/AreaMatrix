use std::{
    env,
    io::{self, Read, Write},
    process::{Child, Command, ExitStatus, Stdio},
    thread,
    time::{Duration, Instant},
};

#[cfg(unix)]
use std::os::unix::process::CommandExt;

#[cfg(unix)]
extern "C" {
    fn kill(pid: i32, signal: i32) -> i32;
}

const SAFE_PATH: &str = "/usr/local/bin:/usr/bin:/bin:/usr/sbin:/sbin";
const POLL_INTERVAL: Duration = Duration::from_millis(10);
#[cfg(unix)]
const SIGKILL: i32 = 9;

#[derive(Clone, Copy, Debug)]
pub(crate) struct ExternalRuntimeLimits {
    pub(crate) timeout: Duration,
    pub(crate) max_stdout_bytes: usize,
    pub(crate) preserved_environment: &'static [&'static str],
}

#[derive(Debug)]
pub(crate) struct ExternalRuntimeOutput {
    pub(crate) status: ExitStatus,
    pub(crate) stdout: Vec<u8>,
}

#[derive(Debug)]
pub(crate) enum ExternalRuntimeError {
    Spawn,
    WriteStdin,
    Wait,
    TimedOut,
    ReadStdout,
    StdoutLimitExceeded,
    WorkerPanicked,
}

/// Runs a configured child process with bounded IO and deterministic cleanup.
///
/// The child receives a minimal, fixed environment. stderr is deliberately discarded because
/// runtime output can contain credentials or provider response details.
pub(crate) fn run(
    command: &mut Command,
    payload: &[u8],
    limits: ExternalRuntimeLimits,
) -> Result<ExternalRuntimeOutput, ExternalRuntimeError> {
    command.env_clear().env("PATH", SAFE_PATH);
    for name in limits.preserved_environment {
        if let Some(value) = env::var_os(name) {
            command.env(name, value);
        }
    }
    command
        .stdin(Stdio::piped())
        .stdout(Stdio::piped())
        .stderr(Stdio::null());
    isolate_process_group(command);

    let mut child = command.spawn().map_err(|_| ExternalRuntimeError::Spawn)?;
    let Some(stdin) = child.stdin.take() else {
        terminate_child(&mut child);
        return Err(ExternalRuntimeError::WriteStdin);
    };
    let Some(stdout) = child.stdout.take() else {
        terminate_child(&mut child);
        return Err(ExternalRuntimeError::ReadStdout);
    };

    let payload = payload.to_vec();
    let writer = thread::spawn(move || write_payload(stdin, &payload));
    let reader = thread::spawn(move || read_bounded(stdout, limits.max_stdout_bytes));
    let (status, timed_out) = match wait_for_child(&mut child, limits.timeout) {
        Ok(result) => result,
        Err(error) => {
            terminate_child(&mut child);
            let _ = writer.join();
            let _ = reader.join();
            return Err(error);
        }
    };

    let write_result = writer
        .join()
        .map_err(|_| ExternalRuntimeError::WorkerPanicked)?;

    if timed_out {
        return Err(ExternalRuntimeError::TimedOut);
    }
    let read_result = reader
        .join()
        .map_err(|_| ExternalRuntimeError::WorkerPanicked)?;
    write_result.map_err(|_| ExternalRuntimeError::WriteStdin)?;
    let (stdout, truncated) = read_result.map_err(|_| ExternalRuntimeError::ReadStdout)?;
    if truncated {
        return Err(ExternalRuntimeError::StdoutLimitExceeded);
    }

    Ok(ExternalRuntimeOutput { status, stdout })
}

fn write_payload(mut stdin: impl Write, payload: &[u8]) -> io::Result<()> {
    stdin.write_all(payload)
}

fn read_bounded(mut stdout: impl Read, limit: usize) -> io::Result<(Vec<u8>, bool)> {
    let mut output = Vec::with_capacity(limit.min(8 * 1024));
    let mut buffer = [0_u8; 8 * 1024];
    let mut truncated = false;

    loop {
        let read = stdout.read(&mut buffer)?;
        if read == 0 {
            return Ok((output, truncated));
        }
        let remaining = limit.saturating_sub(output.len());
        let retained = read.min(remaining);
        output.extend_from_slice(&buffer[..retained]);
        truncated |= retained < read;
    }
}

fn wait_for_child(
    child: &mut Child,
    timeout: Duration,
) -> Result<(ExitStatus, bool), ExternalRuntimeError> {
    let deadline = Instant::now() + timeout;
    loop {
        match child.try_wait().map_err(|_| ExternalRuntimeError::Wait)? {
            Some(status) => return Ok((status, false)),
            None if Instant::now() >= deadline => {
                terminate_child(child);
                let status = child.wait().map_err(|_| ExternalRuntimeError::Wait)?;
                return Ok((status, true));
            }
            None => thread::sleep(POLL_INTERVAL),
        }
    }
}

fn terminate_child(child: &mut Child) {
    terminate_process_group(child);
    let _ = child.kill();
    let _ = child.wait();
}

#[cfg(unix)]
fn isolate_process_group(command: &mut Command) {
    command.process_group(0);
}

#[cfg(not(unix))]
fn isolate_process_group(_command: &mut Command) {}

#[cfg(unix)]
fn terminate_process_group(child: &Child) {
    let process_group = -(child.id() as i32);
    // SAFETY: the child is spawned into a process group whose id equals its pid.
    let _ = unsafe { kill(process_group, SIGKILL) };
}

#[cfg(not(unix))]
fn terminate_process_group(_child: &Child) {}

#[cfg(test)]
mod tests {
    use std::{
        fs,
        path::Path,
        process::Command,
        thread,
        time::{Duration, Instant},
    };

    #[cfg(unix)]
    use super::kill;
    use super::{run, ExternalRuntimeError, ExternalRuntimeLimits};

    fn limits(timeout: Duration, max_stdout_bytes: usize) -> ExternalRuntimeLimits {
        ExternalRuntimeLimits {
            timeout,
            max_stdout_bytes,
            preserved_environment: &[],
        }
    }

    #[test]
    fn captures_bounded_stdout_and_writes_payload() {
        let mut command = shell("cat >/dev/null; printf 'ok'");
        let output = run(&mut command, b"payload", limits(Duration::from_secs(1), 16))
            .expect("runtime should complete");

        assert!(output.status.success());
        assert_eq!(output.stdout, b"ok");
    }

    #[test]
    fn clears_inherited_environment_but_keeps_safe_path() {
        let mut command = shell("printf '%s|%s' \"${AREAMATRIX_TEST_SECRET-unset}\" \"$PATH\"");
        command.env("AREAMATRIX_TEST_SECRET", "must-not-leak");
        let output = run(&mut command, b"", limits(Duration::from_secs(1), 256))
            .expect("runtime should complete");
        let rendered = String::from_utf8(output.stdout).expect("output is utf8");

        assert!(rendered.starts_with("unset|/usr/local/bin:/usr/bin:/bin:/usr/sbin:/sbin"));
    }

    #[test]
    fn rejects_output_over_limit_after_draining_pipe() {
        let mut command = shell("printf '0123456789'");
        let error = run(&mut command, b"", limits(Duration::from_secs(1), 4))
            .expect_err("oversized output should be rejected");

        assert!(matches!(error, ExternalRuntimeError::StdoutLimitExceeded));
    }

    #[test]
    fn kills_and_reaps_hanging_process() {
        let started = Instant::now();
        let mut command = shell("cat >/dev/null; sleep 30");
        let error = run(&mut command, b"", limits(Duration::from_millis(100), 16))
            .expect_err("hanging runtime should time out");

        assert!(matches!(error, ExternalRuntimeError::TimedOut));
        assert!(started.elapsed() < Duration::from_secs(3));
    }

    #[cfg(unix)]
    #[test]
    fn kills_descendant_process_group_on_timeout() {
        let directory = tempfile::tempdir().expect("create descendant pid directory");
        let pid_path = directory.path().join("descendant.pid");
        let script = format!(
            "sleep 30 & descendant=$!; printf '%s' \"$descendant\" > {}; wait",
            shell_quote(&pid_path)
        );
        let mut command = shell(&script);

        let error = run(&mut command, b"", limits(Duration::from_millis(200), 16))
            .expect_err("runtime process group should time out");
        let descendant_pid = fs::read_to_string(&pid_path)
            .expect("read descendant pid")
            .parse::<i32>()
            .expect("parse descendant pid");

        assert!(matches!(error, ExternalRuntimeError::TimedOut));
        assert!(wait_until_process_exits(descendant_pid));
    }

    #[test]
    fn preserves_non_zero_exit_status_for_callers() {
        let mut command = shell("exit 42");
        let output = run(&mut command, b"", limits(Duration::from_secs(1), 16))
            .expect("process execution should complete");

        assert_eq!(output.status.code(), Some(42));
    }

    fn shell(script: &str) -> Command {
        let mut command = Command::new("sh");
        command.arg("-c").arg(script);
        command
    }

    #[cfg(unix)]
    fn wait_until_process_exits(pid: i32) -> bool {
        let deadline = Instant::now() + Duration::from_secs(2);
        while Instant::now() < deadline {
            // SAFETY: signal 0 performs an existence check without sending a signal.
            if unsafe { kill(pid, 0) } != 0 {
                return true;
            }
            thread::sleep(Duration::from_millis(10));
        }
        false
    }

    #[cfg(unix)]
    fn shell_quote(path: &Path) -> String {
        format!("'{}'", path.to_string_lossy().replace('\'', "'\\''"))
    }
}
