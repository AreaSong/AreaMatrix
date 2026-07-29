fn main() {
    println!("cargo:rustc-check-cfg=cfg(areamatrix_system_trash)");

    let target_os = std::env::var("CARGO_CFG_TARGET_OS")
        .expect("Cargo must provide CARGO_CFG_TARGET_OS to build scripts");
    if matches!(
        target_os.as_str(),
        "macos" | "windows" | "linux" | "freebsd"
    ) {
        println!("cargo:rustc-cfg=areamatrix_system_trash");
    }

    println!("cargo:rerun-if-changed=area_matrix.udl");
    println!("cargo:rerun-if-changed=uniffi.toml");
    uniffi::generate_scaffolding("./area_matrix.udl").expect("generate UniFFI scaffolding");
}
