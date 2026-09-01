use std::{
    env, fs,
    io::{self, Read, Write},
    path::{Path, PathBuf},
    process::{Child, Command, ExitStatus, Stdio},
    thread,
    time::{Duration, Instant, SystemTime},
};

use serde::Deserialize;
use sha2::{Digest, Sha256};

#[cfg(debug_assertions)]
use std::sync::atomic::{AtomicUsize, Ordering};

#[cfg(unix)]
use std::os::unix::{fs::MetadataExt, process::CommandExt};

#[cfg(unix)]
extern "C" {
    fn kill(pid: i32, signal: i32) -> i32;
}

const SAFE_PATH: &str = "/usr/local/bin:/usr/bin:/bin:/usr/sbin:/sbin";
const POLL_INTERVAL: Duration = Duration::from_millis(10);
const RUNTIME_MANIFEST_SCHEMA_VERSION: u32 = 1;
const RUNTIME_PROTOCOL_VERSION: &str = "1";
const MAX_MANIFEST_BYTES: u64 = 64 * 1024;
const TEST_RUNTIME_PROVIDER: &str = "areamatrix-test-fixture";
const TEST_RUNTIME_ENDPOINT: &str = "https://example.invalid/areamatrix-test-endpoint";
const TEST_RUNTIME_PRIVACY_CLASSIFICATION: &str = "synthetic-test-data-only";
const TEST_RUNTIME_SOURCE: &str = "https://example.invalid/areamatrix-test-runtime";
const ALLOWED_LICENSES: &[&str] = &[
    "MIT",
    "Apache-2.0",
    "BSD-2-Clause",
    "BSD-3-Clause",
    "ISC",
    "Unicode-DFS-2016",
];
#[cfg(unix)]
const SIGKILL: i32 = 9;

#[cfg(debug_assertions)]
static TEST_HARNESS_USERS: AtomicUsize = AtomicUsize::new(0);

#[cfg(debug_assertions)]
const TEST_HARNESS_TARGETS: &[&str] = &[
    "ai_call_log_implementation",
    "ai_call_log_schema_compatibility",
    "ai_classification_suggestion_failure_recovery",
    "ai_classification_suggestion_implementation",
    "ai_classification_suggestion_validation",
    "ai_summary_failure_recovery",
    "ai_summary_implementation",
    "ai_summary_validation",
    "ai_tags_suggestion_failure_recovery",
    "ai_tags_suggestion_implementation",
    "area_matrix_core",
    "semantic_search_failure_recovery",
    "semantic_search_implementation",
];

/// Process-local capability that enables external runtime fixtures in debug test binaries.
///
/// Production callers cannot enable an environment-provided executable without explicitly
/// linking test support and holding this capability.
#[cfg(debug_assertions)]
#[doc(hidden)]
pub struct ExternalRuntimeTestHarnessGuard {
    _private: (),
}

/// Enables the process-local external runtime harness until the returned guard is dropped.
#[cfg(debug_assertions)]
#[doc(hidden)]
pub fn enable_external_runtime_test_harness() -> ExternalRuntimeTestHarnessGuard {
    TEST_HARNESS_USERS.fetch_add(1, Ordering::AcqRel);
    ExternalRuntimeTestHarnessGuard { _private: () }
}

#[cfg(debug_assertions)]
impl Drop for ExternalRuntimeTestHarnessGuard {
    fn drop(&mut self) {
        TEST_HARNESS_USERS.fetch_sub(1, Ordering::AcqRel);
    }
}

#[derive(Clone, Debug)]
pub(crate) struct VerifiedExternalRuntime {
    executable: PathBuf,
    identity: RuntimeFileIdentity,
    expected_sha256: String,
}

#[derive(Clone, Debug, Eq, PartialEq)]
struct RuntimeFileIdentity {
    #[cfg(unix)]
    device: u64,
    #[cfg(unix)]
    inode: u64,
    length: u64,
    modified: Option<SystemTime>,
}

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
    Untrusted,
    Spawn,
    WriteStdin,
    Wait,
    TimedOut,
    ReadStdout,
    StdoutLimitExceeded,
    WorkerPanicked,
}

