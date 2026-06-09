import Carea_matrixFFI
import Foundation

protocol PlatformDifferencesBindingContractInspecting: Sendable {
    func inspectBindingContract(
        targetPlatform: PlatformDifferencesBindingTarget,
        bindingVersion: Int64
    ) async throws -> PlatformDifferencesBindingContractReport
}

enum PlatformDifferencesBindingTarget: String, CaseIterable, Equatable, Identifiable, Sendable {
    case swift = "Swift"
    case kotlin = "Kotlin"
    case python = "Python"

    var id: String { rawValue }
}

enum PlatformDifferencesBindingSupportStatus: String, Equatable, Sendable {
    case supported = "Supported"
    case limited = "Limited"
    case missing = "Missing"
}

struct PlatformDifferencesBindingApiContract: Equatable, Identifiable, Sendable {
    var name: String
    var capability: String
    var status: PlatformDifferencesBindingSupportStatus
    var reason: String?

    var id: String { "\(capability)-\(name)" }
}

struct PlatformDifferencesBindingTypeMapping: Equatable, Identifiable, Sendable {
    var rustType: String
    var udlType: String
    var targetType: String
    var status: PlatformDifferencesBindingSupportStatus
    var reason: String?

    var id: String { "\(rustType)-\(udlType)-\(targetType)" }
}

struct PlatformDifferencesMissingCapability: Equatable, Identifiable, Sendable {
    var capability: String
    var label: String
    var status: PlatformDifferencesBindingSupportStatus
    var reason: String

    var id: String { "\(capability)-\(label)" }
}

struct PlatformDifferencesBindingContractReport: Equatable, Sendable {
    var targetPlatform: PlatformDifferencesBindingTarget
    var bindingVersion: Int64
    var coreVersion: String
    var supportedApis: [PlatformDifferencesBindingApiContract]
    var typeMappings: [PlatformDifferencesBindingTypeMapping]
    var missingCapabilities: [PlatformDifferencesMissingCapability]
}

enum PlatformDifferencesBindingContractError: Error, Equatable, LocalizedError {
    case config(String)
    case internalFailure(String)
    case unavailable(String)

    var errorDescription: String? {
        switch self {
        case let .config(reason):
            reason
        case let .internalFailure(message):
            message
        case let .unavailable(message):
            message
        }
    }

    var recoverySuggestion: String {
        switch self {
        case .config:
            "Choose a supported binding contract version, then retry."
        case .internalFailure:
            "Retry after the Core bridge reports a complete contract."
        case .unavailable:
            "Check the Core bridge integration, then retry."
        }
    }
}

actor LivePlatformDifferencesCoreBridge: PlatformDifferencesBindingContractInspecting {
    private let client: PlatformDifferencesCoreFFIClient

    init(client: PlatformDifferencesCoreFFIClient = PlatformDifferencesCoreFFIClient()) {
        self.client = client
    }

    func inspectBindingContract(
        targetPlatform: PlatformDifferencesBindingTarget,
        bindingVersion: Int64
    ) async throws -> PlatformDifferencesBindingContractReport {
        try client.inspectBindingContract(targetPlatform: targetPlatform, bindingVersion: bindingVersion)
    }
}

struct PlatformDifferencesCoreFFIClient: Sendable {
    func inspectBindingContract(
        targetPlatform: PlatformDifferencesBindingTarget,
        bindingVersion: Int64
    ) throws -> PlatformDifferencesBindingContractReport {
        try ensureCurrentContract()
        let request = try FFIWriter.lowerBindingContractRequest(
            targetPlatform: targetPlatform,
            bindingVersion: bindingVersion
        )
        let result = try rustCallWithCoreError {
            uniffi_area_matrix_core_fn_func_inspect_binding_contract(request, $0)
        }
        return try FFIReader.liftBindingContractReport(result)
    }

    private func ensureCurrentContract() throws {
        guard ffi_area_matrix_core_uniffi_contract_version() == 26,
              uniffi_area_matrix_core_checksum_func_inspect_binding_contract() == 34434 else {
            throw PlatformDifferencesBindingContractError.unavailable(
                "AreaMatrix Core binding contract mismatch."
            )
        }
    }
}

private enum PlatformDifferencesCoreFFIError: LocalizedError {
    case bufferOverflow
    case unexpectedStatus(Int8)
    case unexpectedEnumCase(Int32)
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
            throw try PlatformDifferencesCoreFFIError.rustPanic(FFIReader.liftString(status.errorBuf))
        }
        try FFIReader.deallocate(status.errorBuf)
        throw PlatformDifferencesCoreFFIError.rustPanic("Rust panic")
    default:
        try FFIReader.deallocate(status.errorBuf)
        throw PlatformDifferencesCoreFFIError.unexpectedStatus(status.code)
    }
}

private enum FFIWriter {
    static func lowerBindingContractRequest(
        targetPlatform: PlatformDifferencesBindingTarget,
        bindingVersion: Int64
    ) throws -> RustBuffer {
        var bytes: [UInt8] = []
        writeInt32(targetPlatform.coreEnumTag, into: &bytes)
        writeInt64(bindingVersion, into: &bytes)
        return try bytes.withUnsafeBufferPointer { try lowerBytes($0) }
    }

