import Foundation
import SwiftUI
import UniformTypeIdentifiers
#if os(iOS)
import UIKit
#endif

@MainActor
final class LibraryListViewModel: ObservableObject {
    @Published private(set) var files: [MobileLibraryFile] = []
    @Published private(set) var categories: [MobileLibraryCategoryRow] = []
    @Published private(set) var needsReview: [MobileLibraryFile] = []
    @Published private(set) var selectedCategory: MobileLibraryCategoryRow?
    @Published private(set) var error: MobileLibraryQueryError?
    @Published private(set) var shareImportReport: ShareImportQueueTakeoverReport?
    @Published private(set) var isLoading = false
    @Published private(set) var isRefreshing = false
    @Published var sort: MobileLibrarySort = .recentlyUpdated {
        didSet { applySort() }
    }

    let repositoryName: String
    let repositoryPath: String

    private let connection: MobileRepositoryConnection
    private let bridge: any MobileLibraryCoreBridge
    private let shareImportConsumer: any ShareImportQueueConsuming
    private var hasLoaded = false

    init(
        connection: MobileRepositoryConnection,
        bridge: any MobileLibraryCoreBridge,
        shareImportConsumer: any ShareImportQueueConsuming = ShareImportQueueConsumer()
    ) {
        self.connection = connection
        self.bridge = bridge
        self.shareImportConsumer = shareImportConsumer
        repositoryPath = connection.validation.repoPath
        repositoryName = Self.name(for: connection)
    }

    var statusText: String {
        if isLoading {
            return "Loading repository..."
        }
        if isRefreshing {
            return "Checking changes..."
        }
        if let error {
            return error.message
        }
        if files.isEmpty, categories.isEmpty {
            return "Repository is empty"
        }
        return "Synced just now"
    }

    var allowReplaceDuringImport: Bool {
        connection.config.allowReplaceDuringImport
    }

    func loadIfNeeded() async {
        guard !hasLoaded else { return }
        await consumeShareImportQueue()
        await reload(isRefresh: false)
    }

    func refresh() async {
        await reload(isRefresh: true)
    }

    func showAllFiles() async {
        selectedCategory = nil
        await reload(isRefresh: true)
    }

    func selectCategory(_ category: MobileLibraryCategoryRow) async {
        selectedCategory = category
        await reload(isRefresh: true)
    }

    private func reload(isRefresh: Bool) async {
        beginLoading(isRefresh: isRefresh)
        let filter = MobileLibraryFileFilter.page(category: selectedCategory?.category)
        do {
            async let treeRequest = bridge.listTree(repoPath: repositoryPath, locale: connection.config.locale)
            async let fileRequest = bridge.listFiles(repoPath: repositoryPath, filter: filter)
            let (tree, loadedFiles) = try await (treeRequest, fileRequest)
            apply(tree: tree, files: loadedFiles)
        } catch {
            self.error = MobileLibraryQueryError.map(error)
        }
        endLoading()
    }

    private func consumeShareImportQueue() async {
        let report = await shareImportConsumer.consumePendingTickets(repoPath: repositoryPath)
        shareImportReport = report.isEmpty ? nil : report
    }

    private func beginLoading(isRefresh: Bool) {
        error = nil
        if hasLoaded || isRefresh {
            isRefreshing = true
        } else {
            isLoading = true
        }
    }

    private func apply(tree: MobileLibraryTreeNode, files: [MobileLibraryFile]) {
        categories = tree.categoryRows
        self.files = sorted(files)
        needsReview = self.files.filter(\.needsReview)
        hasLoaded = true
    }

    private func endLoading() {
        isLoading = false
        isRefreshing = false
    }

    private func applySort() {
        files = sorted(files)
        needsReview = files.filter(\.needsReview)
    }

