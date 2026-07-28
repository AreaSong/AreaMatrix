import SwiftUI

struct DiagnosticsTraceDiffView: View {
    let traces: [String: DiagnosticsTraceData]
    let traceIDs: [String]
    let traceRevisionToken: [Int]
    @Binding var baselineID: String
    @Binding var comparisonID: String
    @State private var projection = DiagnosticsTraceDiffProjection(
        onlyBaseline: [], shared: [], onlyComparison: []
    )

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                tracePicker(L10n.string("observability.diff.baseline"), selection: $baselineID)
                Image(systemName: "arrow.left.arrow.right")
                    .accessibilityHidden(true)
                tracePicker(L10n.string("observability.diff.comparison"), selection: $comparisonID)
                Spacer()
            }
            .padding()
            Divider()
            HSplitView {
                signatureColumn(
                    L10n.string("observability.diff.onlyBaseline"),
                    signatures: projection.onlyBaseline
                )
                signatureColumn(L10n.string("observability.diff.shared"), signatures: projection.shared)
                signatureColumn(
                    L10n.string("observability.diff.onlyComparison"),
                    signatures: projection.onlyComparison
                )
            }
        }
        .onAppear(perform: recompute)
        .onChange(of: baselineID) { _, _ in recompute() }
        .onChange(of: comparisonID) { _, _ in recompute() }
        .onChange(of: traceRevisionToken) { _, _ in recompute() }
    }

    private func tracePicker(_ title: String, selection: Binding<String>) -> some View {
        Picker(title, selection: selection) {
            ForEach(traceIDs, id: \.self) { traceID in
                Text(diagnosticsTechnicalText(
                    traceID.diagnosticsShortTechnicalID,
                    reason: .technicalIdentifier
                )).tag(traceID)
            }
        }
        .frame(width: 260)
        .disabled(traceIDs.isEmpty)
    }

    private func signatureColumn(_ title: String, signatures: [String]) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            Text(L10n.format("observability.diff.count.format", title, signatures.count))
                .font(.headline)
                .padding()
            Divider()
            List(signatures, id: \.self) { signature in
                Text(diagnosticsTechnicalText(signature))
                    .font(.caption.monospaced()).textSelection(.enabled)
            }
        }
        .frame(minWidth: 260)
    }

    private func recompute() {
        projection = .compare(
            baseline: traces[baselineID]?.events.map(\.event) ?? [],
            comparison: traces[comparisonID]?.events.map(\.event) ?? []
        )
    }
}

struct DiagnosticsFingerprintView: View {
    let traceID: String
    let fingerprint: String
    let eventCount: Int

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                Label(L10n.string("observability.console.fingerprint"), systemImage: "number.square")
                    .font(.title2.weight(.semibold))
                Text(diagnosticsTechnicalText(fingerprint, reason: .technicalIdentifier))
                    .font(.title3.monospaced())
                    .textSelection(.enabled)
                Divider()
                DiagnosticsTechnicalRow(
                    label: L10n.string("observability.field.trace"),
                    value: traceID
                )
                DiagnosticsTechnicalRow(
                    label: L10n.string("observability.package.events"),
                    value: String(eventCount)
                )
                Text(L10n.string("observability.fingerprint.detail"))
                    .font(.callout)
                    .foregroundStyle(.secondary)
            }
            .padding(28)
            .frame(maxWidth: 720, alignment: .leading)
        }
    }
}
