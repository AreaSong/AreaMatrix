import AppKit
import SwiftUI

@main
struct AreaMatrixApp: App {
    @NSApplicationDelegateAdaptor(AreaMatrixDockOpenAppDelegate.self) private var appDelegate
    @StateObject private var localizer: AppLocalizer
    @StateObject private var languageStore: AppLanguageStore
    @StateObject private var commandRouter = AppCommandRouter.shared
    private let dependencies = AppDependencyContainer.live
    private let observabilityRuntime = ObservabilityRuntimeAssembly.shared

    init() {
        let commandRouter = AppCommandRouter.shared
        commandRouter.installFeatureExtensionRegistry(
            FeatureManifestRegistry.makeRuntimeRegistry(commandRouter: commandRouter)
        )
        let isRunningTests = ProcessInfo.processInfo.environment["XCTestBundlePath"] != nil
        if !isRunningTests {
            ObservabilityRuntimeAssembly.shared.start()
        }
        let runtime = AppLanguageRuntime.shared
        let localizer = AppLocalizer(runtime: runtime)
        _localizer = StateObject(wrappedValue: localizer)
        let testLanguage: AppLanguage? = isRunningTests ? .en : nil
        _languageStore = StateObject(wrappedValue: AppLanguageStore(
            runtime: runtime,
            localizer: localizer,
            initialLanguageOverride: testLanguage
        ))
    }

    var body: some Scene {
        WindowGroup {
            rootContent
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
                    commandRouter.publish(.importRequested)
                }
                .keyboardShortcut("i", modifiers: [.command])
                Button(localizer.string("app.command.settings")) {
                    AppLogger.shared.logUIAction("app.command.settings.triggered")
                    commandRouter.publish(.settingsRequested)
                }
                .keyboardShortcut(",", modifiers: [.command])
                Divider()
                Button(localizer.string("app.command.commandPalette")) {
                    AppLogger.shared.logUIAction("app.command.command_palette.triggered")
                    commandRouter.publish(.commandPaletteRequested)
                }
                .keyboardShortcut("k", modifiers: [.command])
                Button(localizer.string("app.command.undoHistory")) {
                    AppLogger.shared.logUIAction("app.command.undo_history.triggered")
                    commandRouter.publish(.undoHistoryRequested)
                }
                .keyboardShortcut("z", modifiers: [.command, .option])
            }
        }
    }

    @ViewBuilder
    private var rootContent: some View {
        #if DEBUG
        if let configuration = AreaMatrixDeveloperScenario.current {
            AreaMatrixDeveloperScenarioView(configuration: configuration)
        } else {
            MainWindow(
                dependencies: dependencies,
                observabilityRuntime: observabilityRuntime,
                commandRouter: commandRouter
            )
        }
        #else
        MainWindow(
            dependencies: dependencies,
            observabilityRuntime: observabilityRuntime,
            commandRouter: commandRouter
        )
        #endif
    }
}

@MainActor
enum AreaMatrixImportCommandRelay {
    static func publish() {
        AppCommandRouter.shared.publish(.importRequested)
    }
}

@MainActor
enum AreaMatrixSettingsCommandRelay {
    static func publish() {
        AppCommandRouter.shared.publish(.settingsRequested)
    }
}

@MainActor
enum AreaMatrixCommandPaletteCommandRelay {
    static func publish() {
        AppCommandRouter.shared.publish(.commandPaletteRequested)
    }
}

@MainActor
enum AreaMatrixUndoHistoryCommandRelay {
    static func publish() {
        AppCommandRouter.shared.publish(.undoHistoryRequested)
    }
}

@MainActor
enum AreaMatrixDockOpenRelay {
    static func publish(_ urls: [URL]) {
        AppCommandRouter.shared.publishDockOpen(urls)
    }

    static func takePendingBatches() -> [[URL]] {
        AppCommandRouter.shared.takePendingDockOpenBatches()
    }
}

@MainActor
enum AreaMatrixExternalCreatedFileRelay {
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
        AppCommandRouter.shared.publishExternalSync(window)
    }

    static func takePendingSignals() -> [MainExternalCreatedFileSignal] {
        takePendingWindows(matchingRepoPath: nil).flatMap(\.signals)
    }

    static func takePendingSignals(matchingRepoPath repoPath: String?) -> [MainExternalCreatedFileSignal] {
        takePendingWindows(matchingRepoPath: repoPath).flatMap(\.signals)
    }

    static func takePendingWindows(matchingRepoPath repoPath: String?) -> [MainExternalSyncWindow] {
        AppCommandRouter.shared.takePendingExternalWindows(matchingRepoPath: repoPath)
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
        AppCommandRouter.shared.publishDockOpen(urls)
    }

    func application(_ sender: NSApplication, openFiles filenames: [String]) {
        AppCommandRouter.shared.publishDockOpen(filenames.map(URL.init(fileURLWithPath:)))
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

protocol AppUIActionLogging: Sendable {
    func logUIAction(_ actionID: String, context: AppUIActionContext)

    func recordUIAction(actionID: String, context: AppUIActionContext) async

    func recordUIAction(traceContext: CoreImportTraceContext) async

    func recordSemanticEvent(_ event: ObservabilitySemanticEventInput) async
}

struct AppUIActionContext {
    let severity: AppObservabilitySeverity
    let traceID: String
    let operationID: String
    let retryOfOperationID: String?
    let componentID: String

    init(
        severity: AppObservabilitySeverity = .info,
        traceID: String = UUID().uuidString.lowercased(),
        operationID: String = UUID().uuidString.lowercased(),
        retryOfOperationID: String? = nil,
        componentID: String = "macos.ui"
    ) {
        self.severity = severity
        self.traceID = traceID
        self.operationID = operationID
        self.retryOfOperationID = retryOfOperationID
        self.componentID = componentID
    }

    static var `default`: Self {
        Self()
    }
}

extension AppUIActionLogging {
    func logUIAction(_ actionID: String, context: AppUIActionContext = .default) {
        logUIAction(actionID, context: context)
    }

    func recordUIAction(actionID: String, context: AppUIActionContext = .default) async {
        await recordUIAction(actionID: actionID, context: context)
    }
}

/// Keeps previews and isolated test fixtures free of process-wide observability side effects.
struct NoopAppUIActionLogger: AppUIActionLogging {
    func logUIAction(_: String, context _: AppUIActionContext) {}

    func recordUIAction(actionID _: String, context _: AppUIActionContext) async {}

    func recordUIAction(traceContext _: CoreImportTraceContext) async {}

    func recordSemanticEvent(_: ObservabilitySemanticEventInput) async {}
}

final class AppLogger: AppUIActionLogging {
    static let shared = AppLogger(hub: .shared)

    private let hub: ObservabilityHub

    init(hub: ObservabilityHub) {
        self.hub = hub
    }

    func logUIAction(_ actionID: String, context: AppUIActionContext) {
        Task { await recordUIAction(actionID: actionID, context: context) }
    }

    func recordUIAction(actionID: String, context: AppUIActionContext) async {
        var event = ObservabilitySemanticEventInput(actionID: actionID, componentID: context.componentID)
        event.traceID = context.traceID
        event.operationID = context.operationID
        event.retryOfOperationID = context.retryOfOperationID
        event.severity = context.severity
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

    func recordSemanticEvent(_ event: ObservabilitySemanticEventInput) async {
        await record(event)
    }

    func record(_ event: ObservabilitySemanticEventInput) async {
        await hub.recordSemanticAction(event)
    }
}
