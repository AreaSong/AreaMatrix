import Foundation

enum ObservabilitySafetyPolicy {
    enum LocatorClass: Int, Equatable {
        case none
        case fileName
        case fullPath
    }

    enum PrivacyClass: Int, Equatable {
        case `public`
        case pseudonymous
        case sensitive
        case prohibited

        init?(_ value: String) {
            switch value {
            case "public": self = .public
            case "pseudonymous": self = .pseudonymous
            case "sensitive": self = .sensitive
            case "prohibited": self = .prohibited
            default: return nil
            }
        }
    }

    enum BuildScope {
        case liveApp
        case liveCore(expected: ObservabilityBuildContextSnapshot)
        case diagnosticPackage
    }

    enum Violation: Error, Equatable {
        case credentialMaterial
        case invalidAttributeKey
        case invalidPrivacy
        case privacyBelowFloor
        case invalidResource
        case invalidBuildContext
    }

    struct TextAssessment: Equatable {
        let locator: LocatorClass
        let containsCredential: Bool
    }

    struct AttributeAssessment: Equatable {
        let locator: LocatorClass
        let privacy: PrivacyClass
        let minimumPrivacy: PrivacyClass
    }

    static func assess(text: String) -> TextAssessment {
        TextAssessment(
            locator: locatorClass(in: text),
            containsCredential: containsCredentialPattern(text)
        )
    }

    static func assess(
        attribute: ObservabilityAttributeSnapshot
    ) -> Result<AttributeAssessment, Violation> {
        guard validIdentifier(attribute.key) else {
            return .failure(.invalidAttributeKey)
        }
        guard !containsCredentialKey(attribute.key) else {
            return .failure(.credentialMaterial)
        }
        let text = assess(text: attribute.value)
        guard !text.containsCredential else {
            return .failure(.credentialMaterial)
        }
        guard let privacy = PrivacyClass(attribute.privacy), privacy != .prohibited else {
            return .failure(.invalidPrivacy)
        }
        let locator = max(locatorClass(forKey: attribute.key), text.locator)
        let minimumPrivacy = minimumPrivacy(forKey: attribute.key, locator: locator)
        guard privacy.rawValue >= minimumPrivacy.rawValue else {
            return .failure(.privacyBelowFloor)
        }
        return .success(AttributeAssessment(
            locator: locator,
            privacy: privacy,
            minimumPrivacy: minimumPrivacy
        ))
    }

    static func validate(
        resource: ObservabilityResourceSnapshot
    ) -> Result<Void, Violation> {
        guard UUID(uuidString: resource.resourceID) != nil,
              validAlias(resource.alias),
              resource.pathExtension.map(validExtension) ?? true,
              resource.sizeBucket.map(validSizeBucket) ?? true,
              resource.storageMode.map(validStorageMode) ?? true
        else { return .failure(.invalidResource) }
        return .success(())
    }

    static func validate(
        buildContext: ObservabilityBuildContextSnapshot?,
        schemaVersion: UInt64,
        scope: BuildScope
    ) -> Result<Void, Violation> {
        if schemaVersion == 1, case .diagnosticPackage = scope {
            return buildContext == nil ? .success(()) : .failure(.invalidBuildContext)
        }
        guard schemaVersion == 2,
              let buildContext,
              validBuildValue(buildContext.version),
              buildContext.build.map(validBuildValue) ?? true,
              ["debug", "release"].contains(buildContext.configuration),
              buildContext.platform == "macos"
        else { return .failure(.invalidBuildContext) }

        guard validBuildTuple(buildContext) else { return .failure(.invalidBuildContext) }
        switch scope {
        case .liveApp:
            guard buildContext == .currentApp else { return .failure(.invalidBuildContext) }
        case let .liveCore(expected):
            guard expected.producer == "area_matrix_core", buildContext == expected else {
                return .failure(.invalidBuildContext)
            }
        case .diagnosticPackage:
            break
        }
        return .success(())
    }

    static func validIdentifier(_ value: String) -> Bool {
        !value.isEmpty && value.utf8.count <= 128 && value.utf8.allSatisfy {
            isASCIIAlphanumeric($0) || [46, 95, 45].contains($0)
        }
    }

    private static func validBuildTuple(_ context: ObservabilityBuildContextSnapshot) -> Bool {
        switch context.producer {
        case "areamatrix_macos":
            ["arm64", "x86_64"].contains(context.architecture)
        case "area_matrix_core":
            ["aarch64", "x86_64"].contains(context.architecture)
        default:
            false
        }
    }
}

