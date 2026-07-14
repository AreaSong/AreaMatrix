use std::{
    fs,
    path::{Path, PathBuf},
};

#[test]
fn external_process_management_stays_inside_shared_executor() {
    let src_root = PathBuf::from(env!("CARGO_MANIFEST_DIR")).join("src");
    let mut source_files = Vec::new();
    collect_rust_files(&src_root, &mut source_files);

    let violations = source_files
        .into_iter()
        .filter(|path| {
            path.file_name().and_then(|name| name.to_str()) != Some("external_runtime.rs")
        })
        .flat_map(|path| {
            let source =
                fs::read_to_string(&path).expect("read Core source for runtime governance");
            [".spawn(", ".wait_with_output(", ".output("]
                .into_iter()
                .filter(move |pattern| source.contains(pattern))
                .map(move |pattern| (path.clone(), pattern))
                .collect::<Vec<_>>()
        })
        .collect::<Vec<_>>();

    assert!(
        violations.is_empty(),
        "direct external process management escaped core/src/external_runtime.rs: {violations:?}"
    );
}

#[test]
fn shared_executor_keeps_descendant_cleanup_in_its_process_group_boundary() {
    let source_path = PathBuf::from(env!("CARGO_MANIFEST_DIR")).join("src/external_runtime.rs");
    let source = fs::read_to_string(source_path).expect("read shared external runtime executor");

    for required in [
        "process_group(0)",
        "terminate_process_group",
        "kill(process_group",
    ] {
        assert!(
            source.contains(required),
            "shared external runtime executor lost required process-group cleanup term: {required}"
        );
    }
}

fn collect_rust_files(root: &Path, files: &mut Vec<PathBuf>) {
    for entry in fs::read_dir(root).expect("read Core source directory") {
        let path = entry.expect("read Core source entry").path();
        if path.is_dir() {
            collect_rust_files(&path, files);
        } else if path.extension().and_then(|value| value.to_str()) == Some("rs") {
            files.push(path);
        }
    }
}
