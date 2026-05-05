import SwiftUI

struct ImportEntrySheetView: View {
    let request: ImportEntryRequest
    let onCancel: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text(request.sheetTitle)
                .font(.title2.weight(.semibold))
            Text(primaryFileLabel)
                .font(.callout)
                .lineLimit(2)
                .textSelection(.enabled)
            LabeledContent("Destination", value: request.destinationLabel)
            HStack {
                Spacer()
                Button("Cancel", action: onCancel)
                    .keyboardShortcut(.cancelAction)
            }
        }
        .padding(24)
        .frame(minWidth: 420)
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