#[derive(Debug, Deserialize)]
#[serde(deny_unknown_fields)]
struct RuntimeManifest {
    schema_version: u32,
    capability: String,
    version: String,
    executable: String,
    platforms: Vec<String>,
    sha256: String,
    provider: String,
    endpoint: String,
    privacy_classification: String,
    license: String,
    source: String,
}

pub(crate) fn resolve(
    runtime_env: &str,
    capability: &str,
) -> Result<Option<VerifiedExternalRuntime>, ExternalRuntimeError> {
    let Some(configured) = env::var_os(runtime_env).filter(|value| !value.is_empty()) else {
        return Ok(None);
    };
    if !test_harness_enabled() {
        return Err(ExternalRuntimeError::Untrusted);
    }
    let (executable, identity) = canonical_regular_file(Path::new(&configured), true)?;
    let manifest_path = companion_manifest_path(&executable);
    let (manifest_path, _) = canonical_regular_file(&manifest_path, false)?;
    let manifest = read_manifest(&manifest_path)?;
    validate_manifest(&manifest, capability, &executable)?;
    validate_runtime_hash(&executable, &identity, &manifest.sha256)?;
    Ok(Some(VerifiedExternalRuntime {
        executable,
        identity,
        expected_sha256: manifest.sha256,
    }))
}

#[cfg(debug_assertions)]
fn test_harness_enabled() -> bool {
    TEST_HARNESS_USERS.load(Ordering::Acquire) > 0 && is_known_test_target()
}

#[cfg(debug_assertions)]
fn is_known_test_target() -> bool {
    let Ok(executable) = env::current_exe() else {
        return false;
    };
    let Some(name) = executable.file_stem().and_then(|value| value.to_str()) else {
        return false;
    };
    TEST_HARNESS_TARGETS.iter().any(|target| {
        name == *target
            || name
                .strip_prefix(target)
                .is_some_and(|suffix| suffix.starts_with('-'))
    })
}

#[cfg(not(debug_assertions))]
fn test_harness_enabled() -> bool {
    false
}

fn companion_manifest_path(executable: &Path) -> PathBuf {
    let mut path = executable.as_os_str().to_os_string();
    path.push(".manifest.json");
    PathBuf::from(path)
}

fn read_manifest(path: &Path) -> Result<RuntimeManifest, ExternalRuntimeError> {
    let mut file = fs::File::open(path).map_err(|_| ExternalRuntimeError::Untrusted)?;
    let before = file
        .metadata()
        .map_err(|_| ExternalRuntimeError::Untrusted)?;
    if before.len() > MAX_MANIFEST_BYTES {
        return Err(ExternalRuntimeError::Untrusted);
    }
    let mut bytes = Vec::with_capacity(before.len() as usize);
    file.read_to_end(&mut bytes)
        .map_err(|_| ExternalRuntimeError::Untrusted)?;
    let after = path
        .metadata()
        .map_err(|_| ExternalRuntimeError::Untrusted)?;
    if runtime_file_identity(&before) != runtime_file_identity(&after) {
        return Err(ExternalRuntimeError::Untrusted);
    }
    serde_json::from_slice(&bytes).map_err(|_| ExternalRuntimeError::Untrusted)
}

fn validate_manifest(
    manifest: &RuntimeManifest,
    capability: &str,
    executable: &Path,
) -> Result<(), ExternalRuntimeError> {
    let executable_text = executable.to_str().ok_or(ExternalRuntimeError::Untrusted)?;
    if manifest.schema_version != RUNTIME_MANIFEST_SCHEMA_VERSION
        || manifest.capability != capability
        || manifest.version != RUNTIME_PROTOCOL_VERSION
        || manifest.executable != executable_text
        || !manifest
            .platforms
            .iter()
            .any(|value| value == &current_platform())
        || manifest.provider != TEST_RUNTIME_PROVIDER
        || manifest.endpoint != TEST_RUNTIME_ENDPOINT
        || manifest.privacy_classification != TEST_RUNTIME_PRIVACY_CLASSIFICATION
        || !ALLOWED_LICENSES.contains(&manifest.license.as_str())
        || manifest.source != TEST_RUNTIME_SOURCE
        || !is_sha256(&manifest.sha256)
    {
        return Err(ExternalRuntimeError::Untrusted);
    }
    Ok(())
}