private extension ObservabilitySafetyPolicy {
    static let credentialTerms = Set([
        "authorization", "credential", "password", "passwd", "secret", "token", "apikey",
        "accesstoken", "refreshtoken", "clientsecret", "privatekey"
    ])

    static let credentialMarkers = [
        "authorization:", "authorization=", "auth:", "auth=", "bearer ",
        "api_key", "api-key", "api key", "apikey",
        "access_token", "access-token", "access token", "accesstoken",
        "refresh_token", "refresh-token", "refresh token", "refreshtoken",
        "client_secret", "client-secret", "client secret", "clientsecret", "password:",
        "password=", "passwd:", "passwd=", "token:", "token=", "secret:", "secret=",
        "private_key", "private-key", "private key", "privatekey",
        "-----begin private key", "-----begin rsa private key", "-----begin ec private key",
        "-----begin openssh private key"
    ]

    static func locatorClass(forKey key: String) -> LocatorClass {
        let segments = normalizedKeySegments(key)
        if segments.contains(where: { ["path", "url", "uri", "locator"].contains($0) }) {
            return .fullPath
        }
        if segments.contains("filename") {
            return .fileName
        }
        let userName = segments.last == "name" && segments.first.map {
            ["file", "resource", "source"].contains($0)
        } == true
        return userName ? .fileName : .none
    }

    static func minimumPrivacy(forKey key: String, locator: LocatorClass) -> PrivacyClass {
        guard locator == .none else { return .sensitive }
        let segments = normalizedKeySegments(key)
        let repositoryName = segments.first == "repository" && segments.last == "name"
        return repositoryName ? .sensitive : .public
    }

    static func containsCredentialKey(_ key: String) -> Bool {
        let segments = normalizedKeySegments(key)
        return credentialTerms.contains(segments.joined()) ||
            segments.contains(where: credentialTerms.contains)
    }

    static func normalizedKeySegments(_ key: String) -> [String] {
        let characters = Array(key)
        var segments: [String] = []
        var current = ""
        for index in characters.indices {
            let character = characters[index]
            if character == "." || character == "_" || character == "-" {
                appendSegment(&current, to: &segments)
                continue
            }
            let previous = index > characters.startIndex ? characters[index - 1] : nil
            let next = index + 1 < characters.endIndex ? characters[index + 1] : nil
            let camelBoundary = isASCIIUppercase(character) && !current.isEmpty &&
                (previous.map { isASCIILowercase($0) || isASCIIDigit($0) } == true ||
                    (previous.map(isASCIIUppercase) == true && next.map(isASCIILowercase) == true))
            if camelBoundary { appendSegment(&current, to: &segments) }
            current.append(contentsOf: character.lowercased())
        }
        appendSegment(&current, to: &segments)
        return segments
    }

    static func appendSegment(_ current: inout String, to segments: inout [String]) {
        guard !current.isEmpty else { return }
        segments.append(current)
        current = ""
    }

    static func containsCredentialPattern(_ value: String) -> Bool {
        let normalized = normalizedCredentialText(value)
        return credentialMarkers.contains(where: normalized.contains)
    }

    static func normalizedCredentialText(_ value: String) -> String {
        let source = value.precomposedStringWithCompatibilityMapping.lowercased()
        var normalized = ""
        var pendingWhitespace = false
        for character in source {
            if character.isWhitespace {
                pendingWhitespace = true
                continue
            }
            if character == ":" || character == "=" {
                while normalized.last == " " {
                    normalized.removeLast()
                }
                normalized.append(character)
                pendingWhitespace = false
                continue
            }
            if pendingWhitespace, !normalized.isEmpty {
                normalized.append(" ")
            }
            normalized.append(character)
            pendingWhitespace = false
        }
        return normalized
    }

    static func locatorClass(in value: String) -> LocatorClass {
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, trimmed != "[REDACTED]" else {
            return .none
        }
        if containsFullPath(trimmed) { return .fullPath }
        return containsFilenameToken(trimmed) ? .fileName : .none
    }

    static func containsFullPath(_ value: String) -> Bool {
        if value.hasPrefix("/") || value.hasPrefix("~/") || value.hasPrefix("\\\\") ||
            value.lowercased().hasPrefix("file://") || value.contains("://") {
            return true
        }
        let characters = Array(value)
        for index in characters.indices where isLocatorBoundary(before: index, in: characters) {
            if characters[index] == "/", nextCharacter(after: index, in: characters)?.isWhitespace == false {
                return true
            }
            if characters[index] == "\\", nextCharacter(after: index, in: characters) == "\\",
               character(at: index + 2, in: characters)?.isWhitespace == false {
                return true
            }
            if isASCIIAlphabetic(characters[index]), nextCharacter(after: index, in: characters) == ":",
               let separator = character(at: index + 2, in: characters), separator == "\\" || separator == "/" {
                return true
            }
        }
        return false
    }

