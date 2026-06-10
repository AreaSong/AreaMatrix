#pragma once

#include <stdint.h>

typedef struct RustBuffer {
    uint64_t capacity;
    uint64_t len;
    uint8_t *_Nullable data;
} RustBuffer;

typedef struct ForeignBytes {
    int32_t len;
    const uint8_t *_Nullable data;
} ForeignBytes;

typedef struct RustCallStatus {
    int8_t code;
    RustBuffer errorBuf;
} RustCallStatus;

RustBuffer uniffi_area_matrix_core_fn_func_get_version(
    RustCallStatus *_Nonnull out_status
);

RustBuffer uniffi_area_matrix_core_fn_func_validate_repo_path(
    RustBuffer repo_path,
    RustCallStatus *_Nonnull out_status
);

RustBuffer uniffi_area_matrix_core_fn_func_load_config(
    RustBuffer repo_path,
    RustCallStatus *_Nonnull out_status
);

void uniffi_area_matrix_core_fn_func_update_config(
    RustBuffer repo_path,
    RustBuffer new_config,
    RustCallStatus *_Nonnull out_status
);

void uniffi_area_matrix_core_fn_func_init_repo(
    RustBuffer repo_path,
    RustBuffer options,
    RustCallStatus *_Nonnull out_status
);

RustBuffer uniffi_area_matrix_core_fn_func_detect_cloud_storage_state(
    RustBuffer repo_path,
    RustCallStatus *_Nonnull out_status
);

RustBuffer uniffi_area_matrix_core_fn_func_list_files(
    RustBuffer repo_path,
    RustBuffer filter,
    RustCallStatus *_Nonnull out_status
);

RustBuffer uniffi_area_matrix_core_fn_func_list_tree_json(
    RustBuffer repo_path,
    RustBuffer locale,
    RustCallStatus *_Nonnull out_status
);

RustBuffer uniffi_area_matrix_core_fn_func_detect_sync_conflicts(
    RustBuffer repo_path,
    RustCallStatus *_Nonnull out_status
);

RustBuffer uniffi_area_matrix_core_fn_func_predict_category(
    RustBuffer repo_path,
    RustBuffer filename,
    RustCallStatus *_Nonnull out_status
);

RustBuffer uniffi_area_matrix_core_fn_func_import_file(
    RustBuffer repo_path,
    RustBuffer source_path,
    RustBuffer options,
    RustCallStatus *_Nonnull out_status
);

RustBuffer uniffi_area_matrix_core_fn_func_preview_batch_delete(
    RustBuffer repo_path,
    RustBuffer file_ids,
    RustBuffer delete_mode,
    RustCallStatus *_Nonnull out_status
);

RustBuffer uniffi_area_matrix_core_fn_func_batch_delete_to_trash(
    RustBuffer repo_path,
    RustBuffer file_ids,
    RustBuffer delete_mode,
    RustBuffer preview_token,
    RustCallStatus *_Nonnull out_status
);

RustBuffer uniffi_area_matrix_core_fn_func_get_file(
    RustBuffer repo_path,
    int64_t file_id,
    RustCallStatus *_Nonnull out_status
);

RustBuffer uniffi_area_matrix_core_fn_func_get_missing_file_state(
    RustBuffer repo_path,
    int64_t file_id,
    RustCallStatus *_Nonnull out_status
);

RustBuffer uniffi_area_matrix_core_fn_func_relink_missing_file(
    RustBuffer repo_path,
    RustBuffer request,
    RustCallStatus *_Nonnull out_status
);

RustBuffer uniffi_area_matrix_core_fn_func_remove_missing_file_record(
    RustBuffer repo_path,
    RustBuffer request,
    RustCallStatus *_Nonnull out_status
);

RustBuffer uniffi_area_matrix_core_fn_func_list_changes(
    RustBuffer repo_path,
    RustBuffer filter,
    RustCallStatus *_Nonnull out_status
);

RustBuffer uniffi_area_matrix_core_fn_func_read_note(
    RustBuffer repo_path,
    int64_t file_id,
    RustCallStatus *_Nonnull out_status
);

RustBuffer uniffi_area_matrix_core_fn_func_inspect_binding_contract(
    RustBuffer request,
    RustCallStatus *_Nonnull out_status
);

RustBuffer uniffi_area_matrix_core_fn_func_get_platform_capabilities(
    RustBuffer platform,
    RustBuffer app_version,
    RustCallStatus *_Nonnull out_status
);

RustBuffer ffi_area_matrix_core_rustbuffer_from_bytes(
    ForeignBytes bytes,
    RustCallStatus *_Nonnull out_status
);

void ffi_area_matrix_core_rustbuffer_free(
    RustBuffer buf,
    RustCallStatus *_Nonnull out_status
);

uint32_t ffi_area_matrix_core_uniffi_contract_version(void);
uint16_t uniffi_area_matrix_core_checksum_func_get_version(void);
uint16_t uniffi_area_matrix_core_checksum_func_validate_repo_path(void);
uint16_t uniffi_area_matrix_core_checksum_func_load_config(void);
uint16_t uniffi_area_matrix_core_checksum_func_update_config(void);
uint16_t uniffi_area_matrix_core_checksum_func_init_repo(void);
uint16_t uniffi_area_matrix_core_checksum_func_detect_cloud_storage_state(void);
uint16_t uniffi_area_matrix_core_checksum_func_list_files(void);
uint16_t uniffi_area_matrix_core_checksum_func_list_tree_json(void);
uint16_t uniffi_area_matrix_core_checksum_func_detect_sync_conflicts(void);
uint16_t uniffi_area_matrix_core_checksum_func_predict_category(void);
uint16_t uniffi_area_matrix_core_checksum_func_import_file(void);
uint16_t uniffi_area_matrix_core_checksum_func_preview_batch_delete(void);
uint16_t uniffi_area_matrix_core_checksum_func_batch_delete_to_trash(void);
uint16_t uniffi_area_matrix_core_checksum_func_get_file(void);
uint16_t uniffi_area_matrix_core_checksum_func_get_missing_file_state(void);
uint16_t uniffi_area_matrix_core_checksum_func_relink_missing_file(void);
uint16_t uniffi_area_matrix_core_checksum_func_remove_missing_file_record(void);
uint16_t uniffi_area_matrix_core_checksum_func_list_changes(void);
uint16_t uniffi_area_matrix_core_checksum_func_read_note(void);
uint16_t uniffi_area_matrix_core_checksum_func_inspect_binding_contract(void);
uint16_t uniffi_area_matrix_core_checksum_func_get_platform_capabilities(void);
