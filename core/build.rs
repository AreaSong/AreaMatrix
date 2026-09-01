fn main() {
    println!("cargo:rerun-if-changed=area_matrix.udl");
    println!("cargo:rerun-if-changed=uniffi.toml");
    uniffi::generate_scaffolding("./area_matrix.udl").expect("generate UniFFI scaffolding");
}
