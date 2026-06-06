import Carea_matrixFFI
import Foundation

struct CameraImportCoreFFIClient {
    func predictCategory(repoPath: String, filename: String) throws -> CameraImportCategoryPrediction {
        try ensureCurrentContract()
        let result = try rustCallWithCoreError {
            uniffi_area_matrix_core_fn_func_predict_category(
                try FFIWriter.lowerString(repoPath),
                try FFIWriter.lowerString(filename),
                $0
            )
        }
        return try FFIReader.liftCategoryPrediction(result)
    }

    func importCapturedPhoto(request: CameraImportCoreRequest) throws -> MobileLibraryFile {
        try ensureCurrentContract()
        let result = try rustCallWithCoreError {
            uniffi_area_matrix_core_fn_func_import_file(
                try FFIWriter.lowerString(request.repoPath),
                try FFIWriter.lowerString(request.sourceURL.path),
                try FFIWriter.lowerImportOptions(request),
                $0
            )
        }
        return try FFIReader.liftFileEntry(result)
    }

    private func ensureCurrentContract() throws {
        guard ffi_area_matrix_core_uniffi_contract_version() == 26,
              uniffi_area_matrix_core_checksum_func_predict_category() == 65047,
              uniffi_area_matrix_core_checksum_func_import_file() == 45263 else {
            throw CameraImportError.unavailable("AreaMatrix Core binding contract mismatch.")
        }
    }
}

private enum CameraImportCoreFFIError: LocalizedError {
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

private func rustCallWithCoreError(_ callback: (UnsafeMutablePointer<RustCallStatus>) throws -> RustBuffer)
    throws -> RustBuffer {
    var status = RustCallStatus()
    let result = try callback(&status)
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
            throw try CameraImportCoreFFIError.rustPanic(FFIReader.liftString(status.errorBuf))
        }
        try FFIReader.deallocate(status.errorBuf)
        throw CameraImportCoreFFIError.rustPanic("Rust panic")
    default:
        try FFIReader.deallocate(status.errorBuf)
        throw CameraImportCoreFFIError.unexpectedStatus(status.code)
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

    static func lowerImportOptions(_ request: CameraImportCoreRequest) throws -> RustBuffer {
        var bytes: [UInt8] = []
        writeInt32(2, into: &bytes)
        writeInt32(3, into: &bytes)
        writeOptionalString(nil, into: &bytes)
        writeOptionalString(request.category, into: &bytes)
        writeOptionalString(request.filename, into: &bytes)
        writeInt32(request.duplicateStrategy == .keepBoth ? 3 : 1, into: &bytes)
        return try bytes.withUnsafeBufferPointer { try lowerBytes($0) }
    }

    private static func lowerBytes(_ bytes: UnsafeBufferPointer<UInt8>) throws -> RustBuffer {
        var status = RustCallStatus()
        let buffer = ffi_area_matrix_core_rustbuffer_from_bytes(
            ForeignBytes(len: Int32(bytes.count), data: bytes.baseAddress),
            &status
        )
        guard status.code == 0 else {
            throw CameraImportCoreFFIError.unexpectedStatus(status.code)
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
}

private enum FFIReader {
    static func liftCategoryPrediction(_ buffer: RustBuffer) throws -> CameraImportCategoryPrediction {
        var reader = Reader(buffer: buffer)
        let prediction = try CameraImportCategoryPrediction(
            category: reader.readString(),
            suggestedName: reader.readString(),
            confidence: reader.skippingClassifyReasonAndReadingConfidence()
        )
        try reader.finish()
        return prediction
    }

    static func liftFileEntry(_ buffer: RustBuffer) throws -> MobileLibraryFile {
        var reader = Reader(buffer: buffer)
        let file = try reader.readFileEntry()
        try reader.finish()
        return file
    }

    static func liftCoreError(_ buffer: RustBuffer) throws -> CameraImportError {
        var reader = Reader(buffer: buffer)
        let variant = try reader.readInt32()
        let error: CameraImportError = switch variant {
        case 2:
            try .database(reader.readString())
        case 6:
            try .nameConflict(reader.readString())
        case 7:
            try .duplicateContent(reader.readString())
        case 11:
            try .invalidPath(reader.readString())
        case 14:
            try .permissionDenied(reader.readString())
        case 1, 12:
            try .unreadableSource(reader.readString())
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
            throw CameraImportCoreFFIError.unexpectedStatus(status.code)
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
                throw CameraImportCoreFFIError.incompleteData
            }
        }

        mutating func readFileEntry() throws -> MobileLibraryFile {
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

        mutating func readString() throws -> String {
            let count = try Int(readInt32())
            guard count >= 0, data.count >= offset + count else {
                throw CameraImportCoreFFIError.bufferOverflow
            }
            defer { offset += count }
            return String(decoding: data[offset ..< offset + count], as: UTF8.self)
        }

        mutating func readCoreErrorPayload(variant: Int32) throws -> String {
            switch variant {
            case 1, 2, 3, 4, 5, 6, 7, 8, 9, 10, 11, 12, 13, 14, 15:
                return try readString()
            default:
                throw CameraImportCoreFFIError.unexpectedEnumCase(Int64(variant))
            }
        }

        mutating func skippingClassifyReasonAndReadingConfidence() throws -> Float {
            _ = try readInt32()
            return try readFloat()
        }

        private mutating func readOptionalString() throws -> String? {
            let tag = try readInt8()
            switch tag {
            case 0:
                return nil
            case 1:
                return try readString()
            default:
                throw CameraImportCoreFFIError.unexpectedOptionalTag(tag)
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
                throw CameraImportCoreFFIError.unexpectedEnumCase(Int64(value))
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
                throw CameraImportCoreFFIError.unexpectedEnumCase(Int64(value))
            }
        }

        private mutating func readFileAvailability() throws -> MobileLibraryFileAvailability {
            switch try readInt32() {
            case 1:
                return .available
            case 2:
                return .missing
            case let value:
                throw CameraImportCoreFFIError.unexpectedEnumCase(Int64(value))
            }
        }

        private mutating func readInt8() throws -> Int8 {
            guard data.count >= offset + 1 else {
                throw CameraImportCoreFFIError.bufferOverflow
            }
            defer { offset += 1 }
            return Int8(bitPattern: data[offset])
        }

        mutating func readInt32() throws -> Int32 {
            guard data.count >= offset + 4 else {
                throw CameraImportCoreFFIError.bufferOverflow
            }
            defer { offset += 4 }
            var value: Int32 = 0
            _ = withUnsafeMutableBytes(of: &value) { data.copyBytes(to: $0, from: offset ..< offset + 4) }
            return value.bigEndian
        }

        private mutating func readInt64() throws -> Int64 {
            guard data.count >= offset + 8 else {
                throw CameraImportCoreFFIError.bufferOverflow
            }
            defer { offset += 8 }
            var value: Int64 = 0
            _ = withUnsafeMutableBytes(of: &value) { data.copyBytes(to: $0, from: offset ..< offset + 8) }
            return value.bigEndian
        }

        private mutating func readFloat() throws -> Float {
            Float(bitPattern: UInt32(bitPattern: try readInt32()))
        }
    }
}