    static func isLocatorBoundary(before index: Int, in characters: [Character]) -> Bool {
        guard index > characters.startIndex else { return true }
        let previous = characters[index - 1]
        return previous.isWhitespace || !isASCIIAlphanumeric(previous)
    }

    static func nextCharacter(after index: Int, in characters: [Character]) -> Character? {
        character(at: index + 1, in: characters)
    }

    static func character(at index: Int, in characters: [Character]) -> Character? {
        characters.indices.contains(index) ? characters[index] : nil
    }

    static func containsFilenameToken(_ value: String) -> Bool {
        value.split(whereSeparator: { !isFilenameCharacter($0) }).contains(where: looksLikeFilenameToken)
    }

    static func isFilenameCharacter(_ character: Character) -> Bool {
        character.isLetter || character.isNumber || [".", "_", "-", "\u{3002}", "\u{ff0e}"].contains(character)
    }

    static func looksLikeFilenameToken(_ token: Substring) -> Bool {
        guard !token.isEmpty, token.utf8.count <= 255 else { return false }
        let normalized = token.replacingOccurrences(of: "\u{3002}", with: ".")
            .replacingOccurrences(of: "\u{ff0e}", with: ".")
        if normalized.hasPrefix(".") {
            let hidden = normalized.dropFirst()
            return !hidden.isEmpty && !hidden.contains(".") && hidden.utf8.count <= 32 &&
                hidden.contains(where: \.isLetter)
        }
        guard let dot = normalized.lastIndex(of: ".") else { return false }
        let stem = normalized[..<dot]
        let extensionStart = normalized.index(after: dot)
        let pathExtension = normalized[extensionStart...]
        return !stem.isEmpty && !pathExtension.isEmpty && pathExtension.utf8.count <= 32 &&
            stem.contains(where: { $0.isLetter || $0.isNumber }) &&
            pathExtension.allSatisfy(isASCIIAlphanumeric) && pathExtension.contains(where: isASCIIAlphabetic)
    }

    static func validAlias(_ value: String) -> Bool {
        guard value.hasPrefix("file.") else { return false }
        let digest = value.dropFirst(5)
        return digest.utf8.count == 24 && digest.utf8.allSatisfy {
            (48 ... 57).contains($0) || (97 ... 102).contains($0)
        }
    }

    static func validExtension(_ value: String) -> Bool {
        (1 ... 32).contains(value.utf8.count) && value.utf8.allSatisfy {
            (48 ... 57).contains($0) || (97 ... 122).contains($0)
        }
    }

    static func validSizeBucket(_ value: String) -> Bool {
        ["lt_1mb", "1mb_10mb", "10mb_100mb", "100mb_1gb", "gte_1gb"].contains(value)
    }

    static func validStorageMode(_ value: String) -> Bool {
        ["copied", "moved", "indexed"].contains(value)
    }

    static func validBuildValue(_ value: String) -> Bool {
        !value.isEmpty && value.utf8.count <= 128 && value.utf8.allSatisfy {
            isASCIIAlphanumeric($0) || [46, 95, 45, 43].contains($0)
        }
    }

    static func isASCIIAlphanumeric(_ byte: UInt8) -> Bool {
        (48 ... 57).contains(byte) || (65 ... 90).contains(byte) || (97 ... 122).contains(byte)
    }

    static func isASCIIAlphabetic(_ character: Character) -> Bool {
        character.asciiValue.map { (65 ... 90).contains($0) || (97 ... 122).contains($0) } == true
    }

    static func isASCIIAlphanumeric(_ character: Character) -> Bool {
        character.asciiValue.map(isASCIIAlphanumeric) == true
    }

    static func isASCIIUppercase(_ character: Character) -> Bool {
        character.asciiValue.map { (65 ... 90).contains($0) } == true
    }

    static func isASCIILowercase(_ character: Character) -> Bool {
        character.asciiValue.map { (97 ... 122).contains($0) } == true
    }

    static func isASCIIDigit(_ character: Character) -> Bool {
        character.asciiValue.map { (48 ... 57).contains($0) } == true
    }
}

private func max(
    _ lhs: ObservabilitySafetyPolicy.LocatorClass,
    _ rhs: ObservabilitySafetyPolicy.LocatorClass
) -> ObservabilitySafetyPolicy.LocatorClass {
    lhs.rawValue >= rhs.rawValue ? lhs : rhs
}
