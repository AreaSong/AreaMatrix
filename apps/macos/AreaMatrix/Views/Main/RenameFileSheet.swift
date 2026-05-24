import AppKit
import SwiftUI

struct RenameFileSheet: View {
    let file: FileEntrySnapshot?
    let candidateFiles: [FileEntrySnapshot]
    let state: MainFileRenameState
    let onCancel: () -> Void
    let onRename: (Int64, String) -> Void
    let onShowExistingFile: (Int64) -> Void
    @State private var newName: String
    private let editingConfiguration: RenameFilenameEditingConfiguration

    init(
        file: FileEntrySnapshot?,
        candidateFiles: [FileEntrySnapshot],
        state: MainFileRenameState,
        onCancel: @escaping () -> Void,
        onRename: @escaping (Int64, String) -> Void,
        onShowExistingFile: @escaping (Int64) -> Void
    ) {
        self.file = file
        self.candidateFiles = candidateFiles
        self.state = state
        self.onCancel = onCancel
        self.onRename = onRename
        self.onShowExistingFile = onShowExistingFile
        let configuration = RenameFilenameEditingConfiguration(currentName: file?.currentName ?? "")
        editingConfiguration = configuration
        _newName = State(initialValue: configuration.text)
    }

    var initialEditingConfiguration: RenameFilenameEditingConfiguration {
        editingConfiguration
    }

    var body: some View {
        MainFileActionSheetContainer(title: "Rename File", pageID: "S1-33") {
            if let file {
                VStack(alignment: .leading, spacing: 12) {
                    summaryRows(file)
                    filenameField
                    validationStatus(for: file)
                    helperText(for: file)
                    actionButtons(for: file)
                }
            } else {
                MissingFileActionContext(onCancel: onCancel)
            }
        }
    }

    private var filenameField: some View {
        RenameFilenameTextField(
            text: $newName,
            configuration: editingConfiguration,
            isDisabled: state.isRenaming
        )
        .frame(height: 22)
        .accessibilityIdentifier("S1-33-new-name")
        .accessibilityHint(draft.validationMessage ?? "Enter a new file name")
    }

    private func summaryRows(_ file: FileEntrySnapshot) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            metadataRow("Current name", file.currentName)
            metadataRow("Location", file.categoryPathDisplay)
            metadataRow("Storage mode", file.storageMode)
        }
    }

    @ViewBuilder
    private func validationStatus(for file: FileEntrySnapshot) -> some View {
        if state.isRenaming {
            Label("Renaming...", systemImage: "arrow.triangle.2.circlepath")
                .font(.caption)
                .foregroundStyle(.secondary)
        } else if let failure = state.failure(for: file.id) {
            renameFailure(failure)
        } else if let validationMessage = draft.validationMessage {
            FilenameValidationMessage(message: validationMessage)
            if let conflict = draft.conflictingFile {
                Button("Show existing file") {
                    onShowExistingFile(conflict.id)
                }
                .keyboardShortcut("e", modifiers: [.command])
            }
        }
    }

    private func helperText(for file: FileEntrySnapshot) -> some View {
        let indexOnlyPrefix = file.storageMode == "Indexed" ? "Index-only: source files stay in place. " : ""
        return Text("\(indexOnlyPrefix)Only the file name changes. Category and notes stay attached to this file.")
            .font(.caption)
            .foregroundStyle(.secondary)
            .fixedSize(horizontal: false, vertical: true)
    }

    private func actionButtons(for file: FileEntrySnapshot) -> some View {
        HStack {
            Spacer()
            Button("Cancel", action: onCancel)
                .keyboardShortcut(.cancelAction)
                .disabled(state.isRenaming)
            Button(primaryActionTitle(for: file)) {
                onRename(file.id, draft.sanitizedName)
            }
            .disabled(renameDisabled)
            .keyboardShortcut(.defaultAction)
        }
    }

    private func renameFailure(_ failure: CoreErrorMappingSnapshot) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Label(failure.userMessage, systemImage: "exclamationmark.triangle")
                .font(.caption.weight(.semibold))
            Text(failure.suggestedAction)
                .font(.caption)
            Text(failure.rawContext)
                .font(.system(.caption, design: .monospaced))
                .textSelection(.enabled)
        }
        .foregroundStyle(.secondary)
        .padding(10)
        .background(Color.yellow.opacity(0.12))
    }

    private var renameDisabled: Bool {
        state.isRenaming || draft.validationMessage != nil || file == nil
    }

    private func primaryActionTitle(for file: FileEntrySnapshot) -> String {
        if state.isRenaming {
            return "Renaming..."
        }
        if state.failure(for: file.id) != nil {
            return "Retry"
        }
        return "Rename"
    }

    private var draft: RenameFileDraft {
        RenameFileDraft(file: file, candidateFiles: candidateFiles, rawName: newName)
    }
}

