import Carea_matrixFFI
import Foundation

struct SyncConflictEntryCoreFFIClient {
    func detectSyncConflicts(repoPath: String) throws -> [SyncConflictEntryConflict] {
        try ensureCurrentContract()
        let path = try FFIWriter.lowerString(repoPath)
        let result = try rustCallWithCoreError {
            uniffi_area_matrix_core_fn_func_detect_sync_conflicts(path, $0)
        }
        return try FFIReader.liftConflicts(result)
    }

    private func ensureCurrentContract() throws {
        guard ffi_area_matrix_core_uniffi_contract_version() == 26,
              uniffi_area_matrix_core_checksum_func_detect_sync_conflicts() == 31524 else {
            throw SyncConflictEntryError.unavailable("AreaMatrix Core binding contract mismatch.")
        }
    }
}

private enum SyncConflictEntryCoreFFIError: LocalizedError {
    case bufferOverflow
    case unexpectedStatus(Int8)
    case unexpectedEnumCase(Int64)
    case unexpectedOptionalTag(Int8)
    case incompleteData
    case rustPanic(String)

    var errorDescription: String? {
        switch self {
        case .bufferOverflow:
            "Core response buffer ended unexpectedly."
        case let .unexpectedStatus(code):
            "Unexpected Core call status: \(code)."
        case let .unexpectedEnumCase(value):
            "Unexpected Core enum value: \(value)."
        case let .unexpectedOptionalTag(tag):
            "Unexpected Core optional tag: \(tag)."
        case .incompleteData:
            "Core response buffer contained trailing data."
        case let .rustPanic(message):
            message
        }
    }
}

private func rustCallWithCoreError(_ callback: (UnsafeMutablePointer<RustCallStatus>) -> RustBuffer)
    throws -> RustBuffer {
    var status = RustCallStatus()
    let result = callback(&status)
    try checkStatus(status)
    return result
}

private func checkStatus(_ status: RustCallStatus) throws {
    switch status.code {
    case 0:
        return
    case 1:
        throw try FFIReader.liftCoreError(status.errorBuf)
    case 2:
        if status.errorBuf.len > 0 {
            throw try SyncConflictEntryCoreFFIError.rustPanic(FFIReader.liftString(status.errorBuf))
        }
        try FFIReader.deallocate(status.errorBuf)
        throw SyncConflictEntryCoreFFIError.rustPanic("Rust panic")
    default:
        try FFIReader.deallocate(status.errorBuf)
        throw SyncConflictEntryCoreFFIError.unexpectedStatus(status.code)
    }
}

private enum FFIWriter {
    static func lowerString(_ value: String) throws -> RustBuffer {
        try value.utf8CString.withUnsafeBufferPointer { int8Pointer in
            try int8Pointer.withMemoryRebound(to: UInt8.self) { pointer in
                let bytes = UnsafeBufferPointer(rebasing: pointer.prefix(upTo: pointer.count - 1))
                return try lowerBytes(bytes)
            }
        }
    }

    private static func lowerBytes(_ bytes: UnsafeBufferPointer<UInt8>) throws -> RustBuffer {
        var status = RustCallStatus()
        let buffer = ffi_area_matrix_core_rustbuffer_from_bytes(
            ForeignBytes(len: Int32(bytes.count), data: bytes.baseAddress),
            &status
        )
        guard status.code == 0 else {
            throw SyncConflictEntryCoreFFIError.unexpectedStatus(status.code)
        }
        return buffer
    }
}

private enum FFIReader {
    static func liftConflicts(_ buffer: RustBuffer) throws -> [SyncConflictEntryConflict] {
        var reader = Reader(buffer: buffer)
        let conflicts = try reader.readConflicts()
        try reader.finish()
        return conflicts
    }

    static func liftCoreError(_ buffer: RustBuffer) throws -> SyncConflictEntryError {
        var reader = Reader(buffer: buffer)
        let variant = try reader.readInt32()
        let error: SyncConflictEntryError = switch variant {
        case 1:
            try .io(reader.readString())
        case 2:
            try .database(reader.readString())
        case 6:
            try .conflict(reader.readString())
        default:
            try .unavailable(reader.readCoreErrorPayload(variant: variant))
        }
        try reader.finish()
        return error
    }

    static func liftString(_ buffer: RustBuffer) throws -> String {
        defer { try? deallocate(buffer) }
        guard let data = buffer.data else { return "" }
        return String(decoding: UnsafeBufferPointer(start: data, count: Int(buffer.len)), as: UTF8.self)
    }

    static func deallocate(_ buffer: RustBuffer) throws {
        var status = RustCallStatus()
        ffi_area_matrix_core_rustbuffer_free(buffer, &status)
        guard status.code == 0 else {
            throw SyncConflictEntryCoreFFIError.unexpectedStatus(status.code)
        }
    }

    private struct Reader {
        private let buffer: RustBuffer
        private let data: Data
        private var offset: Data.Index = 0

        init(buffer: RustBuffer) {
            self.buffer = buffer
            if let pointer = buffer.data {
                data = Data(bytes: pointer, count: Int(buffer.len))
            } else {
                data = Data()
            }
        }

        mutating func finish() throws {
            defer { try? FFIReader.deallocate(buffer) }
            guard offset == data.count else {
                throw SyncConflictEntryCoreFFIError.incompleteData
            }
        }

