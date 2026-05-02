use std::{ffi::OsString, fs, path::Path, sync::Mutex};

static HOME_ENV_LOCK: Mutex<()> = Mutex::new(());

struct HomeOverride {
    previous: Option<OsString>,
}

impl HomeOverride {
    fn install(home: &Path) -> Self {
        let previous = std::env::var_os("HOME");
        std::env::set_var("HOME", home);
        Self { previous }
    }
}

impl Drop for HomeOverride {
    fn drop(&mut self) {
        match &self.previous {
            Some(value) => std::env::set_var("HOME", value),
            None => std::env::remove_var("HOME"),
        }
    }
}

pub(crate) fn with_test_system_trash<R>(run: impl FnOnce(&Path) -> R) -> R {
    let _guard = HOME_ENV_LOCK.lock().expect("lock HOME override");
    let home = tempfile::tempdir().expect("create temporary HOME");
    let trash_dir = home.path().join(".Trash");
    fs::create_dir(&trash_dir).expect("create temporary system Trash");
    let _home = HomeOverride::install(home.path());
    run(&trash_dir)
}
