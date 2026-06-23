import SwiftUI

extension CoreErrorSeveritySnapshot {
    var displayName: String {
        switch self {
        case .low: "Low"
        case .medium: "Medium"
        case .high: "High"
        case .critical: "Critical"
        }
    }

    var tint: Color {
        switch self {
        case .low: .yellow
        case .medium: .orange
        case .high: .red
        case .critical: .purple
        }
    }
}

extension CoreErrorRecoverabilitySnapshot {
    var displayName: String {
        switch self {
        case .retryable: "Retryable"
        case .userActionRequired: "User action required"
        case .refreshRequired: "Refresh required"
        case .fatal: "Fatal"
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
        case .checking: "Checking"
        case .passed: "Passed"
        case .warning: "Warning"
        case .failed: "Failed"
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
