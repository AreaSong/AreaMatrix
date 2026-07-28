import Foundation

struct DiagnosticPackageRedactionResult {
    let events: [ObservabilityEventSnapshot]
    let redacted: Int
    let rejected: Int
}

enum DiagnosticPackageRedactor {
    static let redactedValue = "[REDACTED]"

    static func redact(
        _ events: [ObservabilityEventSnapshot],
        selection: DiagnosticPackagePrivacySelection
    ) throws -> DiagnosticPackageRedactionResult {
        guard selection.isValid else { throw DiagnosticPackageError.invalidPackage }
        var output: [ObservabilityEventSnapshot] = []
        var redactedCount = 0
        var rejectedCount = 0
        output.reserveCapacity(events.count)

        for event in events {
            try validateSchema(event)
            guard event.privacy != "prohibited",
                  !event.attributes.contains(where: { $0.privacy == "prohibited" })
            else {
                rejectedCount += 1
                continue
            }
            try validatePrivacyLabels(event)
            try validateCredentialFree(event)
            let result = try redactEvent(event, selection: selection)
            output.append(result.event)
            redactedCount += result.redactedCount
        }
        return DiagnosticPackageRedactionResult(
            events: output,
            redacted: redactedCount,
            rejected: rejectedCount
        )
    }

    static func sanitizedSummary(_ summary: String) throws -> String {
        let bounded = String(summary.prefix(8192))
        let assessment = ObservabilitySafetyPolicy.assess(text: bounded)
        guard !assessment.containsCredential else { throw DiagnosticPackageError.redactionFailed }
        return assessment.locator == .none ? bounded : redactedValue
    }

    static func validateExportedEvents(
        _ events: [ObservabilityEventSnapshot],
        selection: DiagnosticPackagePrivacySelection
    ) throws {
        guard selection.isValid else { throw DiagnosticPackageError.invalidPackage }
        for event in events {
            try validateSchema(event)
            guard event.privacy != "prohibited",
                  event.attributes.allSatisfy({ $0.privacy != "prohibited" })
            else { throw DiagnosticPackageError.invalidPackage }
            try validatePrivacyLabels(event)
            try validateCredentialFree(event)
            try validateNoUnstructuredLocators(event)
            try validateRedactionState(event, selection: selection)
        }
    }

    static func validateCredentialFree(_ values: [String]) throws {
        guard !values.map(ObservabilitySafetyPolicy.assess).contains(where: \.containsCredential) else {
            throw DiagnosticPackageError.redactionFailed
        }
    }

    private static func redactEvent(
        _ source: ObservabilityEventSnapshot,
        selection: DiagnosticPackagePrivacySelection
    ) throws -> (event: ObservabilityEventSnapshot, redactedCount: Int) {
        var event = source
        var redactedCount = 0
        event.attributes = try source.attributes.map { attribute in
            var attribute = attribute
            let assessment = try policyValue(ObservabilitySafetyPolicy.assess(attribute: attribute))
            if attribute.privacy == "sensitive", !selection.allowsSensitiveAttribute(assessment) {
                redactedCount += replaceWithRedaction(&attribute.value)
            }
            return attribute
        }
        if var error = event.error, error.technicalDetails != nil {
            redactedCount += replaceWithRedaction(&error.technicalDetails)
            event.error = error
        }
        redactedCount += redactUnstructuredLocator(&event.message)
        redactedCount += redactUnstructuredLocator(&event.target)
        redactedCount += redactUnstructuredLocator(&event.threadName)
        if event.privacy == "sensitive", !selection.includeSensitiveFields, event.message != nil {
            redactedCount += replaceWithRedaction(&event.message)
        }
        return (event, redactedCount)
    }

    private static func validatePrivacyLabels(_ event: ObservabilityEventSnapshot) throws {
        guard ObservabilitySafetyPolicy.PrivacyClass(event.privacy) != nil else {
            throw DiagnosticPackageError.redactionFailed
        }
        for attribute in event.attributes {
            _ = try policyValue(ObservabilitySafetyPolicy.assess(attribute: attribute))
        }
        for resource in event.resources {
            _ = try policyValue(ObservabilitySafetyPolicy.validate(resource: resource))
        }
        guard ObservabilityHubPolicy.privacyFloorIsValid(event) else {
            throw DiagnosticPackageError.redactionFailed
        }
    }

