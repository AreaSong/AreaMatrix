import Carea_matrixFFI
import Foundation

struct MobileFileDetailCoreFFIClient {
    func getFile(repoPath: String, fileID: Int64) throws -> MobileFileDetailMetadata {
        try ensureCurrentContract()
        let path = try FFIWriter.lowerString(repoPath)
        let result = try rustCallWithCoreError {
            uniffi_area_matrix_core_fn_func_get_file(path, fileID, $0)
        }
        return try FFIReader.liftMetadata(result)
    }

    func listChanges(
        repoPath: String,
        filter: MobileFileDetailChangeFilter
    ) throws -> [MobileFileChangeLogEntry] {
        try ensureCurrentContract()
        let path = try FFIWriter.lowerString(repoPath)
        let loweredFilter = try FFIWriter.lowerChangeFilter(filter)
        let result = try rustCallWithCoreError {
            uniffi_area_matrix_core_fn_func_list_changes(path, loweredFilter, $0)
        }
        return try FFIReader.liftChanges(result)
    }

    func readNote(repoPath: String, fileID: Int64) throws -> String? {
        try ensureCurrentContract()
        let path = try FFIWriter.lowerString(repoPath)
        let result = try rustCallWithCoreError {
            uniffi_area_matrix_core_fn_func_read_note(path, fileID, $0)
        }
        return try FFIReader.liftOptionalString(result)
    }

    private func ensureCurrentContract() throws {
        guard ffi_area_matrix_core_uniffi_contract_version() == 26,
              uniffi_area_matrix_core_checksum_func_get_file() == 6132,
              uniffi_area_matrix_core_checksum_func_list_changes() == 62602,
              uniffi_area_matrix_core_checksum_func_read_note() == 62313 else {
            throw MobileFileDetailError.unavailable("AreaMatrix Core binding contract mismatch.")
        }
    }
}

private enum MobileFileDetailCoreFFIError: LocalizedError {
    case bufferOverflow
    case unexpectedStatus(Int8)
    case unexpectedEnumCase(Int64)
    case unexpectedOptionalTag(Int8)
    case incompleteData
    case invalidStringEncoding
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
        case .invalidStringEncoding:
            "Core response buffer contained invalid UTF-8."
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
            throw try MobileFileDetailCoreFFIError.rustPanic(FFIReader.liftString(status.errorBuf))
        }
        try FFIReader.deallocate(status.errorBuf)
        throw MobileFileDetailCoreFFIError.rustPanic("Rust panic")
    default:
        try FFIReader.deallocate(status.errorBuf)
        throw MobileFileDetailCoreFFIError.unexpectedStatus(status.code)
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

    static func lowerChangeFilter(_ filter: MobileFileDetailChangeFilter) throws -> RustBuffer {
        var bytes: [UInt8] = []
        writeOptionalInt64(filter.fileID, into: &bytes)
        writeOptionalString(filter.category, into: &bytes)
        writeOptionalString(filter.action, into: &bytes)
        writeOptionalInt64(filter.since, into: &bytes)
        writeOptionalInt64(filter.until, into: &bytes)
        writeInt64(filter.limit, into: &bytes)
        writeInt64(filter.offset, into: &bytes)
        return try bytes.withUnsafeBufferPointer { try lowerBytes($0) }
    }

    private static func lowerBytes(_ bytes: UnsafeBufferPointer<UInt8>) throws -> RustBuffer {
        var status = RustCallStatus()
        let buffer = ffi_area_matrix_core_rustbuffer_from_bytes(
            ForeignBytes(len: Int32(bytes.count), data: bytes.baseAddress),
            &status
        )
        guard status.code == 0 else {
            throw MobileFileDetailCoreFFIError.unexpectedStatus(status.code)
        }
        return buffer
    }

    private static func writeOptionalString(_ value: String?, into bytes: inout [UInt8]) {
        guard let value else {
            writeInt8(0, into: &bytes)
            return
        }
        writeInt8(1, into: &bytes)
        writeString(value, into: &bytes)
    }

    private static func writeOptionalInt64(_ value: Int64?, into bytes: inout [UInt8]) {
        guard let value else {
            writeInt8(0, into: &bytes)
            return
        }
        writeInt8(1, into: &bytes)
        writeInt64(value, into: &bytes)
    }

    private static func writeString(_ value: String, into bytes: inout [UInt8]) {
        let data = Array(value.utf8)
        writeInt32(Int32(data.count), into: &bytes)
        bytes.append(contentsOf: data)
    }

    private static func writeInt8(_ value: Int8, into bytes: inout [UInt8]) {
        bytes.append(UInt8(bitPattern: value))
    }

    private static func writeInt32(_ value: Int32, into bytes: inout [UInt8]) {
        var bigEndian = value.bigEndian
        withUnsafeBytes(of: &bigEndian) { bytes.append(contentsOf: $0) }
    }

    private static func writeInt64(_ value: Int64, into bytes: inout [UInt8]) {
        var bigEndian = value.bigEndian
        withUnsafeBytes(of: &bigEndian) { bytes.append(contentsOf: $0) }
    }
}