struct BatchRenameTrigger: View {
    let repoPath: String
    let fileIDs: [Int64]
    let selectedFiles: [FileEntrySnapshot]
    let selectedCount: Int
    let disabledReason: String?
    let renamer: any CoreBatchRenaming
    let errorMapper: any CoreErrorMapping
    let onApplied: (BatchRenameReportSnapshot) -> Void
    @State private var isPresented = false

    var body: some View {
        Button("Rename...") { isPresented = true }
            .help(BatchRenameEntryPolicy.openHelp(disabledReason: disabledReason))
            .accessibilityIdentifier("S2-14-batch-rename-open")
            .sheet(isPresented: $isPresented) {
                BatchRenameSheet(
                    repoPath: repoPath,
                    fileIDs: fileIDs,
                    selectedFiles: selectedFiles,
                    selectedCount: selectedCount,
                    disabledReason: disabledReason,
                    renamer: renamer,
                    errorMapper: errorMapper,
                    onApplied: onApplied,
                    onClose: { isPresented = false }
                )
            }
    }
}

struct BatchRenameSheet: View {
    let repoPath: String
    let fileIDs: [Int64]
    let selectedFiles: [FileEntrySnapshot]
    let selectedCount: Int
    let disabledReason: String?
    let renamer: any CoreBatchRenaming
    let errorMapper: any CoreErrorMapping
    let onApplied: (BatchRenameReportSnapshot) -> Void
    let onClose: () -> Void
    @State private var draft = BatchRenameRuleDraft()
    @State private var previewState: BatchRenamePreviewState = .idle
    @State private var isApplying = false
    @State private var result: BatchRenameReportSnapshot?
    @State private var failure: CoreErrorMappingSnapshot?

    var body: some View {
        MainFileActionSheetContainer(title: "批量重命名", pageID: "S2-14") {
            selectedCount == 0 ? AnyView(emptyContent) : AnyView(content)
        }
        .task(id: previewTaskKey) { await refreshPreview() }
        .accessibilityIdentifier("S2-14-C2-10-batch-rename-preview")
    }