    private static func lowerBytes(_ bytes: UnsafeBufferPointer<UInt8>) throws -> RustBuffer {
        var status = RustCallStatus()
        let buffer = ffi_area_matrix_core_rustbuffer_from_bytes(
            ForeignBytes(len: Int32(bytes.count), data: bytes.baseAddress),
            &status
        )
        guard status.code == 0 else {
            throw PlatformDifferencesCoreFFIError.unexpectedStatus(status.code)
        }
        return buffer
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
    static func liftBindingContractReport(_ buffer: RustBuffer) throws
        -> PlatformDifferencesBindingContractReport {
        var reader = Reader(buffer: buffer)
        let report = try reader.readBindingContractReport()
        try reader.finish()
        return report
    }

    static func liftCoreError(_ buffer: RustBuffer) throws -> PlatformDifferencesBindingContractError {
        var reader = Reader(buffer: buffer)
        let variant = try reader.readInt32()
        let payload = try reader.readString()
        try reader.finish()
        switch variant {
        case 3:
            return .config(payload)
        case 15:
            return .internalFailure(payload)
        default:
            return .unavailable(payload.isEmpty ? "AreaMatrix Core returned error \(variant)." : payload)
        }
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
            throw PlatformDifferencesCoreFFIError.unexpectedStatus(status.code)
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
                throw PlatformDifferencesCoreFFIError.incompleteData
            }
        }

        mutating func readBindingContractReport() throws -> PlatformDifferencesBindingContractReport {
            try PlatformDifferencesBindingContractReport(
                targetPlatform: readBindingTarget(),
                bindingVersion: readInt64(),
                coreVersion: readString(),
                supportedApis: readApiContracts(),
                typeMappings: readTypeMappings(),
                missingCapabilities: readMissingCapabilities()
            )
        }

        mutating func readApiContracts() throws -> [PlatformDifferencesBindingApiContract] {
            try readSequence { reader in
                try PlatformDifferencesBindingApiContract(
                    name: reader.readString(),
                    capability: reader.readString(),
                    status: reader.readSupportStatus(),
                    reason: reader.readOptionalString()
                )
            }
        }

        mutating func readTypeMappings() throws -> [PlatformDifferencesBindingTypeMapping] {
            try readSequence { reader in
                try PlatformDifferencesBindingTypeMapping(
                    rustType: reader.readString(),
                    udlType: reader.readString(),
                    targetType: reader.readString(),
                    status: reader.readSupportStatus(),
                    reason: reader.readOptionalString()
                )
            }
        }

        mutating func readMissingCapabilities() throws -> [PlatformDifferencesMissingCapability] {
            try readSequence { reader in
                try PlatformDifferencesMissingCapability(
                    capability: reader.readString(),
                    label: reader.readString(),
                    status: reader.readSupportStatus(),
                    reason: reader.readString()
                )
            }
        }

        mutating func readBindingTarget() throws -> PlatformDifferencesBindingTarget {
            switch try readInt32() {
            case 1:
                return .swift
            case 2:
                return .kotlin
            case 3:
                return .python
            case let value:
                throw PlatformDifferencesCoreFFIError.unexpectedEnumCase(value)
            }
        }

        mutating func readSupportStatus() throws -> PlatformDifferencesBindingSupportStatus {
            switch try readInt32() {
            case 1:
                return .supported
            case 2:
                return .limited
            case 3:
                return .missing
            case let value:
                throw PlatformDifferencesCoreFFIError.unexpectedEnumCase(value)
            }
        }

        mutating func readOptionalString() throws -> String? {
            switch try readInt8() {
            case 0:
                return nil
            case 1:
                return try readString()
            case let tag:
                throw PlatformDifferencesCoreFFIError.unexpectedOptionalTag(tag)
            }
        }

        mutating func readSequence<T>(_ readElement: (inout Reader) throws -> T) throws -> [T] {
            let count = try Int(readInt32())
            guard count >= 0 else {
                throw PlatformDifferencesCoreFFIError.bufferOverflow
            }
            var values: [T] = []
            values.reserveCapacity(count)
            for _ in 0 ..< count {
                try values.append(readElement(&self))
            }
            return values
        }

        mutating func readString() throws -> String {
            let count = try Int(readInt32())
            guard count >= 0, data.count >= offset + count else {
                throw PlatformDifferencesCoreFFIError.bufferOverflow
            }
            defer { offset += count }
            return String(decoding: data[offset ..< offset + count], as: UTF8.self)
        }

        mutating func readInt8() throws -> Int8 {
            guard data.count >= offset + 1 else {
                throw PlatformDifferencesCoreFFIError.bufferOverflow
            }
            defer { offset += 1 }
            return Int8(bitPattern: data[offset])
        }

        mutating func readInt32() throws -> Int32 {
            guard data.count >= offset + 4 else {
                throw PlatformDifferencesCoreFFIError.bufferOverflow
            }
            defer { offset += 4 }
            var value: Int32 = 0
            _ = withUnsafeMutableBytes(of: &value) { data.copyBytes(to: $0, from: offset ..< offset + 4) }
            return value.bigEndian
        }

        mutating func readInt64() throws -> Int64 {
            guard data.count >= offset + 8 else {
                throw PlatformDifferencesCoreFFIError.bufferOverflow
            }
            defer { offset += 8 }
            var value: Int64 = 0
            _ = withUnsafeMutableBytes(of: &value) { data.copyBytes(to: $0, from: offset ..< offset + 8) }
            return value.bigEndian
        }
    }
}

private extension PlatformDifferencesBindingTarget {
    var coreEnumTag: Int32 {
        switch self {
        case .swift:
            1
        case .kotlin:
            2
        case .python:
            3
        }
    }
}