    private func sorted(_ files: [MobileLibraryFile]) -> [MobileLibraryFile] {
        switch sort {
        case .recentlyUpdated:
            files.sorted { $0.updatedAt > $1.updatedAt }
        case .name:
            files.sorted {
                $0.currentName.localizedStandardCompare($1.currentName) == .orderedAscending
            }
        case .size:
            files.sorted { $0.sizeBytes > $1.sizeBytes }
        }
    }

    private static func name(for connection: MobileRepositoryConnection) -> String {
        if !connection.bookmark.displayName.isEmpty {
            return connection.bookmark.displayName
        }
        return URL(fileURLWithPath: connection.validation.repoPath).lastPathComponent
    }
}

struct MobileLibraryView: View {
    @StateObject private var model: LibraryListViewModel
    @StateObject private var syncConflictModel: SyncConflictEntryViewModel
    @State private var capturedPhoto: CapturedPhotoSelection?
    @State private var filesImportSelection: FilesImportSelection?
    @State private var filesImportPickerError: String?
    @State private var showingCameraCapture = false
    @State private var showingFilesImporter = false
    @State private var cameraCaptureError: SystemCameraCaptureUnavailable?
    private let cameraImportBridge: any CameraImportCoreBridge
    private let filesImportBridge: any FilesImportCoreBridge
    private let detailBridge: any MobileFileDetailCoreBridge
    private let syncConflictBridge: any SyncConflictEntryCoreBridge
    private let onOpenMissingRecovery: (Int64) -> Void
    private let onOpenSyncConflictReview: (SyncConflictEntryReviewRoute) -> Void

    init(
        connection: MobileRepositoryConnection,
        bridge: any MobileLibraryCoreBridge,
        cameraImportBridge: (any CameraImportCoreBridge)? = nil,
        filesImportBridge: (any FilesImportCoreBridge)? = nil,
        shareImportConsumer: (any ShareImportQueueConsuming)? = nil,
        detailBridge: (any MobileFileDetailCoreBridge)? = nil,
        syncConflictBridge: (any SyncConflictEntryCoreBridge)? = nil,
        onOpenMissingRecovery: @escaping (Int64) -> Void = { _ in },
        onOpenSyncConflictReview: @escaping (SyncConflictEntryReviewRoute) -> Void = { _ in }
    ) {
        _model = StateObject(wrappedValue: LibraryListViewModel(
            connection: connection,
            bridge: bridge,
            shareImportConsumer: shareImportConsumer ?? ShareImportQueueConsumer()
        ))
        let conflictBridge = syncConflictBridge ?? LiveMobileRepositoryCoreBridge()
        _syncConflictModel = StateObject(wrappedValue: SyncConflictEntryViewModel(
            repoPath: connection.validation.repoPath,
            bridge: conflictBridge
        ))
        self.cameraImportBridge = cameraImportBridge ?? LiveMobileRepositoryCoreBridge()
        self.filesImportBridge = filesImportBridge ?? LiveMobileRepositoryCoreBridge()
        self.detailBridge = detailBridge ?? LiveMobileRepositoryCoreBridge()
        self.syncConflictBridge = conflictBridge
        self.onOpenMissingRecovery = onOpenMissingRecovery
        self.onOpenSyncConflictReview = onOpenSyncConflictReview
    }