    private static func validateSchema(_ event: ObservabilityEventSnapshot) throws {
        guard DiagnosticPackageFormat.supportedEventSchemaVersions.contains(event.schemaVersion) else {
            throw DiagnosticPackageError.unsupportedSchema
        }
        _ = try policyValue(ObservabilitySafetyPolicy.validate(
            buildContext: event.buildContext,
            schemaVersion: event.schemaVersion,
            scope: .diagnosticPackage
        ))
    }

    private static func validateCredentialFree(_ event: ObservabilityEventSnapshot) throws {
        for attribute in event.attributes {
            _ = try policyValue(ObservabilitySafetyPolicy.assess(attribute: attribute))
        }
        var values = event.attributes.map(\.value)
        values.append(contentsOf: [
            event.error?.technicalDetails,
            event.message,
            event.target,
            event.threadName
        ].compactMap { $0 })
        try validateCredentialFree(values)
    }

    private static func validateRedactionState(
        _ event: ObservabilityEventSnapshot,
        selection: DiagnosticPackagePrivacySelection
    ) throws {
        for attribute in event.attributes where attribute.privacy == "sensitive" && attribute.value != redactedValue {
            let assessment = try policyValue(ObservabilitySafetyPolicy.assess(attribute: attribute))
            guard selection.allowsSensitiveAttribute(assessment) else {
                throw DiagnosticPackageError.invalidPackage
            }
        }
        let messageIsRedacted = event.privacy != "sensitive" || selection.includeSensitiveFields ||
            event.message == nil || event.message == redactedValue
        guard messageIsRedacted else {
            throw DiagnosticPackageError.invalidPackage
        }
        guard event.error?.technicalDetails == nil || event.error?.technicalDetails == redactedValue else {
            throw DiagnosticPackageError.invalidPackage
        }
    }

    private static func replaceWithRedaction(_ value: inout String) -> Int {
        guard value != redactedValue else { return 0 }
        value = redactedValue
        return 1
    }

    private static func replaceWithRedaction(_ value: inout String?) -> Int {
        guard value != nil, value != redactedValue else { return 0 }
        value = redactedValue
        return 1
    }

    private static func redactUnstructuredLocator(_ value: inout String?) -> Int {
        guard let current = value, ObservabilitySafetyPolicy.assess(text: current).locator != .none else {
            return 0
        }
        return replaceWithRedaction(&value)
    }

    private static func validateNoUnstructuredLocators(
        _ event: ObservabilityEventSnapshot
    ) throws {
        let values = [
            event.message,
            event.target,
            event.threadName,
            event.error?.technicalDetails
        ].compactMap { $0 }
        guard !values.contains(where: {
            $0 != redactedValue && ObservabilitySafetyPolicy.assess(text: $0).locator != .none
        }) else {
            throw DiagnosticPackageError.redactionFailed
        }
    }

    private static func policyValue<Success>(
        _ result: Result<Success, ObservabilitySafetyPolicy.Violation>
    ) throws -> Success {
        switch result {
        case let .success(value):
            return value
        case let .failure(violation):
            switch violation {
            case .credentialMaterial, .invalidPrivacy, .privacyBelowFloor:
                throw DiagnosticPackageError.redactionFailed
            case .invalidAttributeKey, .invalidResource, .invalidBuildContext:
                throw DiagnosticPackageError.invalidPackage
            }
        }
    }
}

private extension DiagnosticPackagePrivacySelection {
    func allowsSensitiveAttribute(
        _ assessment: ObservabilitySafetyPolicy.AttributeAssessment
    ) -> Bool {
        switch assessment.locator {
        case .fullPath:
            includeFullPaths
        case .fileName:
            includeFileNames
        case .none:
            includeSensitiveFields
        }
    }
}