    private var emptyContent: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("No files selected").foregroundStyle(.secondary)
            HStack { Spacer(); Button("Close", action: onClose) }
        }
    }

    private var content: some View {
        VStack(alignment: .leading, spacing: 12) {
            BatchRenameSelectedFilesSummary(selectedFiles: selectedFiles, selectedCount: selectedCount)
            RenameRuleEditor(draft: $draft, isDisabled: isApplying || disabledReason != nil)
            BatchRenamePreviewSection(
                previewState: previewState,
                validationMessage: draft.validationMessage,
                failure: failure,
                disabledReason: disabledReason
            )
            BatchRenameResultSummary(result: result)
            actionButtons
        }
    }

    private var actionButtons: some View {
        HStack {
            Button("Refresh preview") { Task { await refreshPreview() } }
                .disabled(previewRefreshDisabled)
            Spacer()
            Button("Cancel", action: onClose).keyboardShortcut(.cancelAction).disabled(isApplying)
            Button(isApplying ? "Renaming..." : "Apply") { Task { await apply() } }
                .keyboardShortcut(.defaultAction)
                .disabled(!canApplyPreview)
                .accessibilityIdentifier("S2-14-C2-10-batch-rename-apply")
        }
    }

    @MainActor
    private func refreshPreview() async {
        guard selectedCount > 0, disabledReason == nil, draft.validationMessage == nil else { return }
        previewState = .loading(previous: previewState.displayReport)
        failure = nil
        result = nil
        previewState = await BatchRenameAction.preview(
            repoPath: repoPath,
            fileIDs: fileIDs,
            rule: draft.snapshot,
            renamer: renamer,
            errorMapper: errorMapper
        )
    }

    @MainActor
    private func apply() async {
        guard let preview = previewState.applyReport, canApplyPreview else { return }
        isApplying = true
        failure = nil
        result = nil
        let applyResult = await BatchRenameAction.apply(
            repoPath: repoPath,
            fileIDs: fileIDs,
            preview: preview,
            renamer: renamer,
            errorMapper: errorMapper
        )
        result = applyResult.report
        failure = applyResult.failure
        isApplying = false
        if let report = applyResult.report, report.shouldRefreshConsumerAfterApply { onApplied(report) }
        if let report = applyResult.report, report.shouldCloseSheetAfterApply { onClose() }
    }

    private var canApplyPreview: Bool {
        BatchRenameValidation.canApply(
            fileIDs: fileIDs,
            preview: previewState.applyReport,
            rule: draft.snapshot,
            disabledReason: disabledReason,
            isApplying: isApplying
        )
    }

    private var previewRefreshDisabled: Bool {
        isApplying || disabledReason != nil || draft.validationMessage != nil
    }

    private var previewTaskKey: String {
        [fileIDs.map(String.init).joined(separator: ","), draft.previewKey].joined(separator: "|")
    }
}

private struct BatchRenameSelectedFilesSummary: View {
    let selectedFiles: [FileEntrySnapshot]
    let selectedCount: Int

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Selected: \(selectedCount) files")
            ForEach(selectedFiles.prefix(5)) { file in
                Text(file.currentName).font(.caption).foregroundStyle(.secondary)
            }
        }
        .accessibilityElement(children: .contain)
    }
}

struct RenameFilenameEditingConfiguration: Equatable {
    let text: String
    let initialSelection: RenameFilenameSelection
    let focusesOnAppear: Bool

    init(currentName: String) {
        text = currentName
        initialSelection = .filenameBody(in: currentName)
        focusesOnAppear = true
    }
}

struct RenameFilenameSelection: Equatable {
    let location: Int
    let length: Int

    static func filenameBody(in name: String) -> RenameFilenameSelection {
        let nsName = name as NSString
        let fullLength = nsName.length
        guard fullLength > 0 else {
            return RenameFilenameSelection(location: 0, length: 0)
        }

        let dotRange = nsName.range(of: ".", options: .backwards)
        if dotRange.location > 0, dotRange.location < fullLength - 1 {
            return RenameFilenameSelection(location: 0, length: dotRange.location)
        }

        return RenameFilenameSelection(location: 0, length: fullLength)
    }

    func nsRange(clampedTo text: String) -> NSRange {
        let fullLength = (text as NSString).length
        let clampedLocation = min(max(location, 0), fullLength)
        let clampedLength = min(max(length, 0), fullLength - clampedLocation)
        return NSRange(location: clampedLocation, length: clampedLength)
    }

    func selectedText(in text: String) -> String {
        (text as NSString).substring(with: nsRange(clampedTo: text))
    }

    func unselectedSuffix(in text: String) -> String {
        let nsText = text as NSString
        let range = nsRange(clampedTo: text)
        let suffixLocation = NSMaxRange(range)
        guard suffixLocation < nsText.length else { return "" }
        return nsText.substring(from: suffixLocation)
    }
}

private struct RenameFilenameTextField: NSViewRepresentable {
    @Binding var text: String
    let configuration: RenameFilenameEditingConfiguration
    let isDisabled: Bool

    func makeCoordinator() -> Coordinator {
        Coordinator(text: $text, configuration: configuration)
    }

