import Combine
import Foundation

/// Typed application-level commands shared by menus, platform callbacks and feature hosts.
///
/// The router keeps commands in-process and typed. Platform callbacks also retain pending
/// payloads until a window is ready, so a launch-time Dock or watcher event is not dropped.
@MainActor
final class AppCommandRouter: ObservableObject {
    enum Command: Equatable {
        case importRequested
        case settingsRequested
        case commandPaletteRequested
        case undoHistoryRequested
        case dockOpenRequested
        case externalSyncRequested
        case featureExtensionRequested(id: String)
    }

    static let shared = AppCommandRouter()

    private let subject = PassthroughSubject<Command, Never>()
    private var pendingDockOpenBatches: [[URL]] = []
    private var pendingExternalWindows: [MainExternalSyncWindow] = []
    private var featureExtensionRegistry: FeatureExtensionRuntimeRegistry?

    var commands: AnyPublisher<Command, Never> {
        subject.eraseToAnyPublisher()
    }

    func publish(_ command: Command) {
        subject.send(command)
    }

    func installFeatureExtensionRegistry(_ registry: FeatureExtensionRuntimeRegistry) {
        featureExtensionRegistry = registry
    }

    @discardableResult
    func executeFeatureExtension(id: String) -> Bool {
        featureExtensionRegistry?.execute(id: id) ?? false
    }

    func publishDockOpen(_ urls: [URL]) {
        guard !urls.isEmpty else { return }
        pendingDockOpenBatches.append(urls)
        publish(.dockOpenRequested)
    }

    func takePendingDockOpenBatches() -> [[URL]] {
        defer { pendingDockOpenBatches.removeAll() }
        return pendingDockOpenBatches
    }

    func publishExternalSync(_ window: MainExternalSyncWindow) {
        if let index = pendingExternalWindows.firstIndex(where: { existing in
            existing.repoPath == window.repoPath && existing.cursorWatermark == window.cursorWatermark
        }), let merged = pendingExternalWindows[index].merging(window) {
            pendingExternalWindows[index] = merged
        } else {
            pendingExternalWindows.append(window)
        }
        publish(.externalSyncRequested)
    }

    func takePendingExternalWindows(matchingRepoPath repoPath: String?) -> [MainExternalSyncWindow] {
        guard let repoPath, !repoPath.isEmpty else {
            defer { pendingExternalWindows.removeAll() }
            return pendingExternalWindows.enumerated().sorted { lhs, rhs in
                if lhs.element.cursorWatermark == rhs.element.cursorWatermark { return lhs.offset < rhs.offset }
                return lhs.element.cursorWatermark < rhs.element.cursorWatermark
            }.map(\.element)
        }

        let normalizedRepoPath = URL(fileURLWithPath: repoPath, isDirectory: true).standardizedFileURL.path
        var matchingWindows: [MainExternalSyncWindow] = []
        pendingExternalWindows.removeAll { window in
            guard window.repoPath == normalizedRepoPath else { return false }
            matchingWindows.append(window)
            return true
        }
        return matchingWindows.enumerated().sorted { lhs, rhs in
            if lhs.element.cursorWatermark == rhs.element.cursorWatermark { return lhs.offset < rhs.offset }
            return lhs.element.cursorWatermark < rhs.element.cursorWatermark
        }.map(\.element)
    }
}
