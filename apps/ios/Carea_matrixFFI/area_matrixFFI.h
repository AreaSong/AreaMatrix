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

RustBuffer uniffi_area_matrix_core_fn_func_validate_repo_path(
    RustBuffer repo_path,
    RustCallStatus *_Nonnull out_status
);

RustBuffer uniffi_area_matrix_core_fn_func_load_config(
    RustBuffer repo_path,
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

RustBuffer ffi_area_matrix_core_rustbuffer_from_bytes(
    ForeignBytes bytes,
    RustCallStatus *_Nonnull out_status
);

void ffi_area_matrix_core_rustbuffer_free(
    RustBuffer buf,
    RustCallStatus *_Nonnull out_status
);

uint32_t ffi_area_matrix_core_uniffi_contract_version(void);
uint16_t uniffi_area_matrix_core_checksum_func_validate_repo_path(void);
uint16_t uniffi_area_matrix_core_checksum_func_load_config(void);
uint16_t uniffi_area_matrix_core_checksum_func_init_repo(void);
uint16_t uniffi_area_matrix_core_checksum_func_detect_cloud_storage_state(void);
uint16_t uniffi_area_matrix_core_checksum_func_list_files(void);
uint16_t uniffi_area_matrix_core_checksum_func_list_tree_json(void);
