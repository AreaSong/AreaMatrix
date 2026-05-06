import SwiftUI

struct ImportBatchNamingOptionsSection: View {
    @Binding var selectedStrategy: ImportBatchNamingStrategy
    @Binding var prefix: String
    let isDisabled: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Picker("命名策略", selection: $selectedStrategy) {
                ForEach(ImportBatchNamingStrategy.allCases) { strategy in
                    Text(strategy.title).tag(strategy)
                }
            }
            .pickerStyle(.segmented)
            .disabled(isDisabled)

            if selectedStrategy == .uniformPrefix {
                TextField("统一前缀", text: $prefix)
                    .textFieldStyle(.roundedBorder)
                    .frame(maxWidth: 260)
                    .disabled(isDisabled)
            }
        }
    }
}
