#[test]
fn core_crate_links_into_integration_tests() {
    let _version_reader: fn() -> String = area_matrix_core::get_version;
}
