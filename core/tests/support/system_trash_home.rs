use std::{ffi::OsString, fs, path::Path, sync::Mutex};

static HOME_ENV_LOCK: Mutex<()> = Mutex::new(());
const FORCE_USER_TRASH_ENV: &str = "AREAMATRIX_TEST_FORCE_USER_TRASH";

struct HomeOverride {
    previous: Option<OsString>,
    previous_force_user_trash: Option<OsString>,
}

impl HomeOverride {
    fn install(home: &Path) -> Self {
        let previous = std::env::var_os("HOME");
        let previous_force_user_trash = std::env::var_os(FORCE_USER_TRASH_ENV);
        std::env::set_var("HOME", home);
        std::env::set_var(FORCE_USER_TRASH_ENV, "1");
        Self {
            previous,
            previous_force_user_trash,
        }
    }
}

impl Drop for HomeOverride {
    fn drop(&mut self) {
        match &self.previous {
            Some(value) => std::env::set_var("HOME", value),
            None => std::env::remove_var("HOME"),
        }
        match &self.previous_force_user_trash {
            Some(value) => std::env::set_var(FORCE_USER_TRASH_ENV, value),
            None => std::env::remove_var(FORCE_USER_TRASH_ENV),
        }
    }
}

pub(crate) fn with_test_system_trash<R>(run: impl FnOnce(&Path) -> R) -> R {
    let _guard = HOME_ENV_LOCK
        .lock()
        .unwrap_or_else(|poisoned| poisoned.into_inner());
    let home = tempfile::tempdir().expect("create temporary HOME");
    let trash_dir = home.path().join(".Trash");
    fs::create_dir(&trash_dir).expect("create temporary system Trash");
    let _home = HomeOverride::install(home.path());
    run(&trash_dir)
}
