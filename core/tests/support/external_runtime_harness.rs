#![allow(dead_code)]

use std::{ffi::OsString, fs, path::Path};

use sha2::{Digest, Sha256};

pub struct InstalledRuntime {
    _harness: area_matrix_core::ExternalRuntimeTestHarnessGuard,
    env_name: &'static str,
}

impl Drop for InstalledRuntime {
    fn drop(&mut self) {
        std::env::remove_var(self.env_name);
    }
}

pub fn install_runtime_script(
    env_name: &'static str,
    capability: &str,
    script_path: &Path,
    script: &str,
) -> InstalledRuntime {
    fs::write(script_path, script).expect("write external runtime script");
    set_mode(script_path, 0o700);
    let executable = fs::canonicalize(script_path).expect("canonicalize external runtime script");
    let sha256 = format!(
        "{:x}",
        Sha256::digest(fs::read(&executable).expect("read external runtime script"))
    );
    let manifest = serde_json::json!({
        "schema_version": 1,
        "capability": capability,
        "version": "1",
        "executable": executable.to_string_lossy(),
        "platforms": [format!("{}-{}", std::env::consts::OS, std::env::consts::ARCH)],
        "sha256": sha256,
        "provider": "areamatrix-test-fixture",
        "endpoint": "https://example.invalid/areamatrix-test-endpoint",
        "privacy_classification": "synthetic-test-data-only",
        "license": "MIT",
        "source": "https://example.invalid/areamatrix-test-runtime"
    });
    let manifest_path = companion_manifest_path(&executable);
    fs::write(
        &manifest_path,
        serde_json::to_vec(&manifest).expect("serialize external runtime manifest"),
    )
    .expect("write external runtime manifest");
    set_mode(&manifest_path, 0o600);
    let harness = area_matrix_core::enable_external_runtime_test_harness();
    std::env::set_var(env_name, executable);
    InstalledRuntime {
        _harness: harness,
        env_name,
    }
}

fn companion_manifest_path(executable: &Path) -> std::path::PathBuf {
    let mut path = OsString::from(executable.as_os_str());
    path.push(".manifest.json");
    path.into()
}

fn set_mode(path: &Path, mode: u32) {
    #[cfg(unix)]
    {
        use std::os::unix::fs::PermissionsExt;

        let mut permissions = fs::metadata(path)
            .expect("read external runtime metadata")
            .permissions();
        permissions.set_mode(mode);
        fs::set_permissions(path, permissions).expect("set external runtime permissions");
    }

    #[cfg(not(unix))]
    let _ = (path, mode);
}
