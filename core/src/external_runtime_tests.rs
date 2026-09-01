use std::{
    fs,
    path::Path,
    process::Command,
    sync::{Mutex, MutexGuard},
    thread,
    time::{Duration, Instant},
};

#[cfg(unix)]
use std::os::unix::fs::{symlink, PermissionsExt};

#[cfg(unix)]
use super::kill;
use super::{
    enable_external_runtime_test_harness, resolve, run, run_command, ExternalRuntimeError,
    ExternalRuntimeLimits, ExternalRuntimeTestHarnessGuard,
};

static ADMISSION_TEST_LOCK: Mutex<()> = Mutex::new(());

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
    let output = run_command(&mut command, b"payload", limits(Duration::from_secs(1), 16))
        .expect("runtime should complete");

    assert!(output.status.success());
    assert_eq!(output.stdout, b"ok");
}

#[test]
fn clears_inherited_environment_but_keeps_safe_path() {
    let mut command = shell("printf '%s|%s' \"${AREAMATRIX_TEST_SECRET-unset}\" \"$PATH\"");
    command.env("AREAMATRIX_TEST_SECRET", "must-not-leak");
    let output = run_command(&mut command, b"", limits(Duration::from_secs(1), 256))
        .expect("runtime should complete");
    let rendered = String::from_utf8(output.stdout).expect("output is utf8");

    assert!(rendered.starts_with("unset|/usr/local/bin:/usr/bin:/bin:/usr/sbin:/sbin"));
}

#[test]
fn rejects_output_over_limit_after_draining_pipe() {
    let mut command = shell("printf '0123456789'");
    let error = run_command(&mut command, b"", limits(Duration::from_secs(1), 4))
        .expect_err("oversized output should be rejected");

    assert!(matches!(error, ExternalRuntimeError::StdoutLimitExceeded));
}

#[test]
fn kills_and_reaps_hanging_process() {
    let started = Instant::now();
    let mut command = shell("cat >/dev/null; sleep 30");
    let error = run_command(&mut command, b"", limits(Duration::from_millis(100), 16))
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
    let command = shell(&script);
    let run_handle = thread::spawn(move || {
        let mut command = command;
        run_command(&mut command, b"", limits(Duration::from_secs(3), 16))
    });
    let descendant_pid = wait_until_pid_file(&pid_path);
    let error = run_handle
        .join()
        .expect("runtime worker should not panic")
        .expect_err("runtime process group should time out");

    assert!(matches!(error, ExternalRuntimeError::TimedOut));
    let descendant_pid = descendant_pid.expect("read descendant pid before timeout");
    assert!(wait_until_process_exits(descendant_pid));
}

#[test]
fn preserves_non_zero_exit_status_for_callers() {
    let mut command = shell("exit 42");
    let output = run_command(&mut command, b"", limits(Duration::from_secs(1), 16))
        .expect("process execution should complete");

    assert_eq!(output.status.code(), Some(42));
}

#[test]
fn production_resolve_rejects_configured_runtime_even_with_forged_companion_manifest() {
    let fixture = RuntimeFixture::new("#!/bin/sh\nprintf should-not-run\n", false);
    fs::write(
        fixture.companion_manifest_path(),
        br#"{"sha256":"attacker-controlled","source":"https://attacker.invalid"}"#,
    )
    .expect("write forged companion manifest");

    assert_untrusted(|| fixture.resolve("ai-test"));
}

#[test]
fn unset_runtime_remains_disabled_without_error() {
    let _lock = admission_test_guard();
    let env_name = format!(
        "AREAMATRIX_EXTERNAL_RUNTIME_UNSET_{}",
        uuid::Uuid::new_v4().simple()
    );
    std::env::remove_var(&env_name);

    assert!(resolve(&env_name, "ai-test")
        .expect("unset runtime should stay disabled")
        .is_none());
}

