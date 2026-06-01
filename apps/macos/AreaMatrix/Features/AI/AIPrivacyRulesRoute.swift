import Foundation
import SwiftUI

struct AIPrivacyRulesRoute: Identifiable, Equatable {
    let id = UUID()
    let repoPath: String
    var focus: AIPrivacyRulesRouteFocus?

    init(repoPath: String, focus: AIPrivacyRulesRouteFocus? = nil) {
        self.repoPath = repoPath
        self.focus = focus
    }
}

enum AIPrivacyRulesRouteFocus: Equatable {
    case rule(ruleID: String)
    case field(AiPrivacyInputField)

    var targetID: String {
        switch self {
        case let .rule(ruleID):
            "s309-rule-\(normalizedRuleID(ruleID))"
        case let .field(field):
            "s309-field-\(field)"
        }
    }

    var label: String {
        switch self {
        case let .rule(ruleID):
            "Focused privacy rule \(normalizedRuleID(ruleID))"
        case let .field(field):
            "Focused remote field \(aiPrivacyInputFieldLabel(field))"
        }
    }

    func matches(ruleID: String) -> Bool {
        guard case let .rule(focusedRuleID) = self else { return false }
        return normalizedRuleID(focusedRuleID) == normalizedRuleID(ruleID)
    }

    func matches(field: AiPrivacyInputField) -> Bool {
        self == .field(field)
    }

    private func normalizedRuleID(_ ruleID: String) -> String {
        ruleID.trimmingCharacters(in: .whitespacesAndNewlines)
    }
}

extension AISummaryEditorNotice {
    func s309PrivacyRulesRoute(repoPath: String) -> AIPrivacyRulesRoute? {
        if let ruleID = s309NormalizedPrivacyRuleID {
            return AIPrivacyRulesRoute(repoPath: repoPath, focus: .rule(ruleID: ruleID))
        }
        return privacyField.map { AIPrivacyRulesRoute(repoPath: repoPath, focus: .field($0)) }
    }

    var s309PrivacyRulesRouteAccessibilitySuffix: String? {
        if let ruleID = s309NormalizedPrivacyRuleID { return "privacy-rule-\(ruleID)" }
        return privacyField.map { "privacy-field-\($0)" }
    }

    private var s309NormalizedPrivacyRuleID: String? {
        let ruleID = privacyRuleID?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        return ruleID.isEmpty ? nil : ruleID
    }
}

struct AIPrivacyRulesRouteSheet: View {
    let route: AIPrivacyRulesRoute
    let onConfigureRemoteAI: () -> Void
    let onClose: () -> Void
    @StateObject private var model: AISettingsModel

    init(
        repoPath: String,
        focus: AIPrivacyRulesRouteFocus? = nil,
        onConfigureRemoteAI: @escaping () -> Void = {},
        onClose: @escaping () -> Void = {}
    ) {
        route = AIPrivacyRulesRoute(repoPath: repoPath, focus: focus)
        self.onConfigureRemoteAI = onConfigureRemoteAI
        self.onClose = onClose
        _model = StateObject(wrappedValue: AISettingsModel(repoPath: repoPath))
    }

    var body: some View {
        AIPrivacyRulesRouteView(
            route: route,
            model: model,
            onConfigureRemoteAI: onConfigureRemoteAI,
            onClose: onClose
        )
    }
}

struct AIPrivacyRulesRouteView: View {
    let route: AIPrivacyRulesRoute
    @ObservedObject var model: AISettingsModel
    var registryReader: any AIPrivacyRuleRegistryReading = CoreAIPrivacyRuleRegistryReader()
    let onConfigureRemoteAI: () -> Void
    let onClose: () -> Void

    @State private var registry = AIPrivacyRuleRegistrySnapshot.unavailable
    @State private var loadState = AIPrivacyRulesRegistryLoadState.loading

    var body: some View {
        Group {
            switch loadState {
            case .loading:
                ProgressView("Loading tag and category registry...")
                    .frame(width: 560, height: 260)
            case let .failed(error):
                AISettingsInlineBanner(error: error, tint: .red) {
                    Button("Retry registry", action: retry)
                    Button("Back to AI settings", action: onClose)
                }
                .padding(24)
                .frame(width: 560)
            case .loaded:
                AIPrivacyRulesView(
                    model: model,
                    registry: registry,
                    initialFocus: route.focus,
                    onConfigureRemoteAI: onConfigureRemoteAI,
                    onClose: onClose
                )
            }
        }
        .task(id: route.id) { await loadRegistry() }
    }

    private func retry() {
        Task { await loadRegistry() }
    }

    @MainActor
    private func loadRegistry() async {
        loadState = .loading
        do {
            registry = try await registryReader.loadRegistry(repoPath: route.repoPath)
            loadState = .loaded
        } catch {
            registry = .unavailable
            loadState = .failed(AISettingsError(
                message: "Tag and category registry could not be loaded.",
                recovery: "Retry registry before editing Tag or Category privacy rules.",
                detail: error.localizedDescription
            ))
        }
    }
}

private enum AIPrivacyRulesRegistryLoadState: Equatable {
    case loading
    case loaded
    case failed(AISettingsError)
}

private struct AIPrivacyRulesFocusHighlightModifier: ViewModifier {
    let isActive: Bool
    @State private var isHighlighted = false

    func body(content: Content) -> some View {
        content
            .padding(6)
            .background(Color.accentColor.opacity(isHighlighted ? 0.18 : 0), in: RoundedRectangle(cornerRadius: 6))
            .overlay(RoundedRectangle(cornerRadius: 6).stroke(Color.accentColor.opacity(isHighlighted ? 0.7 : 0)))
            .onAppear { if isActive { pulse() } }
            .onChange(of: isActive) { _, active in if active { pulse() } }
    }

    private func pulse() {
        isHighlighted = true
        Task {
            try? await Task.sleep(nanoseconds: 1_200_000_000)
            await MainActor.run { isHighlighted = false }
        }
    }
}

extension View {
    func aiPrivacyRulesFocusHighlight(_ isActive: Bool) -> some View {
        modifier(AIPrivacyRulesFocusHighlightModifier(isActive: isActive))
    }
}
