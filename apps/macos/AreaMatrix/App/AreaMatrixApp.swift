import SwiftUI

@main
struct AreaMatrixApp: App {
    var body: some Scene {
        WindowGroup {
            MainWindow()
        }
        .windowResizability(.contentMinSize)
    }
}

struct MainLoadingView: View {
    let repoPath: String
    let onChooseAnotherFolder: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            ProgressView()
                .controlSize(.large)
            Text("Opening repository...")
                .font(.title2.weight(.semibold))
            Text(repoPath)
                .font(.system(.body, design: .monospaced))
                .textSelection(.enabled)
                .lineLimit(2)
            Button("Choose another folder", action: onChooseAnotherFolder)
        }
        .padding(48)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .center)
    }
}

struct MainRepoErrorView: View {
    let repoPath: String
    let mapping: CoreErrorMappingSnapshot?
    let onChooseAnotherFolder: () -> Void

    var body: some View {
        ContentUnavailableView {
            Label("Repository cannot be opened", systemImage: "exclamationmark.triangle")
        } description: {
            Text(mapping?.userMessage ?? "AreaMatrix could not open the selected repository.")
            Text(repoPath)
        } actions: {
            Button("Choose another folder", action: onChooseAnotherFolder)
        }
    }
}

struct DBRepairConfirmView: View {
    let repoPath: String
    let scanSession: ScanSessionSnapshot?
    let mapping: CoreErrorMappingSnapshot?
    let onChooseAnotherFolder: () -> Void

    var body: some View {
        ContentUnavailableView {
            Label("Repository metadata needs repair", systemImage: "wrench.and.screwdriver")
        } description: {
            Text(mapping?.userMessage ?? "AreaMatrix found incomplete or damaged .areamatrix metadata.")
            Text(
                "Repair only affects .areamatrix/ metadata; user files are not moved, renamed, deleted, or overwritten."
            )
            if let scanSession {
                Text("Last scan: \(scanSession.status.rawValue), inserted \(scanSession.inserted).")
            }
            Text(repoPath)
        } actions: {
            Button("Choose another folder", action: onChooseAnotherFolder)
        }
    }
}

struct RepositoryReadyView: View {
    let config: RepoConfigSnapshot

    var body: some View {
        ContentUnavailableView {
            Label("Repository ready", systemImage: "checkmark.circle")
        } description: {
            Text(config.repoPath)
            Text("Locale: \(config.locale)")
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}
