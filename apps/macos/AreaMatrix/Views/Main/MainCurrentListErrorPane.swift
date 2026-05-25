import SwiftUI

struct MainCurrentListErrorPane: View {
    let error: CoreErrorMappingSnapshot
    let state: MainRepositoryContentState
    let fileListModel: MainFileListModel
    let onRetryCurrentList: () -> Void
    let onCollectDiagnostics: () async -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Label("Current list cannot be loaded", systemImage: "exclamationmark.triangle")
                .font(.headline)
            Text(error.userMessage)
                .foregroundStyle(.secondary)
            Text(error.suggestedAction)
                .font(.callout)
                .foregroundStyle(.secondary)
            actions
            diagnosticsStatus
        }
        .padding(18)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .accessibilityElement(children: .contain)
    }

    private var actions: some View {
        HStack {
            Button("Retry", action: retry)
            Button("Collect Diagnostics...") {
                Task { await collectDiagnostics() }
            }
            .disabled(isCollectingDiagnostics)
            DisclosureGroup("Technical Details") {
                Text(error.rawContext)
                    .font(.system(.caption, design: .monospaced))
                    .textSelection(.enabled)
            }
        }
    }

    private var isCollectingDiagnostics: Bool {
        if case .collecting = fileListModel.diagnosticsState {
            return true
        }
        return false
    }

    @ViewBuilder
    private var diagnosticsStatus: some View {
        switch fileListModel.diagnosticsState {
        case .idle:
            EmptyView()
        case .collecting:
            Label("Preparing diagnostics...", systemImage: "arrow.clockwise")
                .font(.callout)
                .foregroundStyle(.secondary)
        case let .collected(snapshot):
            VStack(alignment: .leading, spacing: 4) {
                Label("Diagnostics collected", systemImage: "doc.badge.gearshape")
                Text(snapshot.snapshotPath)
                    .font(.system(.caption, design: .monospaced))
                    .textSelection(.enabled)
            }
            .font(.callout)
        case let .failed(mapping):
            VStack(alignment: .leading, spacing: 4) {
                Label("Diagnostics could not be collected", systemImage: "exclamationmark.triangle")
                Text(mapping.userMessage)
                Text(mapping.suggestedAction)
                    .foregroundStyle(.secondary)
            }
            .font(.callout)
        }
    }

    private func retry() {
        if state == .list {
            Task { await fileListModel.retryCurrentCategory() }
        } else {
            onRetryCurrentList()
        }
    }

    private func collectDiagnostics() async {
        if state == .list {
            await fileListModel.collectCurrentListDiagnostics()
        } else {
            await onCollectDiagnostics()
        }
    }
}

struct QueryErrorRouteView: View {
    let request: SearchQueryRequestSnapshot
    let diagnostic: SearchQueryDiagnosticSnapshot
    let onApplySuggestion: (String) -> Void
    let onClear: () -> Void
    @State private var isHelpPresented = false
    @State private var applyFailure: String?

    init(
        request: SearchQueryRequestSnapshot,
        diagnostic: SearchQueryDiagnosticSnapshot,
        onApplySuggestion: @escaping (String) -> Void = { _ in },
        onClear: @escaping () -> Void
    ) {
        self.request = request
        self.diagnostic = diagnostic
        self.onApplySuggestion = onApplySuggestion
        self.onClear = onClear
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            inlineDiagnostic
            VStack(alignment: .leading, spacing: 10) {
                Text("Query could not be parsed")
                    .font(.title3.weight(.semibold))
                Text("Fix the highlighted part of your query to continue searching.")
                    .font(.callout)
                    .foregroundStyle(.secondary)
                diagnosticDetails
                actions
            }
            .frame(maxWidth: 440, alignment: .leading)
        }
        .padding(20)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .center)
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("S2-05-query-error")
    }

    private var inlineDiagnostic: some View {
        Label {
            Text(diagnostic.message)
                .font(.callout.weight(.semibold))
        } icon: {
            Image(systemName: "exclamationmark.triangle")
        }
        .foregroundStyle(.red)
        .accessibilityHint(accessibilityHint)
    }

    private var diagnosticDetails: some View {
        VStack(alignment: .leading, spacing: 8) {
            metadataRow("Query", highlightedQuery)
            metadataRow("Problem", diagnostic.problemText)
            if let suggestion = diagnostic.safeSuggestion {
                metadataRow("Suggestion", suggestion)
            }
            if let applyFailure {
                Label(applyFailure, systemImage: "exclamationmark.circle")
                    .font(.caption)
                    .foregroundStyle(.red)
            }
        }
        .padding(12)
        .background(Color.red.opacity(0.08))
        .clipShape(RoundedRectangle(cornerRadius: 8))
    }

    private var actions: some View {
        HStack(spacing: 10) {
            if let suggestion = diagnostic.safeSuggestion {
                Button("Apply suggestion") {
                    applySuggestion(suggestion)
                }
                .keyboardShortcut(.defaultAction)
            }
            Button("Clear query", action: onClear)
                .keyboardShortcut(.cancelAction)
            Button("Open query help") {
                isHelpPresented.toggle()
            }
            .popover(isPresented: $isHelpPresented) {
                QuerySyntaxHintPopover()
            }
        }
    }

    private var highlightedQuery: String {
        QueryTokenHighlighter.highlighted(query: request.query, diagnostic: diagnostic)
    }

    private var accessibilityHint: String {
        [
            diagnostic.problemText,
            diagnostic.safeSuggestion.map { "Suggestion: \($0)" },
            diagnostic.positionText
        ]
        .compactMap { $0 }
        .joined(separator: ". ")
    }

    private func applySuggestion(_ suggestion: String) {
        guard let nextQuery = QuerySuggestionApplier.applying(suggestion, diagnostic: diagnostic, query: request.query) else {
            applyFailure = "Could not apply suggestion"
            return
        }
        applyFailure = nil
        onApplySuggestion(nextQuery)
    }
}

