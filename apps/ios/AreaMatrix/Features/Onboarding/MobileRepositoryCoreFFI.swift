import Carea_matrixFFI
import Foundation

actor LiveMobileRepositoryCoreBridge: MobileRepositoryCoreBridge {
    private let client: MobileRepositoryCoreFFIClient
    private let cloudClient: MobileCloudStorageCoreFFIClient

    init(
        client: MobileRepositoryCoreFFIClient = MobileRepositoryCoreFFIClient(),
        cloudClient: MobileCloudStorageCoreFFIClient = MobileCloudStorageCoreFFIClient()
    ) {
        self.client = client
        self.cloudClient = cloudClient
    }

    func getVersion() async throws -> String {
        try client.getVersion()
    }

    func validateRepoPath(repoPath: String) async throws -> MobileRepositoryValidation {
        try client.validateRepoPath(repoPath: repoPath)
    }

    func detectCloudStorageState(repoPath: String) async throws -> MobileCloudStorageState {
        try cloudClient.detectCloudStorageState(repoPath: repoPath)
    }

    func initializeEmptyRepository(repoPath: String) async throws {
        try client.initRepo(repoPath: repoPath, mode: .createEmpty, createDefaultCategories: true)
    }

    func adoptExistingRepository(repoPath: String) async throws {
        try client.initRepo(repoPath: repoPath, mode: .adoptExisting, createDefaultCategories: false)
    }

    func loadConfig(repoPath: String) async throws -> MobileRepositoryConfig {
        try client.loadConfig(repoPath: repoPath)
    }

    func updateConfig(repoPath: String, newConfig: MobileRepositoryConfig) async throws {
        try client.updateConfig(repoPath: repoPath, newConfig: newConfig)
    }
}

struct MobileRepositoryCoreFFIClient: Sendable {
    func getVersion() throws -> String {
        try ensureCurrentContract()
        let result = try rustCallWithCoreError {
            uniffi_area_matrix_core_fn_func_get_version($0)
        }
        return try FFIReader.liftString(result)
    }

    func validateRepoPath(repoPath: String) throws -> MobileRepositoryValidation {
        try ensureCurrentContract()
        let path = try FFIWriter.lowerString(repoPath)
        let result = try rustCallWithCoreError {
            uniffi_area_matrix_core_fn_func_validate_repo_path(path, $0)
        }
        return try FFIReader.liftValidation(result)
    }

    func initRepo(
        repoPath: String,
        mode: MobileRepositoryInitMode,
        createDefaultCategories: Bool
    ) throws {
        try ensureCurrentContract()
        let path = try FFIWriter.lowerString(repoPath)
        let options = try FFIWriter.lowerRepoInitOptions(
            mode: mode,
            createDefaultCategories: createDefaultCategories,
            overviewOutput: .generatedOnly
        )
        try rustCallVoidWithCoreError {
            uniffi_area_matrix_core_fn_func_init_repo(path, options, $0)
        }
    }

    func loadConfig(repoPath: String) throws -> MobileRepositoryConfig {
        try ensureCurrentContract()
        let path = try FFIWriter.lowerString(repoPath)
        let result = try rustCallWithCoreError {
            uniffi_area_matrix_core_fn_func_load_config(path, $0)
        }
        return try FFIReader.liftConfig(result)
    }

    func updateConfig(repoPath: String, newConfig: MobileRepositoryConfig) throws {
        try ensureCurrentContract()
        let path = try FFIWriter.lowerString(repoPath)
        let config = try FFIWriter.lowerRepoConfig(newConfig)
        try rustCallVoidWithCoreError {
            uniffi_area_matrix_core_fn_func_update_config(path, config, $0)
        }
    }

    private func ensureCurrentContract() throws {
        guard ffi_area_matrix_core_uniffi_contract_version() == 26,
              uniffi_area_matrix_core_checksum_func_get_version() == 61902,
              uniffi_area_matrix_core_checksum_func_validate_repo_path() == 43498,
              uniffi_area_matrix_core_checksum_func_load_config() == 64573,
              uniffi_area_matrix_core_checksum_func_update_config() == 60628,
              uniffi_area_matrix_core_checksum_func_init_repo() == 29414 else {
            throw MobileRepositoryConnectionError.unavailable("AreaMatrix Core binding contract mismatch.")
        }
    }
}

private enum MobileRepositoryOverviewOutput: Int32 {
    case generatedOnly = 1
}

