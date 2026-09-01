import Foundation
import SwiftUI
import Darwin

enum RepositorySettingsState: Equatable, Sendable {
    case loading
    case empty
    case loaded(RepositorySettingsSnapshot)
    case failed(RepositorySettingsFailure)
}

struct RepositorySettingsFailure: Equatable, Sendable {
    var message: String
    var recovery: String
}

struct RepositorySettingsSnapshot: Equatable, Sendable {
    var name: String
    var location: String
    var locationType: String
    var lastOpened: String
    var coreVersion: String
    var access: String
    var watcher: String
    var cloud: String
    var config: MobileRepositoryConfig
    var capabilities: PlatformDifferencesCapabilities
}

enum RepositorySettingsDiagnosticsState: Equatable, Sendable {
    case idle
    case exporting
    case exported(String)
    case failed(RepositorySettingsFailure)

    var isExporting: Bool {
        if case .exporting = self {
            return true
        }
        return false
    }
}

protocol RepositorySettingsDiagnosticsExporting: Sendable {
    func export(snapshot: RepositorySettingsSnapshot) async throws -> String
}

actor FileRepositorySettingsDiagnosticsExporter: RepositorySettingsDiagnosticsExporting {
    func export(snapshot: RepositorySettingsSnapshot) async throws -> String {
        do {
            return try MobileDiagnosticsFileSafety.write(
                repoPath: snapshot.location,
                prefix: "repository-settings",
                lines: Self.diagnosticLines(for: snapshot)
            )
        } catch let error as MobileRepositoryConnectionError {
            throw error
        } catch {
            throw MobileRepositoryConnectionError.permissionDenied(snapshot.location)
        }
    }

    private static func diagnosticLines(for snapshot: RepositorySettingsSnapshot) -> [String] {
        [
            "AreaMatrix repository settings diagnostics",
            "No user file contents are included.",
            "Name: [redacted]",
            "Location: [redacted]",
            "Type: \(snapshot.locationType)",
            "Last opened: \(snapshot.lastOpened)",
            "Core version: \(snapshot.coreVersion)",
            "Access: \(snapshot.access)",
            "Watcher: \(snapshot.watcher)",
            "Cloud: \(snapshot.cloud)",
            "Locale: \(snapshot.config.locale)",
            "Fallback to Inbox: \(snapshot.config.fallbackToInbox)",
            "Platform: \(snapshot.capabilities.platform.rawValue)",
            "App version: \(snapshot.capabilities.appVersion)"
        ]
    }
}

private enum MobileDiagnosticsFileSafety {
    static func write(repoPath: String, prefix: String, lines: [String]) throws -> String {
        guard !repoPath.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            throw MobileRepositoryConnectionError.invalidPath(repoPath)
        }

        let rootPath = URL(fileURLWithPath: repoPath, isDirectory: true).standardizedFileURL.path
        let rootFD = try openDirectory(path: rootPath)
        defer { close(rootFD) }
        let metadataFD = try openChild(parentFD: rootFD, name: ".areamatrix", create: true)
        defer { close(metadataFD) }
        let generatedFD = try openChild(parentFD: metadataFD, name: "generated", create: true)
        defer { close(generatedFD) }
        let diagnosticsFD = try openChild(parentFD: generatedFD, name: "diagnostics", create: true)
        defer { close(diagnosticsFD) }

        let filename = "\(prefix)-\(UUID().uuidString)-\(Int(Date().timeIntervalSince1970 * 1000)).txt"
        let fd = filename.withCString { name in
            openat(
                diagnosticsFD,
                name,
                O_WRONLY | O_CREAT | O_EXCL | O_NOFOLLOW | O_CLOEXEC,
                S_IRUSR | S_IWUSR
            )
        }
        guard fd >= 0 else { throw POSIXDiagnosticsError(errno: errno) }

        let handle = FileHandle(fileDescriptor: fd, closeOnDealloc: true)
        var completed = false
        do {
            let contents = Data((lines.joined(separator: "\n") + "\n").utf8)
            guard contents.count <= 128 * 1024 else {
                throw POSIXDiagnosticsError(errno: EFBIG)
            }
            try handle.write(contentsOf: contents)
            try handle.synchronize()
            try handle.close()
            completed = true
        } catch {
            try? handle.close()
            if !completed {
                _ = filename.withCString { name in unlinkat(diagnosticsFD, name, 0) }
            }
            throw error
        }