        mutating func readConflicts() throws -> [SyncConflictEntryConflict] {
            let count = try Int(readInt32())
            guard count >= 0 else {
                throw SyncConflictEntryCoreFFIError.bufferOverflow
            }
            var conflicts: [SyncConflictEntryConflict] = []
            conflicts.reserveCapacity(count)
            for _ in 0 ..< count {
                try conflicts.append(readConflict())
            }
            return conflicts
        }

        mutating func readString() throws -> String {
            let count = try Int(readInt32())
            guard count >= 0, data.count >= offset + count else {
                throw SyncConflictEntryCoreFFIError.bufferOverflow
            }
            defer { offset += count }
            return String(decoding: data[offset ..< offset + count], as: UTF8.self)
        }

        mutating func readInt32() throws -> Int32 {
            guard data.count >= offset + 4 else {
                throw SyncConflictEntryCoreFFIError.bufferOverflow
            }
            defer { offset += 4 }
            var value: Int32 = 0
            _ = withUnsafeMutableBytes(of: &value) { data.copyBytes(to: $0, from: offset ..< offset + 4) }
            return value.bigEndian
        }

        private mutating func readConflict() throws -> SyncConflictEntryConflict {
            try SyncConflictEntryConflict(
                conflictID: readString(),
                conflictType: readConflictType(),
                severity: readSeverity(),
                status: readStatus(),
                primaryPath: readString(),
                affectedFiles: readAffectedFiles(),
                versionCount: readInt64(),
                sourceProvider: readOptionalString(),
                detectedAt: readOptionalInt64(),
                summary: readOptionalString()
            )
        }

        private mutating func readAffectedFiles() throws -> [SyncConflictEntryAffectedFile] {
            let count = try Int(readInt32())
            guard count >= 0 else {
                throw SyncConflictEntryCoreFFIError.bufferOverflow
            }
            var files: [SyncConflictEntryAffectedFile] = []
            files.reserveCapacity(count)
            for _ in 0 ..< count {
                try files.append(readAffectedFile())
            }
            return files
        }

        private mutating func readAffectedFile() throws -> SyncConflictEntryAffectedFile {
            try SyncConflictEntryAffectedFile(
                path: readString(),
                fileID: readOptionalInt64(),
                role: readFileRole(),
                sizeBytes: readOptionalInt64(),
                modifiedAt: readOptionalInt64(),
                hashSha256: readOptionalString(),
                sourcePlatform: readOptionalString()
            )
        }

        private mutating func readStatus() throws -> SyncConflictEntryStatus {
            switch try readInt32() {
            case 1:
                .needsReview
            case 2:
                .resolved
            case let value:
                throw SyncConflictEntryCoreFFIError.unexpectedEnumCase(Int64(value))
            }
        }

        private mutating func readConflictType() throws -> SyncConflictEntryType {
            switch try readInt32() {
            case 1:
                .sameNameDifferentContent
            case 2:
                .concurrentModification
            case 3:
                .metadataMismatch
            case 4:
                .missingVersion
            case 5:
                .unknown
            case let value:
                throw SyncConflictEntryCoreFFIError.unexpectedEnumCase(Int64(value))
            }
        }

        private mutating func readSeverity() throws -> SyncConflictEntrySeverity {
            switch try readInt32() {
            case 1:
                .low
            case 2:
                .medium
            case 3:
                .high
            case let value:
                throw SyncConflictEntryCoreFFIError.unexpectedEnumCase(Int64(value))
            }
        }

        private mutating func readFileRole() throws -> SyncConflictEntryFileRole {
            switch try readInt32() {
            case 1:
                .existing
            case 2:
                .incoming
            case 3:
                .conflictCopy
            case 4:
                .missing
            case 5:
                .unknown
            case let value:
                throw SyncConflictEntryCoreFFIError.unexpectedEnumCase(Int64(value))
            }
        }

        private mutating func readOptionalString() throws -> String? {
            let tag = try readInt8()
            switch tag {
            case 0:
                return nil
            case 1:
                return try readString()
            default:
                throw SyncConflictEntryCoreFFIError.unexpectedOptionalTag(tag)
            }
        }

        private mutating func readOptionalInt64() throws -> Int64? {
            let tag = try readInt8()
            switch tag {
            case 0:
                return nil
            case 1:
                return try readInt64()
            default:
                throw SyncConflictEntryCoreFFIError.unexpectedOptionalTag(tag)
            }
        }

        mutating func readCoreErrorPayload(variant: Int32) throws -> String {
            switch variant {
            case 1, 2, 3, 4, 5, 6, 7, 8, 9, 10, 11, 12, 13, 14, 15:
                return try readString()
            default:
                throw SyncConflictEntryCoreFFIError.unexpectedEnumCase(Int64(variant))
            }
        }

        private mutating func readInt8() throws -> Int8 {
            guard data.count >= offset + 1 else {
                throw SyncConflictEntryCoreFFIError.bufferOverflow
            }
            defer { offset += 1 }
            return Int8(bitPattern: data[offset])
        }

        private mutating func readInt64() throws -> Int64 {
            guard data.count >= offset + 8 else {
                throw SyncConflictEntryCoreFFIError.bufferOverflow
            }
            defer { offset += 8 }
            var value: Int64 = 0
            _ = withUnsafeMutableBytes(of: &value) { data.copyBytes(to: $0, from: offset ..< offset + 8) }
            return value.bigEndian
        }
    }
}
