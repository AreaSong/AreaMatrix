#![allow(dead_code)]

use std::{
    fs,
    path::{Path, PathBuf},
    sync::{Mutex, MutexGuard},
};

#[path = "external_runtime_harness.rs"]
mod external_runtime_harness;

use external_runtime_harness::{install_runtime_script, InstalledRuntime};

static LOCAL_RUNTIME_LOCK: Mutex<()> = Mutex::new(());
static REMOTE_RUNTIME_LOCK: Mutex<()> = Mutex::new(());

pub fn path_string(path: &Path) -> String {
    path.to_string_lossy().into_owned()
}

pub struct AiRuntime {
    _lock: MutexGuard<'static, ()>,
    _runtime: InstalledRuntime,
    output: tempfile::TempDir,
    payload_path: PathBuf,
    env_name: &'static str,
}

impl AiRuntime {
    pub fn local(category: &str, confidence: f32, reason: &str) -> Self {
        Self::new(
            &LOCAL_RUNTIME_LOCK,
            "AREAMATRIX_AI_CLASSIFICATION_LOCAL_RUNTIME",
            category,
            confidence,
            reason,
        )
    }

    pub fn remote(category: &str, confidence: f32, reason: &str) -> Self {
        Self::new(
            &REMOTE_RUNTIME_LOCK,
            "AREAMATRIX_AI_CLASSIFICATION_REMOTE_RUNTIME",
            category,
            confidence,
            reason,
        )
    }

    pub fn failing_local() -> Self {
        Self::failing(
            &LOCAL_RUNTIME_LOCK,
            "AREAMATRIX_AI_CLASSIFICATION_LOCAL_RUNTIME",
        )
    }

    fn new(
        lock: &'static Mutex<()>,
        env_name: &'static str,
        category: &str,
        confidence: f32,
        reason: &str,
    ) -> Self {
        let guard = lock.lock().unwrap_or_else(|poisoned| poisoned.into_inner());
        let output = tempfile::tempdir().expect("create AI runtime directory");
        let script_path = output.path().join("ai-classification-runtime.sh");
        let payload_path = output.path().join("payload.json");
        let response = serde_json::json!({
            "category": category,
            "confidence": confidence,
            "reason": reason
        })
        .to_string();
        let script = format!(
            "#!/bin/sh\ncat > \"{}\"\nprintf '%s\\n' '{}'\n",
            payload_path.display(),
            response.replace('\'', "'\\''")
        );
        let runtime = install_runtime_script(
            env_name,
            runtime_capability(env_name),
            &script_path,
            &script,
        );
        Self {
            _lock: guard,
            _runtime: runtime,
            output,
            payload_path,
            env_name,
        }
    }

    fn failing(lock: &'static Mutex<()>, env_name: &'static str) -> Self {
        let guard = lock.lock().unwrap_or_else(|poisoned| poisoned.into_inner());
        let output = tempfile::tempdir().expect("create AI runtime directory");
        let script_path = output.path().join("ai-classification-runtime.sh");
        let payload_path = output.path().join("payload.json");
        let script = format!("#!/bin/sh\ncat > \"{}\"\nexit 42\n", payload_path.display());
        let runtime = install_runtime_script(
            env_name,
            runtime_capability(env_name),
            &script_path,
            &script,
        );
        Self {
            _lock: guard,
            _runtime: runtime,
            output,
            payload_path,
            env_name,
        }
    }

    pub fn captured_payload(&self) -> String {
        fs::read_to_string(&self.payload_path).expect("read captured AI runtime payload")
    }
}

impl Drop for AiRuntime {
    fn drop(&mut self) {
        std::env::remove_var(self.env_name);
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
        let script_path = output.path().join("remote-classification-runtime.sh");
        let marker_path = output.path().join("invoked");
        let script = format!(
            "#!/bin/sh\nprintf invoked > \"{}\"\nexit 33\n",
            marker_path.display()
        );
        let runtime = install_runtime_script(
            "AREAMATRIX_AI_CLASSIFICATION_REMOTE_RUNTIME",
            "ai-classification-remote",
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
        std::env::remove_var("AREAMATRIX_AI_CLASSIFICATION_REMOTE_RUNTIME");
        let _ = self.output.path();
    }
}

fn runtime_capability(env_name: &str) -> &'static str {
    match env_name {
        "AREAMATRIX_AI_CLASSIFICATION_LOCAL_RUNTIME" => "ai-classification-local",
        "AREAMATRIX_AI_CLASSIFICATION_REMOTE_RUNTIME" => "ai-classification-remote",
        _ => panic!("unsupported AI classification runtime environment"),
    }
}
