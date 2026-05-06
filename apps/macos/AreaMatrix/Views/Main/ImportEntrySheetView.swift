import SwiftUI

struct ImportEntrySheetView: View {
    let request: ImportEntryRequest
    let onCancel: () -> Void

    @StateObject private var previewModel: ImportSingleFilePreviewModel
    @State private var isReasonPopoverPresented = false

    init(
        request: ImportEntryRequest,
        onCancel: @escaping () -> Void,
        categoryPredictor: any CoreCategoryPredicting = CoreBridge()
    ) {
        self.request = request
        self.onCancel = onCancel
        _previewModel = StateObject(wrappedValue: ImportSingleFilePreviewModel(predictor: categoryPredictor))
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text(request.sheetTitle)
                .font(.title2.weight(.semibold))

            if request.kind == .singleFile {
                singleFilePreview
            } else {
                genericImportSummary
            }

            footer
        }
        .padding(24)
        .frame(minWidth: 480)
        .task(id: request.id) {
            await previewModel.load(request: request)
        }
    }

    private var singleFilePreview: some View {
        VStack(alignment: .leading, spacing: 12) {
            fileInformation
            classifyControls
            previewStatus
        }
    }

    private var fileInformation: some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: "doc")
                .font(.title2)
                .frame(width: 32, height: 32)
            VStack(alignment: .leading, spacing: 4) {
                Text(previewModel.source?.fileName ?? primaryFileLabel)
                    .font(.headline)
                    .lineLimit(2)
                Text(previewModel.source?.sourcePath ?? request.destinationLabel)
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
                    .textSelection(.enabled)
            }
        }
    }

    private var classifyControls: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .firstTextBaseline) {
                Picker("建议分类", selection: $previewModel.selectedCategory) {
                    ForEach(categoryOptions, id: \.self) { category in
                        Text(category).tag(category)
                    }
                }
                .frame(maxWidth: 240)

                Button("为什么？") {
                    isReasonPopoverPresented.toggle()
                }
                .disabled(previewModel.prediction == nil)
                .popover(isPresented: $isReasonPopoverPresented) {
                    Text(previewModel.reasonSummary)
                        .padding()
                        .frame(minWidth: 180)
                }
            }

            TextField("建议命名", text: $previewModel.suggestedName)
                .textFieldStyle(.roundedBorder)
        }
    }

    private var previewStatus: some View {
        HStack(spacing: 8) {
            if previewModel.status.isLoading {
                ProgressView()
                    .controlSize(.small)
            }

            if let message = previewModel.status.message {
                Text(message)
                    .font(.callout)
                    .foregroundStyle(previewStatusStyle)
            }
        }
        .accessibilityElement(children: .combine)
    }

    private var footer: some View {
        HStack {
            Spacer()
            Button("Cancel", action: onCancel)
                .keyboardShortcut(.cancelAction)
        }
    }

    private var genericImportSummary: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(primaryFileLabel)
                .font(.callout)
                .lineLimit(2)
                .textSelection(.enabled)
            LabeledContent("Destination", value: request.destinationLabel)
        }
    }

    private var categoryOptions: [String] {
        var values = [previewModel.selectedCategory, previewModel.prediction?.category, "inbox"]
        var uniqueValues: [String] = []
        for value in values.compactMap({ $0 }).filter({ !$0.isEmpty }) {
            if !uniqueValues.contains(value) {
                uniqueValues.append(value)
            }
        }
        return uniqueValues
    }

    private var previewStatusStyle: Color {
        if case .failed = previewModel.status {
            return .red
        }
        if case .unsupported = previewModel.status {
            return .secondary
        }
        return .secondary
    }

    private var primaryFileLabel: String {
        guard let firstURL = request.urls.first else {
            return "No valid file URL"
        }

        if request.urls.count == 1 {
            return firstURL.path
        }

        return "\(firstURL.path) and \(request.urls.count - 1) more"
    }
}