private enum FFIReader {
    static func liftMetadata(_ buffer: RustBuffer) throws -> MobileFileDetailMetadata {
        var reader = Reader(buffer: buffer)
        let metadata = try reader.readMetadata()
        try reader.finish()
        return metadata
    }

    static func liftChanges(_ buffer: RustBuffer) throws -> [MobileFileChangeLogEntry] {
        var reader = Reader(buffer: buffer)
        let changes = try reader.readChanges()
        try reader.finish()
        return changes
    }

    static func liftOptionalString(_ buffer: RustBuffer) throws -> String? {
        var reader = Reader(buffer: buffer)
        let value = try reader.readOptionalString()
        try reader.finish()
        return value
    }

    static func liftCoreError(_ buffer: RustBuffer) throws -> MobileFileDetailError {
        var reader = Reader(buffer: buffer)
        let variant = try reader.readInt32()
        let error: MobileFileDetailError = switch variant {
        case 2:
            try .database(reader.readString())
        case 8:
            try .fileNotFound(reader.readString())
        case 14:
            try .permissionDenied(reader.readString())
        default:
            try .unavailable(reader.readCoreErrorPayload(variant: variant))
        }
        try reader.finish()
        return error
    }

    static func liftString(_ buffer: RustBuffer) throws -> String {
        defer { try? deallocate(buffer) }
        guard let data = buffer.data else { return "" }
        let bytes = UnsafeBufferPointer(start: data, count: Int(buffer.len))
        guard let string = String(bytes: bytes, encoding: .utf8) else {
            throw MobileFileDetailCoreFFIError.invalidStringEncoding
        }
        return string
    }

    static func deallocate(_ buffer: RustBuffer) throws {
        var status = RustCallStatus()
        ffi_area_matrix_core_rustbuffer_free(buffer, &status)
        guard status.code == 0 else {
            throw MobileFileDetailCoreFFIError.unexpectedStatus(status.code)
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
                throw MobileFileDetailCoreFFIError.incompleteData
            }
        }

        mutating func readMetadata() throws -> MobileFileDetailMetadata {
            try MobileFileDetailMetadata(
                id: readInt64(),
                path: readString(),
                originalName: readString(),
                currentName: readString(),
                category: readString(),
                sizeBytes: readInt64(),
                hashSha256: readString(),
                storageMode: readStorageMode(),
                origin: readFileOrigin(),
                sourcePath: readOptionalString(),
                availability: readAvailability(),
                importedAt: readInt64(),
                updatedAt: readInt64()
            )
        }