        // Return only a repository-relative display token. The absolute output
        // path is sensitive and is not part of the standalone diagnostics contract.
        return ".areamatrix/generated/diagnostics/\(filename)"
    }

    private static func openDirectory(path: String) throws -> Int32 {
        guard path.hasPrefix("/") else { throw POSIXDiagnosticsError(errno: EINVAL) }
        try rejectUntrustedSymlinkAncestors(path)
        let fd = path.withCString { pointer in
            open(pointer, O_RDONLY | O_DIRECTORY | O_NOFOLLOW | O_CLOEXEC)
        }
        guard fd >= 0 else { throw POSIXDiagnosticsError(errno: errno) }
        return fd
    }

    private static func rejectUntrustedSymlinkAncestors(_ path: String) throws {
        var current = URL(fileURLWithPath: "/", isDirectory: true)
        for component in path.split(separator: "/") {
            current.appendPathComponent(String(component), isDirectory: true)
            var info = stat()
            let result = current.path.withCString { pointer in
                lstat(pointer, &info)
            }
            if result != 0 {
                if errno == ENOENT { continue }
                throw POSIXDiagnosticsError(errno: errno)
            }
            let isSymlink = (info.st_mode & S_IFMT) == S_IFLNK
            let isAllowedAlias = current.path == "/tmp" || current.path == "/var"
            if isSymlink && !isAllowedAlias {
                throw POSIXDiagnosticsError(errno: ELOOP)
            }
        }
    }

    private static func openChild(parentFD: Int32, name: String, create: Bool) throws -> Int32 {
        var fd = name.withCString { component in
            openat(parentFD, component, O_RDONLY | O_DIRECTORY | O_NOFOLLOW | O_CLOEXEC)
        }
        if fd < 0, errno == ENOENT, create {
            let created = name.withCString { component in mkdirat(parentFD, component, 0o700) }
            guard created == 0 || errno == EEXIST else {
                throw POSIXDiagnosticsError(errno: errno)
            }
            fd = name.withCString { component in
                openat(parentFD, component, O_RDONLY | O_DIRECTORY | O_NOFOLLOW | O_CLOEXEC)
            }
        }
        guard fd >= 0 else { throw POSIXDiagnosticsError(errno: errno) }
        return fd
    }
}

private struct POSIXDiagnosticsError: Error {
    let code: Int32

    init(errno: Int32) {
        code = errno
    }
}

@MainActor
final class RepositorySettingsViewModel: ObservableObject {
    @Published private(set) var state: RepositorySettingsState = .loading
    @Published private(set) var saveError: RepositorySettingsFailure?
    @Published private(set) var diagnosticsState: RepositorySettingsDiagnosticsState = .idle
    @Published private(set) var isSaving = false

    let repoPath: String?
    let appVersion: String
    private let bridge: any MobileRepositoryCoreBridge
    private let capabilityLoader: any PlatformDifferencesCapabilityLoading
    private let diagnosticsExporter: any RepositorySettingsDiagnosticsExporting

    init(
        repoPath: String?,
        appVersion: String = "1",
        bridge: any MobileRepositoryCoreBridge = LiveMobileRepositoryCoreBridge(),
        capabilityLoader: any PlatformDifferencesCapabilityLoading = LivePlatformDifferencesCapabilityBridge(),
        diagnosticsExporter: any RepositorySettingsDiagnosticsExporting = FileRepositorySettingsDiagnosticsExporter()
    ) {
        self.repoPath = repoPath
        self.appVersion = appVersion
        self.bridge = bridge
        self.capabilityLoader = capabilityLoader
        self.diagnosticsExporter = diagnosticsExporter
    }

    var canExportDiagnostics: Bool {
        guard case let .loaded(snapshot) = state else { return false }
        return snapshot.capabilities.securityBookmark.uiEnabled && !diagnosticsState.isExporting
    }

    func load() async {
        guard let repoPath, !repoPath.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            state = .empty
            diagnosticsState = .idle
            return
        }

