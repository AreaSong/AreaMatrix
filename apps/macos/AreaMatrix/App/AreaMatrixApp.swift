import AppKit
import SwiftUI

@main
struct AreaMatrixApp: App {
    @NSApplicationDelegateAdaptor(AreaMatrixDockOpenAppDelegate.self) private var appDelegate
    @StateObject private var localizer: AppLocalizer
    @StateObject private var languageStore: AppLanguageStore

    init() {
        ObservabilityRuntimeAssembly.shared.start()
        let runtime = AppLanguageRuntime.shared
        let localizer = AppLocalizer(runtime: runtime)
        _localizer = StateObject(wrappedValue: localizer)
        let testLanguage: AppLanguage? = ProcessInfo.processInfo.environment["XCTestBundlePath"] == nil ? nil : .en
        _languageStore = StateObject(wrappedValue: AppLanguageStore(
            runtime: runtime,
            localizer: localizer,
            initialLanguageOverride: testLanguage
        ))
    }

    var body: some Scene {
        WindowGroup {
            MainWindow()
                .environmentObject(languageStore)
                .environmentObject(localizer)
                .environment(\.locale, Locale(identifier: localizer.resourceLocaleIdentifier))
        }
        .windowStyle(.hiddenTitleBar)
        .windowResizability(.contentSize)
        .commands {
            CommandGroup(after: .sidebar) {
                Button(localizer.string("app.command.import")) {
                    AppLogger.shared.logUIAction("app.command.import.triggered")
                    AreaMatrixImportCommandRelay.publish()
                }
                .keyboardShortcut("i", modifiers: [.command])
                Button(localizer.string("app.command.settings")) {
                    AppLogger.shared.logUIAction("app.command.settings.triggered")
                    AreaMatrixSettingsCommandRelay.publish()
                }
                .keyboardShortcut(",", modifiers: [.command])
                Divider()
                Button(localizer.string("app.command.commandPalette")) {
                    AppLogger.shared.logUIAction("app.command.command_palette.triggered")
                    AreaMatrixCommandPaletteCommandRelay.publish()
                }
                .keyboardShortcut("k", modifiers: [.command])
                Button(localizer.string("app.command.undoHistory")) {
                    AppLogger.shared.logUIAction("app.command.undo_history.triggered")
                    AreaMatrixUndoHistoryCommandRelay.publish()
                }
                .keyboardShortcut("z", modifiers: [.command, .option])
            }
        }
    }
}

@MainActor
enum AreaMatrixImportCommandRelay {
    static let notification = Notification.Name("AreaMatrixImportCommandRelay.notification")

    static func publish() {
        NotificationCenter.default.post(name: notification, object: nil)
    }
}

@MainActor
enum AreaMatrixSettingsCommandRelay {
    static let notification = Notification.Name("AreaMatrixSettingsCommandRelay.notification")

    static func publish() {
        NotificationCenter.default.post(name: notification, object: nil)
    }
}

@MainActor
enum AreaMatrixCommandPaletteCommandRelay {
    static let notification = Notification.Name("AreaMatrixCommandPaletteCommandRelay.notification")

    static func publish() {
        NotificationCenter.default.post(name: notification, object: nil)
    }
}

@MainActor
enum AreaMatrixUndoHistoryCommandRelay {
    static let notification = Notification.Name("AreaMatrixUndoHistoryCommandRelay.notification")

    static func publish() {
        NotificationCenter.default.post(name: notification, object: nil)
    }
}

@MainActor
enum AreaMatrixDockOpenRelay {
    static let notification = Notification.Name("AreaMatrixDockOpenRelay.notification")
    private static var pendingBatches: [[URL]] = []

    static func publish(_ urls: [URL]) {
        pendingBatches.append(urls)
        NotificationCenter.default.post(name: notification, object: nil)
    }

    static func takePendingBatches() -> [[URL]] {
        let batches = pendingBatches
        pendingBatches.removeAll()
        return batches
    }
}

@MainActor
enum AreaMatrixExternalCreatedFileRelay {
    static let notification = Notification.Name("AreaMatrixExternalCreatedFileRelay.notification")
    private static var pendingWindows: [MainExternalSyncWindow] = []

    static func publish(
        kind: MainExternalSyncEventKind = .created,
        repoPath: String,
        relativePath: String,
        fsEventID: Int64
    ) {
        guard let signal = MainExternalCreatedFileSignal(
            kind: kind,
            repoPath: repoPath,
            relativePath: relativePath,
            fsEventID: fsEventID
        ) else { return }

        publish([signal])
    }

    static func publish(_ signals: [MainExternalCreatedFileSignal]) {
        guard !signals.isEmpty else { return }
        var windows: [MainExternalSyncWindow] = []
        for signal in signals {
            guard let window = MainExternalSyncWindow(signals: [signal]) else { continue }
            if let index = windows.firstIndex(where: { existing in
                existing.repoPath == window.repoPath && existing.cursorWatermark == window.cursorWatermark
            }), let merged = windows[index].merging(window) {
                windows[index] = merged
            } else {
                windows.append(window)
            }
        }
        for window in windows {
            publish(window)
        }
    }