        mutating func readChanges() throws -> [MobileFileChangeLogEntry] {
            let count = try Int(readInt32())
            guard count >= 0 else {
                throw MobileFileDetailCoreFFIError.bufferOverflow
            }
            var changes: [MobileFileChangeLogEntry] = []
            changes.reserveCapacity(count)
            for _ in 0 ..< count {
                try changes.append(readChange())
            }
            return changes
        }

        mutating func readOptionalString() throws -> String? {
            let tag = try readInt8()
            switch tag {
            case 0:
                return nil
            case 1:
                return try readString()
            default:
                throw MobileFileDetailCoreFFIError.unexpectedOptionalTag(tag)
            }
        }

        mutating func readString() throws -> String {
            let count = try Int(readInt32())
            guard count >= 0, data.count >= offset + count else {
                throw MobileFileDetailCoreFFIError.bufferOverflow
            }
            defer { offset += count }
            guard let string = String(bytes: data[offset ..< offset + count], encoding: .utf8) else {
                throw MobileFileDetailCoreFFIError.invalidStringEncoding
            }
            return string
        }

        mutating func readInt32() throws -> Int32 {
            guard data.count >= offset + 4 else {
                throw MobileFileDetailCoreFFIError.bufferOverflow
            }
            defer { offset += 4 }
            var value: Int32 = 0
            _ = withUnsafeMutableBytes(of: &value) { data.copyBytes(to: $0, from: offset ..< offset + 4) }
            return value.bigEndian
        }

        private mutating func readChange() throws -> MobileFileChangeLogEntry {
            try MobileFileChangeLogEntry(
                id: readInt64(),
                fileID: readOptionalInt64(),
                filename: readString(),
                category: readString(),
                action: readString(),
                detailJSON: readString(),
                occurredAt: readInt64()
            )
        }

        private mutating func readOptionalInt64() throws -> Int64? {
            let tag = try readInt8()
            switch tag {
            case 0:
                return nil
            case 1:
                return try readInt64()
            default:
                throw MobileFileDetailCoreFFIError.unexpectedOptionalTag(tag)
            }
        }

        private mutating func readStorageMode() throws -> String {
            switch try readInt32() {
            case 1:
                return "Moved"
            case 2:
                return "Copied"
            case 3:
                return "Indexed"
            case let value:
                throw MobileFileDetailCoreFFIError.unexpectedEnumCase(Int64(value))
            }
        }

        private mutating func readFileOrigin() throws -> String {
            switch try readInt32() {
            case 1:
                return "Imported"
            case 2:
                return "Adopted"
            case 3:
                return "External"
            case let value:
                throw MobileFileDetailCoreFFIError.unexpectedEnumCase(Int64(value))
            }
        }

        private mutating func readAvailability() throws -> MobileFileDetailAvailability {
            switch try readInt32() {
            case 1:
                return .available
            case 2:
                return .missing
            case let value:
                throw MobileFileDetailCoreFFIError.unexpectedEnumCase(Int64(value))
            }
        }

        mutating func readCoreErrorPayload(variant: Int32) throws -> String {
            switch variant {
            case 1, 2, 3, 4, 5, 6, 7, 8, 9, 10, 11, 12, 13, 14, 15:
                return try readString()
            default:
                throw MobileFileDetailCoreFFIError.unexpectedEnumCase(Int64(variant))
            }
        }

        private mutating func readInt8() throws -> Int8 {
            guard data.count >= offset + 1 else {
                throw MobileFileDetailCoreFFIError.bufferOverflow
            }
            defer { offset += 1 }
            return Int8(bitPattern: data[offset])
        }

        private mutating func readInt64() throws -> Int64 {
            guard data.count >= offset + 8 else {
                throw MobileFileDetailCoreFFIError.bufferOverflow
            }
            defer { offset += 8 }
            var value: Int64 = 0
            _ = withUnsafeMutableBytes(of: &value) { data.copyBytes(to: $0, from: offset ..< offset + 8) }
            return value.bigEndian
        }
    }
}