    func makeNSView(context: Context) -> NSTextField {
        let textField = NSTextField(string: text)
        textField.placeholderString = "New name"
        textField.delegate = context.coordinator
        textField.isBordered = true
        textField.isBezeled = true
        textField.bezelStyle = .roundedBezel
        textField.isEditable = true
        textField.isSelectable = true
        textField.focusRingType = .default
        textField.lineBreakMode = .byTruncatingTail
        return textField
    }

    func updateNSView(_ textField: NSTextField, context: Context) {
        context.coordinator.text = $text
        context.coordinator.configuration = configuration
        if textField.stringValue != text {
            textField.stringValue = text
        }
        textField.isEnabled = !isDisabled
        guard !isDisabled, configuration.focusesOnAppear else { return }
        context.coordinator.applyInitialFocusIfNeeded(to: textField)
    }

    final class Coordinator: NSObject, NSTextFieldDelegate {
        var text: Binding<String>
        var configuration: RenameFilenameEditingConfiguration {
            didSet {
                if oldValue != configuration {
                    didApplyInitialFocus = false
                }
            }
        }

        private var didApplyInitialFocus = false

        init(text: Binding<String>, configuration: RenameFilenameEditingConfiguration) {
            self.text = text
            self.configuration = configuration
        }

        func controlTextDidChange(_ notification: Notification) {
            guard let textField = notification.object as? NSTextField else { return }
            text.wrappedValue = textField.stringValue
        }

        func applyInitialFocusIfNeeded(to textField: NSTextField) {
            guard !didApplyInitialFocus else { return }
            DispatchQueue.main.async { [weak self, weak textField] in
                guard let self, let textField, !self.didApplyInitialFocus else { return }
                textField.window?.makeFirstResponder(textField)
                textField.selectText(nil)
                guard let editor = textField.currentEditor() else { return }
                editor.selectedRange = configuration.initialSelection.nsRange(clampedTo: textField.stringValue)
                didApplyInitialFocus = true
            }
        }
    }
}

struct RenameFileDraft: Equatable {
    var file: FileEntrySnapshot?
    var candidateFiles: [FileEntrySnapshot]
    var rawName: String

    var sanitizedName: String {
        rawName.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    var validationMessage: String? {
        guard let file else { return nil }
        if sanitizedName.isEmpty { return "File name is required" }
        if sanitizedName == "." || sanitizedName == ".." {
            return "File name cannot be \(sanitizedName)"
        }
        if sanitizedName.count > 255 {
            return "File name is too long"
        }
        if let illegalCharacter = illegalCharacter(in: sanitizedName) {
            return "File name cannot contain \"\(illegalCharacter)\""
        }
        if sanitizedName == file.currentName { return "Enter a different file name" }
        if conflictingFile != nil {
            return "A file with this name already exists in \(file.categoryPathDisplay)"
        }
        return nil
    }

    var conflictingFile: FileEntrySnapshot? {
        guard let file, !sanitizedName.isEmpty, illegalCharacter(in: sanitizedName) == nil else { return nil }

        let directory = directoryPath(for: file.path)
        let targetPath = directory.isEmpty ? sanitizedName : "\(directory)/\(sanitizedName)"
        return candidateFiles.first { candidate in
            candidate.id != file.id && candidate.path == targetPath
        }
    }

    private func illegalCharacter(in name: String) -> String? {
        let invalidCharacters = CharacterSet(charactersIn: "/\\:*?\"<>|")
        if let scalar = name.unicodeScalars.first(where: { invalidCharacters.contains($0) }) {
            return String(scalar)
        }
        if name.unicodeScalars.contains(where: CharacterSet.controlCharacters.contains) {
            return "control character"
        }
        return nil
    }

    private func directoryPath(for path: String) -> String {
        path.split(separator: "/").dropLast().joined(separator: "/")
    }
}

struct FilenameValidationMessage: View {
    let message: String

    var body: some View {
        Text(message)
            .font(.caption)
            .foregroundStyle(.secondary)
            .accessibilityIdentifier("S1-33-validation-message")
    }
}