    var body: some View {
        List {
            repositoryStatusSection
            controlsSection
            if let error = model.error {
                errorSection(error)
            }
            if let filesImportPickerError {
                filesImportErrorSection(filesImportPickerError)
            }
            if let cameraCaptureError {
                cameraErrorSection(cameraCaptureError)
            }
            if let report = model.shareImportReport {
                shareImportSection(report)
            }
            syncConflictSection
            filesSection
            categoriesSection
            needsReviewSection
        }
        .mobileLibraryListStyle()
        .navigationTitle(model.repositoryName)
        .toolbar {
            Button {
                Task { await refreshRepository() }
            } label: {
                Image(systemName: "arrow.clockwise")
            }
            .disabled(model.isLoading || model.isRefreshing)
            .accessibilityLabel("Refresh repository")
            Button {
                filesImportPickerError = nil
                showingFilesImporter = true
            } label: {
                Image(systemName: "doc.badge.plus")
            }
            .accessibilityLabel("Import from Files")
            Button {
                Task { await startCameraCapture() }
            } label: {
                Image(systemName: "camera")
            }
            .accessibilityLabel("Take Photo")
        }
        .systemCameraCapture(
            isPresented: $showingCameraCapture,
            onCaptured: { url in
                cameraCaptureError = nil
                capturedPhoto = CapturedPhotoSelection(url: url)
            },
            onUnavailable: { failure in
                cameraCaptureError = failure
            }
        )
        .fileImporter(
            isPresented: $showingFilesImporter,
            allowedContentTypes: [.item],
            allowsMultipleSelection: true,
            onCompletion: handleFilesImportPicker
        )
        .sheet(item: $capturedPhoto) { photo in
            CameraImportReviewSheet(
                repoPath: model.repositoryPath,
                sourceURL: photo.url,
                bridge: cameraImportBridge,
                onCancel: {
                    discardCapturedPhoto(photo)
                },
                onRetake: {
                    discardCapturedPhoto(photo)
                    Task { await startCameraCapture() }
                },
                onImported: { _ in
                    discardCapturedPhoto(photo)
                    Task { await refreshRepository() }
                }
            )
        }
        .sheet(item: $filesImportSelection) { selection in
            FilesImportReviewSheet(
                repoPath: model.repositoryPath,
                selectedURLs: selection.urls,
                bridge: filesImportBridge,
                allowReplaceDuringImport: model.allowReplaceDuringImport,
                onCancel: {
                    filesImportSelection = nil
                },
                onImported: { _ in
                    filesImportSelection = nil
                    Task { await refreshRepository() }
                }
            )
        }
        .refreshable {
            await refreshRepository()
        }
        .task {
            await model.loadIfNeeded()
        }
    }

    private var syncConflictSection: some View {
        SyncConflictEntryMobileHomeSection(
            model: syncConflictModel,
            onReview: onOpenSyncConflictReview
        )
    }

    private var repositoryStatusSection: some View {
        Section {
            VStack(alignment: .leading, spacing: 6) {
                Text(model.repositoryPath)
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
                Label(model.statusText, systemImage: statusSystemImage)
                    .font(.footnote.weight(.medium))
                    .foregroundStyle(statusColor)
            }
            .accessibilityElement(children: .combine)
        }
    }

    private var controlsSection: some View {
        Section {
            Picker("Sort", selection: $model.sort) {
                ForEach(MobileLibrarySort.allCases) { option in
                    Text(option.label).tag(option)
                }
            }
            .pickerStyle(.segmented)

            if model.selectedCategory != nil {
                Button {
                    Task { await model.showAllFiles() }
                } label: {
                    Label("Show all recent files", systemImage: "tray.full")
                }
            }
        }
    }

    private var filesSection: some View {
        Section(fileSectionTitle) {
            if model.isLoading, model.files.isEmpty {
                loadingRows
            } else if model.files.isEmpty {
                emptyFilesView
            } else {
                ForEach(model.files) { file in
                    detailLink(for: file)
                }
            }
        }
    }

    @ViewBuilder
    private var categoriesSection: some View {
        if !model.categories.isEmpty {
            Section("Categories") {
                ForEach(model.categories) { category in
                    Button {
                        Task { await model.selectCategory(category) }
                    } label: {
                        HStack {
                            Text(category.displayName)
                            Spacer()
                            Text("\(category.fileCount)")
                                .foregroundStyle(.secondary)
                        }
                    }
                    .accessibilityLabel("\(category.displayName), \(category.fileCount) files")
                }
            }
        }
    }

    @ViewBuilder
    private var needsReviewSection: some View {
        if !model.needsReview.isEmpty {
            Section("Needs Review") {
                ForEach(model.needsReview) { file in
                    detailLink(for: file)
                }
            }
        }
    }

