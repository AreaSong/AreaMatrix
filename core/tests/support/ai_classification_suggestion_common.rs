#![allow(dead_code)]

use std::{
    fs,
    path::{Path, PathBuf},
    sync::{Mutex, MutexGuard},
};

static LOCAL_RUNTIME_LOCK: Mutex<()> = Mutex::new(());
static REMOTE_RUNTIME_LOCK: Mutex<()> = Mutex::new(());

pub fn path_string(path: &Path) -> String {
    path.to_string_lossy().into_owned()
}

pub struct AiRuntime {
    _lock: MutexGuard<'static, ()>,
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
        fs::write(&script_path, script).expect("write AI runtime script");
        make_executable(&script_path);
        std::env::set_var(env_name, script_path.to_string_lossy().into_owned());
        Self {
            _lock: guard,
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
        fs::write(&script_path, script).expect("write failing AI runtime script");
        make_executable(&script_path);
        std::env::set_var(env_name, script_path.to_string_lossy().into_owned());
        Self {
            _lock: guard,
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

fn make_executable(path: &Path) {
    #[cfg(unix)]
    {
        use std::os::unix::fs::PermissionsExt;
        let mut permissions = fs::metadata(path)
            .expect("read AI runtime metadata")
            .permissions();
        permissions.set_mode(0o700);
        fs::set_permissions(path, permissions).expect("mark AI runtime executable");
    }
}