extension MainRepositoryContentView {
    func currentListErrorPane(_ error: CoreErrorMappingSnapshot) -> some View {
        MainCurrentListErrorPane(
            error: error,
            state: state,
            fileListModel: fileListModel,
            onRetryCurrentList: onRetryCurrentList,
            onCollectDiagnostics: onCollectDiagnostics
        )
    }
}

struct QuerySyntaxHintPopover: View {
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Query help")
                .font(.headline)
            Text("Supported fields: kind:, cat:, after:, before:, tag:, note:")
            Text("Use quotes or escape literal colons, such as \"foo:bar\" or foo\\:bar.")
            Text("Loading help...")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .padding(14)
        .frame(width: 300, alignment: .leading)
        .accessibilityIdentifier("S2-05-query-help")
    }
}

struct QueryDiagnosticSummary: View {
    let diagnostic: SearchQueryDiagnosticSnapshot
    let query: String

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Label("Query could not be parsed", systemImage: "exclamationmark.triangle")
                .font(.callout.weight(.semibold))
            metadataRow("Query", QueryTokenHighlighter.highlighted(query: query, diagnostic: diagnostic))
            metadataRow("Problem", diagnostic.problemText)
            if let suggestion = diagnostic.safeSuggestion {
                metadataRow("Suggestion", suggestion)
            }
        }
        .padding(12)
        .background(Color.red.opacity(0.08))
        .clipShape(RoundedRectangle(cornerRadius: 8))
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("S2-05-query-error")
        .accessibilityHint(diagnostic.problemAccessibilityHint)
    }
}

enum QueryTokenHighlighter {
    static func highlighted(query: String, diagnostic: SearchQueryDiagnosticSnapshot) -> String {
        if let start = diagnostic.start,
           let end = diagnostic.end,
           let highlighted = highlightingRange(start: start, end: end, in: query) {
            return highlighted
        }
        guard let token = diagnostic.token, !token.isEmpty, let range = query.range(of: token) else {
            return query
        }
        return highlighting(range: range, in: query)
    }

    private static func highlightingRange(start: Int64, end: Int64, in query: String) -> String? {
        guard start >= 0, end >= start,
              let lower = query.index(query.startIndex, offsetBy: Int(start), limitedBy: query.endIndex),
              let upper = query.index(query.startIndex, offsetBy: Int(end), limitedBy: query.endIndex)
        else { return nil }
        return highlighting(range: lower..<upper, in: query)
    }

    private static func highlighting(range: Range<String.Index>, in query: String) -> String {
        "\(query[..<range.lowerBound])[\(query[range])]\(query[range.upperBound...])"
    }
}

enum QuerySuggestionApplier {
    static func applying(
        _ suggestion: String,
        diagnostic: SearchQueryDiagnosticSnapshot,
        query: String
    ) -> String? {
        let replacement = normalizedSuggestion(suggestion)
        guard !replacement.isEmpty else { return nil }
        if let start = diagnostic.start, let end = diagnostic.end {
            return replacingRange(start: start, end: end, in: query, with: replacement)
        }
        if let token = diagnostic.token, !token.isEmpty {
            return replacingFirstOccurrence(of: token, in: query, with: replacement)
        }
        return nil
    }

    private static func normalizedSuggestion(_ suggestion: String) -> String {
        var value = suggestion.trimmingCharacters(in: .whitespacesAndNewlines)
        if value.lowercased().hasPrefix("use ") {
            value.removeFirst(4)
        }
        return value.trimmingCharacters(in: CharacterSet(charactersIn: "`\" "))
    }

    private static func replacingRange(start: Int64, end: Int64, in query: String, with replacement: String) -> String? {
        guard start >= 0, end >= start,
              let lower = query.index(query.startIndex, offsetBy: Int(start), limitedBy: query.endIndex),
              let upper = query.index(query.startIndex, offsetBy: Int(end), limitedBy: query.endIndex)
        else { return nil }
        var updated = query
        updated.replaceSubrange(lower..<upper, with: replacement)
        return updated
    }

    private static func replacingFirstOccurrence(of token: String, in query: String, with replacement: String) -> String? {
        guard let range = query.range(of: token) else { return nil }
        var updated = query
        updated.replaceSubrange(range, with: replacement)
        return updated
    }
}

private extension SearchQueryDiagnosticSnapshot {
    var safeSuggestion: String? {
        suggestion?.trimmingCharacters(in: .whitespacesAndNewlines).nilIfEmpty
    }

    var problemText: String {
        if let token, !token.isEmpty {
            return "\(kindDisplayName): \(token)"
        }
        return "\(kindDisplayName): \(message)"
    }

    var positionText: String? {
        guard let start else { return nil }
        return end.map { "Position \(start)-\($0)" } ?? "Position \(start)"
    }
}

private extension String {
    var nilIfEmpty: String? {
        isEmpty ? nil : self
    }
}
