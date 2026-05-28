#![allow(dead_code)]

use std::{
    fs,
    path::{Path, PathBuf},
    sync::{Mutex, MutexGuard},
};

static LOCAL_RUNTIME_LOCK: Mutex<()> = Mutex::new(());
const LOCAL_RUNTIME_ENV: &str = "AREAMATRIX_AI_TAGS_LOCAL_RUNTIME";
const REMOTE_RUNTIME_ENV: &str = "AREAMATRIX_AI_TAGS_REMOTE_RUNTIME";

#[derive(Clone)]
pub struct RuntimeSuggestion {
    slug: String,
    display_name: String,
    confidence: f32,
    reason: String,
}

impl RuntimeSuggestion {
    pub fn new(slug: &str, display_name: &str, confidence: f32, reason: &str) -> Self {
        Self {
            slug: slug.to_owned(),
            display_name: display_name.to_owned(),
            confidence,
            reason: reason.to_owned(),
        }
    }
}

pub struct AiTagsRuntime {
    _lock: MutexGuard<'static, ()>,
    output: tempfile::TempDir,
    payload_path: PathBuf,
    marker_path: Option<PathBuf>,
}

impl AiTagsRuntime {
    pub fn local(suggestions: Vec<RuntimeSuggestion>) -> Self {
        let guard = runtime_guard();
        let output = tempfile::tempdir().expect("create AI tags runtime directory");
        let script_path = output.path().join("ai-tags-runtime.sh");
        let payload_path = output.path().join("payload.json");
        let response = runtime_response(suggestions);
        let script = format!(
            "#!/bin/sh\ncat > \"{}\"\nprintf '%s\\n' '{}'\n",
            payload_path.display(),
            response.replace('\'', "'\\''")
        );
        install_runtime_script(LOCAL_RUNTIME_ENV, &script_path, &script);
        Self {
            _lock: guard,
            output,
            payload_path,
            marker_path: None,
        }
    }

    pub fn remote(suggestions: Vec<RuntimeSuggestion>) -> Self {
        let guard = runtime_guard();
        let output = tempfile::tempdir().expect("create AI tags runtime directory");
        let script_path = output.path().join("ai-tags-remote-runtime.sh");
        let payload_path = output.path().join("payload.json");
        let response = runtime_response(suggestions);
        let script = format!(
            "#!/bin/sh\ncat > \"{}\"\nprintf '%s\\n' '{}'\n",
            payload_path.display(),
            response.replace('\'', "'\\''")
        );
        install_runtime_script(REMOTE_RUNTIME_ENV, &script_path, &script);
        Self {
            _lock: guard,
            output,
            payload_path,
            marker_path: None,
        }
    }

    pub fn probe() -> Self {
        let guard = runtime_guard();
        let output = tempfile::tempdir().expect("create AI tags probe directory");
        let script_path = output.path().join("ai-tags-runtime.sh");
        let payload_path = output.path().join("payload.json");
        let marker_path = output.path().join("invoked");
        let script = format!(
            "#!/bin/sh\ncat > \"{}\"\nprintf invoked > \"{}\"\nprintf '%s\\n' '{{\"suggestions\":[]}}'\n",
            payload_path.display(),
            marker_path.display()
        );
        install_runtime_script(LOCAL_RUNTIME_ENV, &script_path, &script);
        Self {
            _lock: guard,
            output,
            payload_path,
            marker_path: Some(marker_path),
        }
    }

    pub fn captured_payload(&self) -> String {
        fs::read_to_string(&self.payload_path).expect("read captured AI tags payload")
    }

    pub fn was_invoked(&self) -> bool {
        self.marker_path.as_ref().is_some_and(|path| path.exists())
    }
}

impl Drop for AiTagsRuntime {
    fn drop(&mut self) {
        std::env::remove_var(LOCAL_RUNTIME_ENV);
        std::env::remove_var(REMOTE_RUNTIME_ENV);
        let _ = self.output.path();
    }
}

fn runtime_guard() -> MutexGuard<'static, ()> {
    LOCAL_RUNTIME_LOCK
        .lock()
        .unwrap_or_else(|poisoned| poisoned.into_inner())
}

fn runtime_response(suggestions: Vec<RuntimeSuggestion>) -> String {
    serde_json::json!({
        "suggestions": suggestions
            .into_iter()
            .map(|suggestion| serde_json::json!({
                "slug": suggestion.slug,
                "display_name": suggestion.display_name,
                "confidence": suggestion.confidence,
                "reason": suggestion.reason,
                "merge_target_slug": null,
            }))
            .collect::<Vec<_>>(),
    })
    .to_string()
}

fn install_runtime_script(env_name: &str, script_path: &Path, script: &str) {
    fs::write(script_path, script).expect("write AI tags runtime script");
    make_executable(script_path);
    std::env::set_var(env_name, script_path.to_string_lossy().into_owned());
}

fn make_executable(path: &Path) {
    #[cfg(unix)]
    {
        use std::os::unix::fs::PermissionsExt;
        let mut permissions = fs::metadata(path)
            .expect("read script metadata")
            .permissions();
        permissions.set_mode(0o700);
        fs::set_permissions(path, permissions).expect("mark script executable");
    }
}