fn current_platform() -> String {
    format!("{}-{}", env::consts::OS, env::consts::ARCH)
}

fn is_sha256(value: &str) -> bool {
    value.len() == 64
        && value
            .bytes()
            .all(|byte| byte.is_ascii_digit() || (b'a'..=b'f').contains(&byte))
}

fn canonical_regular_file(
    path: &Path,
    executable: bool,
) -> Result<(PathBuf, RuntimeFileIdentity), ExternalRuntimeError> {
    if !path.is_absolute() {
        return Err(ExternalRuntimeError::Untrusted);
    }
    let lexical_metadata =
        fs::symlink_metadata(path).map_err(|_| ExternalRuntimeError::Untrusted)?;
    if lexical_metadata.file_type().is_symlink() || !lexical_metadata.is_file() {
        return Err(ExternalRuntimeError::Untrusted);
    }
    let canonical = fs::canonicalize(path).map_err(|_| ExternalRuntimeError::Untrusted)?;
    if canonical != path {
        return Err(ExternalRuntimeError::Untrusted);
    }
    let metadata = canonical
        .metadata()
        .map_err(|_| ExternalRuntimeError::Untrusted)?;
    if !metadata.is_file() || !safe_permissions(&metadata, executable) {
        return Err(ExternalRuntimeError::Untrusted);
    }
    Ok((canonical, runtime_file_identity(&metadata)))
}

fn runtime_file_identity(metadata: &fs::Metadata) -> RuntimeFileIdentity {
    RuntimeFileIdentity {
        #[cfg(unix)]
        device: metadata.dev(),
        #[cfg(unix)]
        inode: metadata.ino(),
        length: metadata.len(),
        modified: metadata.modified().ok(),
    }
}

fn same_runtime_file(left: &RuntimeFileIdentity, right: &RuntimeFileIdentity) -> bool {
    left == right
}

#[cfg(unix)]
fn safe_permissions(metadata: &fs::Metadata, executable: bool) -> bool {
    use std::os::unix::fs::PermissionsExt;

    let mode = metadata.permissions().mode();
    mode & 0o022 == 0 && (!executable || mode & 0o111 != 0)
}

#[cfg(not(unix))]
fn safe_permissions(_metadata: &fs::Metadata, _executable: bool) -> bool {
    true
}

fn hash_runtime(path: &Path) -> Result<String, ExternalRuntimeError> {
    let mut file = fs::File::open(path).map_err(|_| ExternalRuntimeError::Untrusted)?;
    let mut hasher = Sha256::new();
    let mut buffer = [0_u8; 64 * 1024];
    loop {
        let read = file
            .read(&mut buffer)
            .map_err(|_| ExternalRuntimeError::Untrusted)?;
        if read == 0 {
            break;
        }
        hasher.update(&buffer[..read]);
    }
    Ok(format!("{:x}", hasher.finalize()))
}

fn validate_runtime_hash(
    path: &Path,
    expected_identity: &RuntimeFileIdentity,
    expected_hash: &str,
) -> Result<(), ExternalRuntimeError> {
    let actual_hash = hash_runtime(path)?;
    let metadata = path
        .metadata()
        .map_err(|_| ExternalRuntimeError::Untrusted)?;
    if &runtime_file_identity(&metadata) != expected_identity || actual_hash != expected_hash {
        return Err(ExternalRuntimeError::Untrusted);
    }
    Ok(())
}

/// Runs a configured child process with bounded IO and deterministic cleanup.
///
/// The child receives a minimal, fixed environment. stderr is deliberately discarded because
/// runtime output can contain credentials or provider response details.
pub(crate) fn run(
    runtime: &VerifiedExternalRuntime,
    payload: &[u8],
    limits: ExternalRuntimeLimits,
) -> Result<ExternalRuntimeOutput, ExternalRuntimeError> {
    let (executable, identity) = canonical_regular_file(&runtime.executable, true)?;
    if !same_runtime_file(&runtime.identity, &identity) {
        return Err(ExternalRuntimeError::Untrusted);
    }
    validate_runtime_hash(&executable, &identity, &runtime.expected_sha256)?;
    let mut command = Command::new(executable);
    run_command(&mut command, payload, limits)
}

fn run_command(
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
#[path = "external_runtime_tests.rs"]
mod tests;