        state = .loading
        saveError = nil
        do {
            async let config = bridge.loadConfig(repoPath: repoPath)
            async let capabilities = capabilityLoader.getPlatformCapabilities(platform: .ios, appVersion: appVersion)
            async let coreVersion = bridge.getVersion()
            state = try await .loaded(Self.snapshot(
                repoPath: repoPath,
                config: config,
                capabilities: capabilities,
                coreVersion: coreVersion
            ))
        } catch {
            state = .failed(Self.failure(for: error))
            diagnosticsState = .idle
        }
    }

    func saveLocale(_ locale: String) async {
        guard case let .loaded(snapshot) = state, !isSaving else { return }
        var updatedConfig = snapshot.config
        updatedConfig.locale = locale
        await save(updatedConfig)
    }

    func saveFallbackToInbox(_ enabled: Bool) async {
        guard case let .loaded(snapshot) = state, !isSaving else { return }
        var updatedConfig = snapshot.config
        updatedConfig.fallbackToInbox = enabled
        await save(updatedConfig)
    }

    private func save(_ config: MobileRepositoryConfig) async {
        guard let repoPath else { return }
        isSaving = true
        saveError = nil
        defer { isSaving = false }

        do {
            try await bridge.updateConfig(repoPath: repoPath, newConfig: config)
            await load()
        } catch {
            saveError = Self.failure(for: error)
        }
    }

    func exportDiagnostics() async {
        guard case let .loaded(snapshot) = state, canExportDiagnostics else { return }

        diagnosticsState = .exporting
        do {
            diagnosticsState = .exported(try await diagnosticsExporter.export(snapshot: snapshot))
        } catch {
            diagnosticsState = .failed(Self.diagnosticsFailure(for: error))
        }
    }

    private static func snapshot(
        repoPath: String,
        config: MobileRepositoryConfig,
        capabilities: PlatformDifferencesCapabilities,
        coreVersion: String
    ) -> RepositorySettingsSnapshot {
        RepositorySettingsSnapshot(
            name: URL(fileURLWithPath: repoPath).lastPathComponent,
            location: repoPath,
            locationType: locationType(for: repoPath),
            lastOpened: "Unknown",
            coreVersion: coreVersion,
            access: accessText(capabilities.securityBookmark),
            watcher: supportText(capabilities.watcher),
            cloud: cloudText(capabilities.cloudPlaceholder),
            config: config,
            capabilities: capabilities
        )
    }

    private static func locationType(for repoPath: String) -> String {
        let lowercased = repoPath.lowercased()
        if lowercased.contains("mobile documents") || lowercased.contains("icloud") {
            return "iCloud Drive"
        }
        if lowercased.contains("onedrive") {
            return "OneDrive"
        }
        if lowercased.hasPrefix("/volumes/") {
            return "Network mount"
        }
        return "Local folder"
    }

    private static func accessText(_ support: PlatformDifferencesCapabilitySupport) -> String {
        if support.uiEnabled {
            return support.requiresPermission ? "Available, permission required" : "Available"
        }
        return support.reason ?? "Unknown"
    }

    private static func cloudText(_ support: PlatformDifferencesCapabilitySupport) -> String {
        switch support.status {
        case .available, .limited:
            return support.reason ?? support.status.rawValue
        case .notAvailable:
            return "None"
        case .unknown:
            return support.reason ?? "Unknown"
        }
    }

    private static func supportText(_ support: PlatformDifferencesCapabilitySupport) -> String {
        support.reason ?? support.status.rawValue
    }

    private static func failure(for error: Error) -> RepositorySettingsFailure {
        if let repositoryError = error as? MobileRepositoryConnectionError {
            return RepositorySettingsFailure(
                message: repositoryError.message,
                recovery: "Try again or reconnect the repository."
            )
        }
        if let capabilityError = error as? PlatformDifferencesCapabilityError {
            return RepositorySettingsFailure(
                message: capabilityError.localizedDescription,
                recovery: capabilityError.recoverySuggestion
            )
        }
        return RepositorySettingsFailure(
            message: "Could not load repository status",
            recovery: "Try again after the repository is available."
        )
    }

    private static func diagnosticsFailure(for error: Error) -> RepositorySettingsFailure {
        if let repositoryError = error as? MobileRepositoryConnectionError {
            return RepositorySettingsFailure(
                message: "Could not export repository diagnostics",
                recovery: repositoryError.message
            )
        }

        return RepositorySettingsFailure(
            message: "Could not export repository diagnostics",
            recovery: "Retry after repository permissions are available."
        )
    }
}

struct RepositorySettingsView: View {
    @StateObject private var model: RepositorySettingsViewModel
    private let onReconnect: () -> Void
    private let onChooseAnotherFolder: () -> Void
    private let onOpenPlatformCapabilities: () -> Void