private enum MobileRepositoryCoreFFIError: LocalizedError {
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

private func rustCallWithCoreError(_ callback: (UnsafeMutablePointer<RustCallStatus>) -> RustBuffer) throws -> RustBuffer {
    var status = RustCallStatus()
    let result = callback(&status)
    try checkStatus(status)
    return result
}

private func rustCallVoidWithCoreError(_ callback: (UnsafeMutablePointer<RustCallStatus>) -> Void) throws {
    var status = RustCallStatus()
    callback(&status)
    try checkStatus(status)
}

private func checkStatus(_ status: RustCallStatus) throws {
    switch status.code {
    case 0:
        return
    case 1:
        throw try FFIReader.liftCoreError(status.errorBuf)
    case 2:
        if status.errorBuf.len > 0 {
            throw try MobileRepositoryCoreFFIError.rustPanic(FFIReader.liftString(status.errorBuf))
        }
        try FFIReader.deallocate(status.errorBuf)
        throw MobileRepositoryCoreFFIError.rustPanic("Rust panic")
    default:
        try FFIReader.deallocate(status.errorBuf)
        throw MobileRepositoryCoreFFIError.unexpectedStatus(status.code)
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

    static func lowerRepoInitOptions(
        mode: MobileRepositoryInitMode,
        createDefaultCategories: Bool,
        overviewOutput: MobileRepositoryOverviewOutput
    ) throws -> RustBuffer {
        var bytes: [UInt8] = []
        writeInt32(enumValue(for: mode), into: &bytes)
        writeBool(createDefaultCategories, into: &bytes)
        writeInt32(overviewOutput.rawValue, into: &bytes)
        return try bytes.withUnsafeBufferPointer { try lowerBytes($0) }
    }

    static func lowerRepoConfig(_ config: MobileRepositoryConfig) throws -> RustBuffer {
        var bytes: [UInt8] = []
        writeString(config.repoPath, into: &bytes)
        writeStorageMode(config.defaultMode, into: &bytes)
        writeOverviewOutput(config.overviewOutput, into: &bytes)
        writeBool(config.aiEnabled, into: &bytes)
        writeString(config.locale, into: &bytes)
        writeBool(config.iCloudWarn, into: &bytes)
        writeBool(config.enableExtensionRules, into: &bytes)
        writeBool(config.enableKeywordRules, into: &bytes)
        writeBool(config.fallbackToInbox, into: &bytes)
        writeBool(config.allowReplaceDuringImport, into: &bytes)
        return try bytes.withUnsafeBufferPointer { try lowerBytes($0) }
    }

    private static func enumValue(for mode: MobileRepositoryInitMode) -> Int32 {
        switch mode {
        case .createEmpty:
            1
        case .adoptExisting:
            2
        }
    }

    private static func writeStorageMode(_ value: String, into bytes: inout [UInt8]) {
        switch value {
        case "Moved":
            writeInt32(1, into: &bytes)
        case "Copied":
            writeInt32(2, into: &bytes)
        case "Indexed":
            writeInt32(3, into: &bytes)
        default:
            writeInt32(2, into: &bytes)
        }
    }

    private static func writeOverviewOutput(_ value: String, into bytes: inout [UInt8]) {
        writeInt32(value == "RootAreaMatrixFile" ? 2 : 1, into: &bytes)
    }

    private static func writeString(_ value: String, into bytes: inout [UInt8]) {
        let stringBytes = Array(value.utf8)
        writeInt32(Int32(stringBytes.count), into: &bytes)
        bytes.append(contentsOf: stringBytes)
    }

    private static func lowerBytes(_ bytes: UnsafeBufferPointer<UInt8>) throws -> RustBuffer {
        var status = RustCallStatus()
        let buffer = ffi_area_matrix_core_rustbuffer_from_bytes(
            ForeignBytes(len: Int32(bytes.count), data: bytes.baseAddress),
            &status
        )
        guard status.code == 0 else {
            throw MobileRepositoryCoreFFIError.unexpectedStatus(status.code)
        }
        return buffer
    }

    private static func writeBool(_ value: Bool, into bytes: inout [UInt8]) {
        bytes.append(value ? 1 : 0)
    }

    private static func writeInt32(_ value: Int32, into bytes: inout [UInt8]) {
        var bigEndian = value.bigEndian
        withUnsafeBytes(of: &bigEndian) { bytes.append(contentsOf: $0) }
    }
}

private enum FFIReader {
    static func liftValidation(_ buffer: RustBuffer) throws -> MobileRepositoryValidation {
        var reader = Reader(buffer: buffer)
        let validation = try MobileRepositoryValidation(
            repoPath: reader.readString(),
            exists: reader.readBool(),
            isDirectory: reader.readBool(),
            isReadable: reader.readBool(),
            isWritable: reader.readBool(),
            isEmpty: reader.readBool(),
            isInitialized: reader.readBool(),
            isInsideAreaMatrix: reader.readBool(),
            isICloudPath: reader.readBool(),
            isOneDrivePath: reader.readBool(),
            platformPathKind: reader.readPlatformPathKind(),
            isCaseSensitivePath: reader.readBool(),
            hasUnfinishedScanSession: reader.readBool(),
            recommendedMode: reader.readOptionalInitMode(),
            issues: reader.readPathIssues()
        )
        try reader.finish()
        return validation
    }

    static func liftConfig(_ buffer: RustBuffer) throws -> MobileRepositoryConfig {
        var reader = Reader(buffer: buffer)
        let config = try MobileRepositoryConfig(
            repoPath: reader.readString(),
            defaultMode: reader.readStorageMode(),
            overviewOutput: reader.readOverviewOutput(),
            aiEnabled: reader.readBool(),
            locale: reader.readString(),
            iCloudWarn: reader.readBool(),
            enableExtensionRules: reader.readBool(),
            enableKeywordRules: reader.readBool(),
            fallbackToInbox: reader.readBool(),
            allowReplaceDuringImport: reader.readBool()
        )
        try reader.finish()
        return config
    }

    static func liftCoreError(_ buffer: RustBuffer) throws -> MobileRepositoryConnectionError {
        var reader = Reader(buffer: buffer)
        let variant = try reader.readInt32()
        let error: MobileRepositoryConnectionError
        switch variant {
        case 10:
            error = try .invalidRepository(reader.readString())
        case 11:
            error = try .invalidPath(reader.readString())
        case 12:
            error = try .iCloudPlaceholder(reader.readString())
        case 14:
            error = try .permissionDenied(reader.readString())
        default:
            error = try .unavailable(reader.readCoreErrorPayload(variant: variant))
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
            throw MobileRepositoryCoreFFIError.unexpectedStatus(status.code)
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
                throw MobileRepositoryCoreFFIError.incompleteData
            }
        }

        mutating func readString() throws -> String {
            let count = Int(try readInt32())
            guard count >= 0, data.count >= offset + count else {
                throw MobileRepositoryCoreFFIError.bufferOverflow
            }
            defer { offset += count }
            return String(decoding: data[offset ..< offset + count], as: UTF8.self)
        }

        mutating func readBool() throws -> Bool {
            try readInt8() != 0
        }

        mutating func readOptionalInitMode() throws -> MobileRepositoryInitMode? {
            let tag = try readInt8()
            switch tag {
            case 0:
                return nil
            case 1:
                return try readInitMode()
            default:
                throw MobileRepositoryCoreFFIError.unexpectedOptionalTag(tag)
            }
        }

        mutating func readPathIssues() throws -> [MobileRepositoryPathIssue] {
            let count = Int(try readInt32())
            guard count >= 0 else {
                throw MobileRepositoryCoreFFIError.bufferOverflow
            }
            var issues: [MobileRepositoryPathIssue] = []
            issues.reserveCapacity(count)
            for _ in 0 ..< count {
                issues.append(try readPathIssue())
            }
            return issues
        }

        mutating func readPlatformPathKind() throws -> MobileRepositoryPlatformPathKind {
            switch try readInt32() {
            case 1:
                return .local
            case 2:
                return .iCloudDrive
            case 3:
                return .oneDrive
            case 4:
                return .networkShare
            case 5:
                return .unknown
            case let value:
                throw MobileRepositoryCoreFFIError.unexpectedEnumCase(value)
            }
        }

        mutating func readStorageMode() throws -> String {
            switch try readInt32() {
            case 1:
                return "Moved"
            case 2:
                return "Copied"
            case 3:
                return "Indexed"
            case let value:
                throw MobileRepositoryCoreFFIError.unexpectedEnumCase(value)
            }
        }

        mutating func readCoreErrorPayload(variant: Int32) throws -> String {
            switch variant {
            case 1, 2, 3, 4, 5, 6, 7, 8, 9, 10, 11, 12, 13, 14, 15:
                return try readString()
            default:
                throw MobileRepositoryCoreFFIError.unexpectedEnumCase(variant)
            }
        }

        private mutating func readInitMode() throws -> MobileRepositoryInitMode {
            switch try readInt32() {
            case 1:
                return .createEmpty
            case 2:
                return .adoptExisting
            case let value:
                throw MobileRepositoryCoreFFIError.unexpectedEnumCase(value)
            }
        }

        private mutating func readPathIssue() throws -> MobileRepositoryPathIssue {
            switch try readInt32() {
            case 1:
                return .missingPath
            case 2:
                return .notDirectory
            case 3:
                return .notReadable
            case 4:
                return .notWritable
            case 5:
                return .nonEmptyDirectory
            case 6:
                return .alreadyInitialized
            case 7:
                return .insideAreaMatrix
            case 8:
                return .iCloudPath
            case 9:
                return .oneDrivePath
            case 10:
                return .windowsReservedName
            case 11:
                return .windowsCaseInsensitive
            case 12:
                return .unfinishedScanSession
            case let value:
                throw MobileRepositoryCoreFFIError.unexpectedEnumCase(value)
            }
        }

        mutating func readOverviewOutput() throws -> String {
            switch try readInt32() {
            case 1:
                return "GeneratedOnly"
            case 2:
                return "RootAreaMatrixFile"
            case let value:
                throw MobileRepositoryCoreFFIError.unexpectedEnumCase(value)
            }
        }

        private mutating func readInt8() throws -> Int8 {
            guard data.count >= offset + 1 else {
                throw MobileRepositoryCoreFFIError.bufferOverflow
            }
            defer { offset += 1 }
            return Int8(bitPattern: data[offset])
        }

        mutating func readInt32() throws -> Int32 {
            guard data.count >= offset + 4 else {
                throw MobileRepositoryCoreFFIError.bufferOverflow
            }
            defer { offset += 4 }
            var value: Int32 = 0
            _ = withUnsafeMutableBytes(of: &value) { data.copyBytes(to: $0, from: offset ..< offset + 4) }
            return value.bigEndian
        }
    }
}
