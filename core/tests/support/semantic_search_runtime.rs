#![allow(dead_code)]

use std::{
    fs,
    path::PathBuf,
    sync::{Mutex, MutexGuard},
};

#[path = "external_runtime_harness.rs"]
mod external_runtime_harness;

use external_runtime_harness::{install_runtime_script, InstalledRuntime};

static REMOTE_RUNTIME_LOCK: Mutex<()> = Mutex::new(());

pub const REMOTE_RUNTIME_ENV: &str = "AREAMATRIX_AI_SEMANTIC_REMOTE_RUNTIME";

pub struct SemanticAiRuntime {
    _lock: MutexGuard<'static, ()>,
    _runtime: InstalledRuntime,
    output: tempfile::TempDir,
    payload_path: PathBuf,
}

impl SemanticAiRuntime {
    pub fn remote_search(file_id: i64, relevance: f32, reason: &str) -> Self {
        let response = serde_json::json!({
            "matches": [{
                "file_id": file_id,
                "relevance": relevance,
                "reason": reason
            }]
        })
        .to_string();
        Self::new(response)
    }

    pub fn remote_build() -> Self {
        Self::new(r#"{"ok":true}"#.to_owned())
    }

    pub fn rate_limited() -> Self {
        Self::failing_with_code(429, r#"{"error":"rate_limited"}"#)
    }

    pub fn timeout() -> Self {
        Self::sleeping()
    }

    fn new(response: String) -> Self {
        let guard = REMOTE_RUNTIME_LOCK
            .lock()
            .unwrap_or_else(|poisoned| poisoned.into_inner());
        let output = tempfile::tempdir().expect("create semantic runtime directory");
        let script_path = output.path().join("semantic-remote-runtime.sh");
        let payload_path = output.path().join("payload.json");
        let script = format!(
            "#!/bin/sh\ncat > \"{}\"\nprintf '%s\\n' '{}'\n",
            payload_path.display(),
            response.replace('\'', "'\\''")
        );
        let runtime = install_runtime_script(
            REMOTE_RUNTIME_ENV,
            "ai-semantic-remote",
            &script_path,
            &script,
        );
        Self {
            _lock: guard,
            _runtime: runtime,
            output,
            payload_path,
        }
    }

    fn failing_with_code(code: i32, response: &str) -> Self {
        let guard = REMOTE_RUNTIME_LOCK
            .lock()
            .unwrap_or_else(|poisoned| poisoned.into_inner());
        let output = tempfile::tempdir().expect("create semantic runtime directory");
        let script_path = output.path().join("semantic-remote-runtime.sh");
        let payload_path = output.path().join("payload.json");
        let script = format!(
            "#!/bin/sh\ncat > \"{}\"\nprintf '%s\\n' '{}'\nexit {code}\n",
            payload_path.display(),
            response.replace('\'', "'\\''")
        );
        let runtime = install_runtime_script(
            REMOTE_RUNTIME_ENV,
            "ai-semantic-remote",
            &script_path,
            &script,
        );
        Self {
            _lock: guard,
            _runtime: runtime,
            output,
            payload_path,
        }
    }

    fn sleeping() -> Self {
        let guard = REMOTE_RUNTIME_LOCK
            .lock()
            .unwrap_or_else(|poisoned| poisoned.into_inner());
        let output = tempfile::tempdir().expect("create semantic runtime directory");
        let script_path = output.path().join("semantic-remote-runtime.sh");
        let payload_path = output.path().join("payload.json");
        let script = format!(
            "#!/bin/sh\ncat > \"{}\"\nsleep 35\n",
            payload_path.display()
        );
        let runtime = install_runtime_script(
            REMOTE_RUNTIME_ENV,
            "ai-semantic-remote",
            &script_path,
            &script,
        );
        Self {
            _lock: guard,
            _runtime: runtime,
            output,
            payload_path,
        }
    }

    pub fn captured_payload(&self) -> String {
        fs::read_to_string(&self.payload_path).expect("read captured semantic runtime payload")
    }
}

impl Drop for SemanticAiRuntime {
    fn drop(&mut self) {
        std::env::remove_var(REMOTE_RUNTIME_ENV);
        let _ = self.output.path();
    }
}

pub struct RemoteRuntimeProbe {
    _guard: MutexGuard<'static, ()>,
    _runtime: InstalledRuntime,
    output: tempfile::TempDir,
    marker_path: PathBuf,
}

impl RemoteRuntimeProbe {
    pub fn new() -> Self {
        let guard = REMOTE_RUNTIME_LOCK
            .lock()
            .unwrap_or_else(|poisoned| poisoned.into_inner());
        let output = tempfile::tempdir().expect("create remote runtime probe directory");
        let script_path = output.path().join("semantic-remote-probe.sh");
        let marker_path = output.path().join("invoked");
        let script = format!(
            "#!/bin/sh\nprintf invoked > \"{}\"\nexit 33\n",
            marker_path.display()
        );
        let runtime = install_runtime_script(
            REMOTE_RUNTIME_ENV,
            "ai-semantic-remote",
            &script_path,
            &script,
        );
        Self {
            _guard: guard,
            _runtime: runtime,
            output,
            marker_path,
        }
    }

    pub fn was_invoked(&self) -> bool {
        self.marker_path.exists()
    }
}

impl Drop for RemoteRuntimeProbe {
    fn drop(&mut self) {
        std::env::remove_var(REMOTE_RUNTIME_ENV);
        let _ = self.output.path();
    }
}
