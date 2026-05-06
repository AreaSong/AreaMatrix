import SwiftUI
import UniformTypeIdentifiers

struct ImportDropTargetModifier: ViewModifier {
    let target: ImportDropTarget
    @ObservedObject var dropPreviewModel: ImportDropPreviewModel
    let onDropImport: ([URL], ImportDropTarget) -> Void
    @State private var isTargeted = false

    func body(content: Content) -> some View {
        content
            .background(isTargeted ? Color.accentColor.opacity(0.08) : Color.clear)
            .onDrop(of: [.fileURL], delegate: ImportDropDelegate(
                target: target,
                dropPreviewModel: dropPreviewModel,
                isTargeted: $isTargeted,
                onDropImport: onDropImport
            ))
    }
}

private struct ImportDropDelegate: DropDelegate {
    let target: ImportDropTarget
    let dropPreviewModel: ImportDropPreviewModel
    @Binding var isTargeted: Bool
    let onDropImport: ([URL], ImportDropTarget) -> Void

    func dropEntered(info: DropInfo) {
        isTargeted = true
        loadPreview(from: info)
    }

    func dropUpdated(info: DropInfo) -> DropProposal? {
        DropProposal(operation: .copy)
    }

    func dropExited(info: DropInfo) {
        isTargeted = false
        Task { @MainActor in
            dropPreviewModel.clear()
        }
    }

    func performDrop(info: DropInfo) -> Bool {
        let providers = info.itemProviders(for: [UTType.fileURL.identifier])
        let fileURLProviders = FileDropAdapter.fileURLProviders(from: providers)
        guard !fileURLProviders.isEmpty else {
            Task { @MainActor in
                dropPreviewModel.clear()
            }
            return false
        }

        FileDropAdapter.loadFileURLs(from: fileURLProviders) { urls in
            Task { @MainActor in
                isTargeted = false
                dropPreviewModel.clear()
                onDropImport(urls, target)
            }
        }
        return true
    }

    private func loadPreview(from info: DropInfo) {
        let providers = info.itemProviders(for: [UTType.fileURL.identifier])
        let fileURLProviders = FileDropAdapter.fileURLProviders(from: providers)
        guard !fileURLProviders.isEmpty else {
            Task { @MainActor in
                await dropPreviewModel.preview(target: target, urls: [])
            }
            return
        }

        FileDropAdapter.loadFileURLs(from: fileURLProviders) { urls in
            Task { @MainActor in
                await dropPreviewModel.preview(target: target, urls: urls)
            }
        }
    }
}

struct DropZoneOverlay: View {
    let presentation: ImportDropPreviewPresentation

    var body: some View {
        VStack(spacing: 10) {
            Text(presentation.headline)
                .font(.title3.weight(.semibold))
            Text("导入到：\(presentation.destinationLabel)")
            Text("拖到左侧分类可改变目标")
                .font(.callout)
                .foregroundStyle(.secondary)
            statusLine
        }
        .multilineTextAlignment(.center)
        .padding(.horizontal, 32)
        .padding(.vertical, 24)
        .frame(maxWidth: 420)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 8))
        .overlay {
            RoundedRectangle(cornerRadius: 8)
                .stroke(Color.accentColor, lineWidth: 2)
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel(accessibilityLabel)
    }

    @ViewBuilder
    private var statusLine: some View {
        if presentation.isPredicting {
            Label("Previewing category...", systemImage: "sparkle.magnifyingglass")
                .font(.caption)
                .foregroundStyle(.secondary)
        } else if let warning = presentation.warning {
            Label(warning, systemImage: "exclamationmark.triangle")
                .font(.caption)
                .foregroundStyle(.orange)
        } else if let predictionLabel = presentation.predictionLabel {
            Text(predictionLabel)
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }

    private var accessibilityLabel: String {
        var parts = [
            presentation.headline,
            "导入到：\(presentation.destinationLabel)",
        ]
        if let warning = presentation.warning {
            parts.append(warning)
        } else if let predictionLabel = presentation.predictionLabel {
            parts.append(predictionLabel)
        }
        return parts.joined(separator: ". ")
    }
}