    private func detailLink(for file: MobileLibraryFile) -> some View {
        NavigationLink {
            MobileFileDetailView(
                repoPath: model.repositoryPath,
                fileID: file.id,
                bridge: detailBridge,
                syncConflictBridge: syncConflictBridge,
                onOpenMissingRecovery: onOpenMissingRecovery,
                onOpenSyncConflictReview: onOpenSyncConflictReview
            )
        } label: {
            MobileLibraryFileRow(file: file)
        }
    }

    private var loadingRows: some View {
        ForEach(0 ..< 3, id: \.self) { _ in
            HStack {
                ProgressView()
                Text("Loading repository...")
                    .foregroundStyle(.secondary)
            }
        }
    }

    private var emptyFilesView: some View {
        Label("No files in this view", systemImage: "tray")
            .foregroundStyle(.secondary)
    }

    private var fileSectionTitle: String {
        if let selectedCategory = model.selectedCategory {
            return selectedCategory.displayName
        }
        return "Recent"
    }

    private var statusSystemImage: String {
        if model.error != nil {
            return "exclamationmark.triangle"
        }
        if model.isLoading || model.isRefreshing {
            return "arrow.triangle.2.circlepath"
        }
        return "checkmark.circle"
    }

    private var statusColor: Color {
        model.error == nil ? .secondary : .orange
    }

    private func errorSection(_ error: MobileLibraryQueryError) -> some View {
        Section {
            Label(error.message, systemImage: "exclamationmark.triangle")
                .font(.footnote)
                .foregroundStyle(.orange)
        }
    }

    private func cameraErrorSection(_ failure: SystemCameraCaptureUnavailable) -> some View {
        Section {
            Label(failure.message, systemImage: "camera")
                .font(.footnote)
                .foregroundStyle(.orange)
            if failure.canOpenSettings {
                Button("Open Settings", action: openAppSettings)
            }
        }
    }

    private func filesImportErrorSection(_ message: String) -> some View {
        Section {
            Label(message, systemImage: "doc.badge.plus")
                .font(.footnote)
                .foregroundStyle(.orange)
        }
    }

    private func shareImportSection(_ report: ShareImportQueueTakeoverReport) -> some View {
        Section("Share Import") {
            if !report.imported.isEmpty {
                Label("\(report.imported.count) shared item imported", systemImage: "square.and.arrow.down")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
            ForEach(report.needsReview) { ticket in
                Label("\(ticket.items.count) queued item needs review in AreaMatrix", systemImage: "exclamationmark.triangle")
                    .font(.footnote)
                    .foregroundStyle(.orange)
            }
            ForEach(report.failed) { failure in
                VStack(alignment: .leading, spacing: 4) {
                    Text(failure.displayName)
                        .font(.footnote.weight(.medium))
                    Text(failure.message)
                        .font(.caption)
                        .foregroundStyle(.orange)
                }
            }
        }
    }

    private func startCameraCapture() async {
        cameraCaptureError = nil
        if let failure = await SystemCameraCaptureAvailability.requestCameraAccess() {
            cameraCaptureError = failure
            return
        }
        showingCameraCapture = true
    }

    private func refreshRepository() async {
        await model.refresh()
        await syncConflictModel.refresh()
    }

    private func openAppSettings() {
        #if os(iOS)
        guard let settingsURL = URL(string: UIApplication.openSettingsURLString) else { return }
        UIApplication.shared.open(settingsURL)
        #endif
    }

    private func handleFilesImportPicker(_ result: Result<[URL], Error>) {
        switch result {
        case let .success(urls):
            filesImportSelection = FilesImportSelection(urls: urls)
        case let .failure(error):
            filesImportPickerError = error.localizedDescription
        }
    }

    private func discardCapturedPhoto(_ photo: CapturedPhotoSelection) {
        SystemCapturedPhotoStore.discardIfOwned(photo.url)
        capturedPhoto = nil
    }
}

private struct CapturedPhotoSelection: Identifiable {
    let id = UUID()
    var url: URL
}