    static func publish(_ window: MainExternalSyncWindow) {
        if let index = pendingWindows.firstIndex(where: { existing in
            existing.repoPath == window.repoPath && existing.cursorWatermark == window.cursorWatermark
        }), let merged = pendingWindows[index].merging(window) {
            pendingWindows[index] = merged
        } else {
            pendingWindows.append(window)
        }
        NotificationCenter.default.post(name: notification, object: nil)
    }

    static func takePendingSignals() -> [MainExternalCreatedFileSignal] {
        let windows = pendingWindows
        pendingWindows.removeAll()
        return windows.flatMap(\.signals)
    }

    static func takePendingSignals(matchingRepoPath repoPath: String?) -> [MainExternalCreatedFileSignal] {
        takePendingWindows(matchingRepoPath: repoPath).flatMap(\.signals)
    }

    static func takePendingWindows(matchingRepoPath repoPath: String?) -> [MainExternalSyncWindow] {
        guard let repoPath, !repoPath.isEmpty else { return [] }

        let normalizedRepoPath = URL(fileURLWithPath: repoPath, isDirectory: true).standardizedFileURL.path
        var matchingWindows: [MainExternalSyncWindow] = []
        pendingWindows.removeAll { window in
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

private extension MainExternalSyncWindow {
    var signals: [MainExternalCreatedFileSignal] {
        events.compactMap { event in
            MainExternalCreatedFileSignal(
                kind: event.kind,
                repoPath: repoPath,
                relativePath: event.relativePath,
                fsEventID: event.fsEventID,
                cursorWatermark: cursorWatermark
            )
        }
    }
}

@MainActor
final class AreaMatrixDockOpenAppDelegate: NSObject, NSApplicationDelegate {
    /// 监听系统外观变化，动态切换 Dock 图标
    private var appearanceObservation: NSKeyValueObservation?
    private let observabilityLifecycle = ObservabilityApplicationLifecycle()

    func applicationDidFinishLaunching(_: Notification) {
        updateDockIcon()
        appearanceObservation = NSApp.observe(
            \.effectiveAppearance, options: [.new]
        ) { [weak self] _, _ in
            DispatchQueue.main.async {
                self?.updateDockIcon()
            }
        }
    }

    func application(_: NSApplication, open urls: [URL]) {
        AreaMatrixDockOpenRelay.publish(urls)
    }

    func application(_ sender: NSApplication, openFiles filenames: [String]) {
        AreaMatrixDockOpenRelay.publish(filenames.map(URL.init(fileURLWithPath:)))
        sender.reply(toOpenOrPrint: .success)
    }

    func applicationShouldTerminate(_ sender: NSApplication) -> NSApplication.TerminateReply {
        observabilityLifecycle.beginTermination(
            stop: { await ObservabilityRuntimeAssembly.shared.stop() },
            reply: { sender.reply(toApplicationShouldTerminate: true) }
        )
    }

    /// 根据系统深浅色切换 Dock / Finder 图标
    private func updateDockIcon() {
        let isDark = NSApp.effectiveAppearance
            .bestMatch(from: [.darkAqua, .aqua]) == .darkAqua
        let imageName = isDark
            ? "AreaMatrixLogoMarkDark"
            : "AreaMatrixLogoMarkLight"
        if let image = NSImage(named: imageName) {
            NSApp.applicationIconImage = image
        }
    }
}

import Foundation

final class AppLogger: Sendable {
    static let shared = AppLogger()

    private let hub: ObservabilityHub

    init(hub: ObservabilityHub = .shared) {
        self.hub = hub
    }

    func logUIAction(
        _ actionID: String,
        severity: AppObservabilitySeverity = .info,
        traceID: String = UUID().uuidString.lowercased(),
        operationID: String = UUID().uuidString.lowercased(),
        retryOfOperationID: String? = nil,
        componentID: String = "macos.ui"
    ) {
        Task {
            await recordUIAction(
                actionID: actionID,
                severity: severity,
                componentID: componentID,
                traceID: traceID,
                operationID: operationID,
                retryOfOperationID: retryOfOperationID
            )
        }
    }

    func recordUIAction(
        actionID: String,
        severity: AppObservabilitySeverity = .info,
        componentID: String = "macos.ui",
        traceID: String = UUID().uuidString.lowercased(),
        operationID: String = UUID().uuidString.lowercased(),
        retryOfOperationID: String? = nil
    ) async {
        var event = ObservabilitySemanticEventInput(actionID: actionID, componentID: componentID)
        event.traceID = traceID
        event.operationID = operationID
        event.retryOfOperationID = retryOfOperationID
        event.severity = severity
        await record(event)
    }

    func recordUIAction(traceContext: CoreImportTraceContext) async {
        var event = ObservabilitySemanticEventInput(
            actionID: traceContext.actionID,
            componentID: traceContext.componentID
        )
        event.traceID = traceContext.traceID
        event.spanID = traceContext.spanID
        event.operationID = traceContext.operationID
        event.retryOfOperationID = traceContext.retryOfOperationID
        event.phase = "started"
        event.outcome = "started"
        await record(event)
    }

    func record(_ event: ObservabilitySemanticEventInput) async {
        await hub.recordSemanticAction(event)
    }
}