#[test]
fn explicit_test_harness_resolves_and_runs_runtime() {
    let fixture = RuntimeFixture::new("#!/bin/sh\ncat >/dev/null\nprintf ok\n", true);
    let runtime = fixture.resolve("ai-test").expect("runtime should resolve");

    let output = run(&runtime, b"payload", limits(Duration::from_secs(1), 16))
        .expect("verified runtime should run");

    assert!(output.status.success());
    assert_eq!(output.stdout, b"ok");
}

#[test]
fn rejects_unapproved_test_runtime_identity_and_license() {
    for (field, value) in [
        ("provider", serde_json::json!("unknown-provider")),
        ("endpoint", serde_json::json!("https://attacker.invalid")),
        ("privacy_classification", serde_json::json!("unrestricted")),
        ("license", serde_json::json!("HPND")),
        (
            "source",
            serde_json::json!("https://attacker.invalid/runtime"),
        ),
    ] {
        let fixture = RuntimeFixture::new("#!/bin/sh\nexit 0\n", true);
        fixture.mutate_manifest(field, value);
        assert_untrusted(|| fixture.resolve("ai-test"));
    }
}

#[test]
fn rejects_relative_runtime_path() {
    let fixture = RuntimeFixture::new("#!/bin/sh\nexit 0\n", true);
    fixture.set_runtime_path("relative-runtime");

    assert_untrusted(|| fixture.resolve("ai-test"));
}

#[cfg(unix)]
#[test]
fn rejects_symlink_runtime() {
    let fixture = RuntimeFixture::new("#!/bin/sh\nexit 0\n", true);
    let linked_runtime = fixture.directory.path().join("linked-runtime.sh");
    symlink(&fixture.script_path, &linked_runtime).expect("create runtime symlink");
    fixture.set_runtime_path(&linked_runtime);
    assert_untrusted(|| fixture.resolve("ai-test"));
}

#[test]
fn rejects_directory_runtime() {
    let fixture = RuntimeFixture::new("#!/bin/sh\nexit 0\n", true);
    fixture.set_runtime_path(fixture.directory.path());

    assert_untrusted(|| fixture.resolve("ai-test"));
}

#[cfg(unix)]
#[test]
fn rejects_group_or_world_writable_runtime() {
    let fixture = RuntimeFixture::new("#!/bin/sh\nexit 0\n", true);
    make_mode(&fixture.script_path, 0o720);
    assert_untrusted(|| fixture.resolve("ai-test"));
}

#[test]
fn rejects_runtime_replaced_after_resolution() {
    let fixture = RuntimeFixture::new("#!/bin/sh\nprintf original\n", true);
    let runtime = fixture.resolve("ai-test").expect("runtime should resolve");
    fs::write(&fixture.script_path, "#!/bin/sh\nprintf replacement\n").expect("replace runtime");
    make_executable(&fixture.script_path);

    let error = run(&runtime, b"", limits(Duration::from_secs(1), 16))
        .expect_err("replacement must be rejected before spawn");

    assert!(matches!(error, ExternalRuntimeError::Untrusted));
}

fn shell(script: &str) -> Command {
    let mut command = Command::new("sh");
    command.arg("-c").arg(script);
    command
}

struct RuntimeFixture {
    _lock: MutexGuard<'static, ()>,
    _harness: Option<ExternalRuntimeTestHarnessGuard>,
    directory: tempfile::TempDir,
    script_path: std::path::PathBuf,
    env_name: String,
}

