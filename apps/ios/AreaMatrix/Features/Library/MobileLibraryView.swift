import Foundation
import SwiftUI

@MainActor
final class LibraryListViewModel: ObservableObject {
    @Published private(set) var files: [MobileLibraryFile] = []
    @Published private(set) var categories: [MobileLibraryCategoryRow] = []
    @Published private(set) var needsReview: [MobileLibraryFile] = []
    @Published private(set) var selectedCategory: MobileLibraryCategoryRow?
    @Published private(set) var error: MobileLibraryQueryError?
    @Published private(set) var isLoading = false
    @Published private(set) var isRefreshing = false
    @Published var sort: MobileLibrarySort = .recentlyUpdated {
        didSet { applySort() }
    }

    let repositoryName: String
    let repositoryPath: String

    private let connection: MobileRepositoryConnection
    private let bridge: any MobileLibraryCoreBridge
    private var hasLoaded = false

    init(connection: MobileRepositoryConnection, bridge: any MobileLibraryCoreBridge) {
        self.connection = connection
        self.bridge = bridge
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

    func loadIfNeeded() async {
        guard !hasLoaded else { return }
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

    init(connection: MobileRepositoryConnection, bridge: any MobileLibraryCoreBridge) {
        _model = StateObject(wrappedValue: LibraryListViewModel(connection: connection, bridge: bridge))
    }

    var body: some View {
        List {
            repositoryStatusSection
            controlsSection
            if let error = model.error {
                errorSection(error)
            }
            filesSection
            categoriesSection
            needsReviewSection
        }
        .mobileLibraryListStyle()
        .navigationTitle(model.repositoryName)
        .toolbar {
            Button {
                Task { await model.refresh() }
            } label: {
                Image(systemName: "arrow.clockwise")
            }
            .disabled(model.isLoading || model.isRefreshing)
            .accessibilityLabel("Refresh repository")
        }
        .refreshable {
            await model.refresh()
        }
        .task {
            await model.loadIfNeeded()
        }
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
                    MobileLibraryFileRow(file: file)
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
                    MobileLibraryFileRow(file: file)
                }
            }
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
}

private struct MobileLibraryFileRow: View {
    let file: MobileLibraryFile

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: fileIcon)
                .foregroundStyle(file.needsReview ? .orange : .secondary)
                .frame(width: 24)
            VStack(alignment: .leading, spacing: 4) {
                Text(file.currentName)
                    .font(.headline)
                Text(file.categoryPath)
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
            Spacer()
            Text(statusText)
                .font(.caption.weight(.medium))
                .foregroundStyle(file.needsReview ? .orange : .secondary)
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel(accessibilityLabel)
    }

    private var fileIcon: String {
        file.needsReview ? "exclamationmark.triangle" : "doc"
    }

    private var statusText: String {
        if file.needsReview {
            return file.availability.statusText
        }
        return ByteCountFormatter.string(fromByteCount: file.sizeBytes, countStyle: .file)
    }

    private var accessibilityLabel: String {
        "\(file.currentName), \(file.categoryPath), \(file.availability.statusText)"
    }
}

private extension View {
    @ViewBuilder
    func mobileLibraryListStyle() -> some View {
        #if os(iOS)
        listStyle(.insetGrouped)
        #else
        listStyle(.inset)
        #endif
    }
}