    init(
        repoPath: String?,
        bridge: any MobileRepositoryCoreBridge = LiveMobileRepositoryCoreBridge(),
        capabilityLoader: any PlatformDifferencesCapabilityLoading = LivePlatformDifferencesCapabilityBridge(),
        onReconnect: @escaping () -> Void = {},
        onChooseAnotherFolder: @escaping () -> Void = {},
        onOpenPlatformCapabilities: @escaping () -> Void = {}
    ) {
        _model = StateObject(wrappedValue: RepositorySettingsViewModel(
            repoPath: repoPath,
            bridge: bridge,
            capabilityLoader: capabilityLoader
        ))
        self.onReconnect = onReconnect
        self.onChooseAnotherFolder = onChooseAnotherFolder
        self.onOpenPlatformCapabilities = onOpenPlatformCapabilities
    }

    init(
        model: RepositorySettingsViewModel,
        onReconnect: @escaping () -> Void = {},
        onChooseAnotherFolder: @escaping () -> Void = {},
        onOpenPlatformCapabilities: @escaping () -> Void = {}
    ) {
        _model = StateObject(wrappedValue: model)
        self.onReconnect = onReconnect
        self.onChooseAnotherFolder = onChooseAnotherFolder
        self.onOpenPlatformCapabilities = onOpenPlatformCapabilities
    }

    var body: some View {
        List {
            content
        }
        .mobileLibraryListStyle()
        .navigationTitle("Repository Settings")
        .task {
            await model.load()
        }
    }

    @ViewBuilder
    private var content: some View {
        switch model.state {
        case .loading:
            Section {
                HStack {
                    ProgressView()
                    Text("Loading repository settings...")
                }
            }
        case .empty:
            Section {
                Text("No repository connected.")
                Button("Connect Repository", action: onReconnect)
            }
        case let .loaded(snapshot):
            repositorySection(snapshot)
            statusSection(snapshot)
            actionsSection
            diagnosticsSection
            if let saveError = model.saveError {
                errorSection(saveError)
            }
        case let .failed(error):
            errorSection(error)
            Section {
                Button("Try again") {
                    Task { await model.load() }
                }
                Button("Reconnect Repository", action: onReconnect)
            }
        }
    }

    private func repositorySection(_ snapshot: RepositorySettingsSnapshot) -> some View {
        Section("Repository") {
            Text("Name: \(snapshot.name)")
            Text("Location: \(snapshot.location)")
            Text("Type: \(snapshot.locationType)")
            Text("Last opened: \(snapshot.lastOpened)")
            Text("Core version: \(snapshot.coreVersion)")
            Text("Locale: \(snapshot.config.locale)")
        }
    }

    private func statusSection(_ snapshot: RepositorySettingsSnapshot) -> some View {
        Section("Status") {
            Text("Access: \(snapshot.access)")
            Text("Watcher: \(snapshot.watcher)")
            Text("Cloud: \(snapshot.cloud)")
            Toggle("Fallback to Inbox", isOn: fallbackBinding(snapshot))
                .disabled(model.isSaving)
        }
    }

    private var actionsSection: some View {
        Section("Actions") {
            Button("Reconnect Repository", action: onReconnect)
            Button("Choose Another Folder", action: onChooseAnotherFolder)
            Button("Platform capabilities", action: onOpenPlatformCapabilities)
            Button("Export diagnostics") {
                Task { await model.exportDiagnostics() }
            }
                .disabled(!model.canExportDiagnostics)
            Text("Diagnostics do not include user file contents.")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }

    @ViewBuilder
    private var diagnosticsSection: some View {
        switch model.diagnosticsState {
        case .idle:
            EmptyView()
        case .exporting:
            Section("Diagnostics") {
                HStack {
                    ProgressView()
                    Text("Exporting diagnostics...")
                }
            }
        case let .exported(path):
            Section("Diagnostics") {
                Text("Diagnostics exported.")
                Text(path)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        case let .failed(error):
            errorSection(error)
        }
    }

    private func errorSection(_ error: RepositorySettingsFailure) -> some View {
        Section("Status") {
            Label(error.message, systemImage: "exclamationmark.triangle")
                .foregroundStyle(.orange)
            Text(error.recovery)
        }
    }

    private func fallbackBinding(_ snapshot: RepositorySettingsSnapshot) -> Binding<Bool> {
        Binding(
            get: { snapshot.config.fallbackToInbox },
            set: { value in
                Task { await model.saveFallbackToInbox(value) }
            }
        )
    }
}
