import SwiftUI

extension CoreErrorSeveritySnapshot {
    var tint: Color {
        switch self {
        case .low: .yellow
        case .medium: .orange
        case .high: .red
        case .critical: .purple
        }
    }
}

enum ValidatePathCheckStatus: Equatable {
    case checking
    case passed
    case warning
    case failed

    var text: String {
        switch self {
        case .checking: L10n.string("Checking")
        case .passed: L10n.string("Passed")
        case .warning: L10n.string("Warning")
        case .failed: L10n.string("Failed")
        }
    }

    var systemImage: String {
        switch self {
        case .checking: "clock"
        case .passed: "checkmark.circle.fill"
        case .warning: "exclamationmark.triangle.fill"
        case .failed: "xmark.octagon.fill"
        }
    }

    var tint: Color {
        switch self {
        case .checking: .secondary
        case .passed: .green
        case .warning: .orange
        case .failed: .red
        }
    }
}
