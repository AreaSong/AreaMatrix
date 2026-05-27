import Foundation

extension StorageMode {
    var fileListDisplayName: String {
        switch self {
        case .moved:
            "Moved"
        case .copied:
            "Copied"
        case .indexed:
            "Indexed"
        }
    }
}

extension SearchMatchField {
    var displayName: String {
        switch self {
        case .name:
            "Name"
        case .path:
            "Path"
        case .note:
            "Note"
        case .category:
            "Category"
        case .changeLog:
            "Change log"
        }
    }
}

extension SearchMatchKind {
    var displayName: String {
        switch self {
        case .exact:
            "Exact match"
        case .fuzzy:
            "Fuzzy match"
        case .pinyinInitials:
            "Pinyin initials"
        }
    }
}

extension SearchDiagnosticKind {
    var displayName: String {
        switch self {
        case .unclosedQuote: "Unclosed quote"
        case .unknownField: "Unknown field"
        case .invalidDate: "Invalid date"
        case .unbalancedParentheses: "Unbalanced parentheses"
        case .invalidOperator: "Invalid operator"
        }
    }
}

extension SearchDiagnosticSeverity {
    var displayName: String {
        switch self {
        case .info: "Info"
        case .warning: "Warning"
        case .error: "Error"
        }
    }
}

extension FileOrigin {
    var fileListDisplayName: String {
        switch self {
        case .imported:
            "Imported"
        case .adopted:
            "Adopted"
        case .external:
            "External"
        }
    }
}
