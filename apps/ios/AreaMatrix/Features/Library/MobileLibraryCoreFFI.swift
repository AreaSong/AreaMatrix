import Carea_matrixFFI
import Foundation

struct MobileLibraryCoreFFIClient {
    func listFiles(repoPath: String, filter: MobileLibraryFileFilter) throws -> [MobileLibraryFile] {
        try ensureCurrentContract()
        let path = try FFIWriter.lowerString(repoPath)
        let loweredFilter = try FFIWriter.lowerFileFilter(filter)
        let result = try rustCallWithCoreError {
            uniffi_area_matrix_core_fn_func_list_files(path, loweredFilter, $0)
        }
        return try FFIReader.liftFileEntries(result)
    }

    func listTreeJSON(repoPath: String, locale: String) throws -> String {
        try ensureCurrentContract()
        let path = try FFIWriter.lowerString(repoPath)
        let loweredLocale = try FFIWriter.lowerString(locale)
        let result = try rustCallWithCoreError {
            uniffi_area_matrix_core_fn_func_list_tree_json(path, loweredLocale, $0)
        }
        return try FFIReader.liftString(result)
    }

    private func ensureCurrentContract() throws {
        guard ffi_area_matrix_core_uniffi_contract_version() == 26,
              uniffi_area_matrix_core_checksum_func_list_files() == 56809,
              uniffi_area_matrix_core_checksum_func_list_tree_json() == 45468 else {
            throw MobileLibraryQueryError.unavailable("AreaMatrix Core binding contract mismatch.")
        }
    }
}

private enum MobileLibraryCoreFFIError: LocalizedError {
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

private func rustCallWithCoreError(_ callback: (UnsafeMutablePointer<RustCallStatus>) -> RustBuffer) throws
    -> RustBuffer {
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
            throw try MobileLibraryCoreFFIError.rustPanic(FFIReader.liftString(status.errorBuf))
        }
        try FFIReader.deallocate(status.errorBuf)
        throw MobileLibraryCoreFFIError.rustPanic("Rust panic")
    default:
        try FFIReader.deallocate(status.errorBuf)
        throw MobileLibraryCoreFFIError.unexpectedStatus(status.code)
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

    static func lowerFileFilter(_ filter: MobileLibraryFileFilter) throws -> RustBuffer {
        var bytes: [UInt8] = []
        writeOptionalString(filter.category, into: &bytes)
        writeOptionalBool(filter.includeDeleted, into: &bytes)
        writeOptionalInt64(filter.importedAfter, into: &bytes)
        writeOptionalInt64(filter.importedBefore, into: &bytes)
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
            throw MobileLibraryCoreFFIError.unexpectedStatus(status.code)
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

    private static func writeOptionalBool(_ value: Bool?, into bytes: inout [UInt8]) {
        guard let value else {
            writeInt8(0, into: &bytes)
            return
        }
        writeInt8(1, into: &bytes)
        bytes.append(value ? 1 : 0)
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
    static func liftFileEntries(_ buffer: RustBuffer) throws -> [MobileLibraryFile] {
        var reader = Reader(buffer: buffer)
        let files = try reader.readFileEntries()
        try reader.finish()
        return files
    }

    static func liftString(_ buffer: RustBuffer) throws -> String {
        defer { try? deallocate(buffer) }
        guard let data = buffer.data else { return "" }
        return String(decoding: UnsafeBufferPointer(start: data, count: Int(buffer.len)), as: UTF8.self)
    }

    static func liftCoreError(_ buffer: RustBuffer) throws -> MobileLibraryQueryError {
        var reader = Reader(buffer: buffer)
        let variant = try reader.readInt32()
        let error: MobileLibraryQueryError = switch variant {
        case 2:
            try .database(reader.readString())
        case 10:
            try .repoNotInitialized(reader.readString())
        case 11:
            try .repoNotInitialized(reader.readString())
        case 14:
            try .unavailable(reader.readString())
        default:
            try .unavailable(reader.readCoreErrorPayload(variant: variant))
        }
        try reader.finish()
        return error
    }

    static func deallocate(_ buffer: RustBuffer) throws {
        var status = RustCallStatus()
        ffi_area_matrix_core_rustbuffer_free(buffer, &status)
        guard status.code == 0 else {
            throw MobileLibraryCoreFFIError.unexpectedStatus(status.code)
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
                throw MobileLibraryCoreFFIError.incompleteData
            }
        }

        mutating func readFileEntries() throws -> [MobileLibraryFile] {
            let count = try Int(readInt32())
            guard count >= 0 else {
                throw MobileLibraryCoreFFIError.bufferOverflow
            }
            var files: [MobileLibraryFile] = []
            files.reserveCapacity(count)
            for _ in 0 ..< count {
                try files.append(readFileEntry())
            }
            return files
        }

        mutating func readString() throws -> String {
            let count = try Int(readInt32())
            guard count >= 0, data.count >= offset + count else {
                throw MobileLibraryCoreFFIError.bufferOverflow
            }
            defer { offset += count }
            return String(decoding: data[offset ..< offset + count], as: UTF8.self)
        }

        mutating func readInt32() throws -> Int32 {
            guard data.count >= offset + 4 else {
                throw MobileLibraryCoreFFIError.bufferOverflow
            }
            defer { offset += 4 }
            var value: Int32 = 0
            _ = withUnsafeMutableBytes(of: &value) { data.copyBytes(to: $0, from: offset ..< offset + 4) }
            return value.bigEndian
        }

        private mutating func readFileEntry() throws -> MobileLibraryFile {
            try MobileLibraryFile(
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
                availability: readFileAvailability(),
                importedAt: readInt64(),
                updatedAt: readInt64()
            )
        }

        private mutating func readOptionalString() throws -> String? {
            let tag = try readInt8()
            switch tag {
            case 0:
                return nil
            case 1:
                return try readString()
            default:
                throw MobileLibraryCoreFFIError.unexpectedOptionalTag(tag)
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
                throw MobileLibraryCoreFFIError.unexpectedEnumCase(Int64(value))
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
                throw MobileLibraryCoreFFIError.unexpectedEnumCase(Int64(value))
            }
        }

        private mutating func readFileAvailability() throws -> MobileLibraryFileAvailability {
            switch try readInt32() {
            case 1:
                return .available
            case 2:
                return .missing
            case let value:
                throw MobileLibraryCoreFFIError.unexpectedEnumCase(Int64(value))
            }
        }

        mutating func readCoreErrorPayload(variant: Int32) throws -> String {
            switch variant {
            case 1, 2, 3, 4, 5, 6, 7, 8, 9, 10, 11, 12, 13, 14, 15:
                return try readString()
            default:
                throw MobileLibraryCoreFFIError.unexpectedEnumCase(Int64(variant))
            }
        }

        private mutating func readInt8() throws -> Int8 {
            guard data.count >= offset + 1 else {
                throw MobileLibraryCoreFFIError.bufferOverflow
            }
            defer { offset += 1 }
            return Int8(bitPattern: data[offset])
        }

        private mutating func readInt64() throws -> Int64 {
            guard data.count >= offset + 8 else {
                throw MobileLibraryCoreFFIError.bufferOverflow
            }
            defer { offset += 8 }
            var value: Int64 = 0
            _ = withUnsafeMutableBytes(of: &value) { data.copyBytes(to: $0, from: offset ..< offset + 8) }
            return value.bigEndian
        }
    }
}