impl RuntimeFixture {
    fn new(script: &str, enable_harness: bool) -> Self {
        let lock = admission_test_guard();
        let directory = tempfile::tempdir().expect("create runtime fixture directory");
        let configured_path = directory.path().join("runtime.sh");
        fs::write(&configured_path, script).expect("write runtime script");
        let script_path = fs::canonicalize(&configured_path).expect("canonicalize runtime path");
        make_executable(&script_path);
        let manifest = serde_json::json!({
            "schema_version": super::RUNTIME_MANIFEST_SCHEMA_VERSION,
            "capability": "ai-test",
            "version": super::RUNTIME_PROTOCOL_VERSION,
            "executable": script_path.to_string_lossy(),
            "platforms": [super::current_platform()],
            "sha256": super::hash_runtime(&script_path).expect("hash runtime fixture"),
            "provider": super::TEST_RUNTIME_PROVIDER,
            "endpoint": super::TEST_RUNTIME_ENDPOINT,
            "privacy_classification": super::TEST_RUNTIME_PRIVACY_CLASSIFICATION,
            "license": "MIT",
            "source": super::TEST_RUNTIME_SOURCE
        });
        let manifest_path = super::companion_manifest_path(&script_path);
        fs::write(
            &manifest_path,
            serde_json::to_vec(&manifest).expect("serialize runtime fixture manifest"),
        )
        .expect("write runtime fixture manifest");
        #[cfg(unix)]
        make_mode(&manifest_path, 0o600);
        let env_name = format!(
            "AREAMATRIX_EXTERNAL_RUNTIME_TEST_{}",
            uuid::Uuid::new_v4().simple()
        );
        std::env::set_var(&env_name, &script_path);
        Self {
            _lock: lock,
            _harness: enable_harness.then(enable_external_runtime_test_harness),
            directory,
            script_path,
            env_name,
        }
    }

    fn resolve(
        &self,
        capability: &str,
    ) -> Result<super::VerifiedExternalRuntime, ExternalRuntimeError> {
        resolve(&self.env_name, capability)?.ok_or(ExternalRuntimeError::Untrusted)
    }

    fn set_runtime_path(&self, path: impl AsRef<Path>) {
        std::env::set_var(&self.env_name, path.as_ref());
    }

    fn companion_manifest_path(&self) -> std::path::PathBuf {
        let mut path = self.script_path.as_os_str().to_os_string();
        path.push(".manifest.json");
        path.into()
    }

    fn mutate_manifest(&self, field: &str, value: serde_json::Value) {
        let path = self.companion_manifest_path();
        let mut manifest: serde_json::Value =
            serde_json::from_slice(&fs::read(&path).expect("read runtime fixture manifest"))
                .expect("parse runtime fixture manifest");
        manifest[field] = value;
        fs::write(
            path,
            serde_json::to_vec(&manifest).expect("serialize mutated runtime fixture manifest"),
        )
        .expect("write mutated runtime fixture manifest");
    }
}

impl Drop for RuntimeFixture {
    fn drop(&mut self) {
        std::env::remove_var(&self.env_name);
    }
}

fn assert_untrusted(
    action: impl FnOnce() -> Result<super::VerifiedExternalRuntime, ExternalRuntimeError>,
) {
    let error = action().expect_err("untrusted runtime must be rejected");
    assert!(matches!(error, ExternalRuntimeError::Untrusted));
}

fn make_executable(path: &Path) {
    #[cfg(unix)]
    make_mode(path, 0o700);
}

fn admission_test_guard() -> MutexGuard<'static, ()> {
    ADMISSION_TEST_LOCK
        .lock()
        .unwrap_or_else(|poisoned| poisoned.into_inner())
}

#[cfg(unix)]
fn make_mode(path: &Path, mode: u32) {
    let mut permissions = fs::metadata(path)
        .expect("read fixture metadata")
        .permissions();
    permissions.set_mode(mode);
    fs::set_permissions(path, permissions).expect("set fixture permissions");
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
fn wait_until_pid_file(path: &Path) -> Option<i32> {
    let deadline = Instant::now() + Duration::from_secs(2);
    while Instant::now() < deadline {
        if let Ok(contents) = fs::read_to_string(path) {
            if let Ok(pid) = contents.trim().parse::<i32>() {
                return Some(pid);
            }
        }
        thread::sleep(Duration::from_millis(10));
    }
    None
}

#[cfg(unix)]
fn shell_quote(path: &Path) -> String {
    format!("'{}'", path.to_string_lossy().replace('\'', "'\\''"))
}
