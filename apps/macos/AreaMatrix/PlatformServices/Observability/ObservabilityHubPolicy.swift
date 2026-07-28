import Foundation

enum ObservabilityHubPolicy {
    private static let configurationKey = "observability.configuration"

    static func loadConfiguration(defaults: UserDefaults) -> AppObservabilityConfiguration {
        guard let data = defaults.data(forKey: configurationKey),
              let value = try? JSONDecoder().decode(AppObservabilityConfiguration.self, from: data)
        else { return .standard }
        return normalized(value)
    }

    static func saveConfiguration(
        _ value: AppObservabilityConfiguration,
        defaults: UserDefaults
    ) {
        guard let data = try? JSONEncoder().encode(value) else { return }
        defaults.set(data, forKey: configurationKey)
    }

    static func normalized(
        _ value: AppObservabilityConfiguration
    ) -> AppObservabilityConfiguration {
        var value = value
        value.diskBudgetBytes = min(max(value.diskBudgetBytes, 100 * 1024 * 1024), 2 * 1024 * 1024 * 1024)
        if value.mode == .standard { value.diskBudgetBytes = 50 * 1024 * 1024 }
        if value.mode == .diagnostic { value.diskBudgetBytes = 250 * 1024 * 1024 }
        value.retentionHours = min(max(value.retentionHours, 1), 30 * 24)
        return value
    }

    static func memoryCapacity(for mode: AppObservabilityMode) -> Int {
        switch mode {
        case .disabled: 500
        case .standard: 5000
        case .diagnostic: 20000
        case .developer: 50000
        }
    }

    static func isEnabled(
        _ severity: AppObservabilitySeverity,
        minimumSeverity: AppObservabilitySeverity
    ) -> Bool {
        severity.rank >= minimumSeverity.rank
    }

    static func safeIdentifier(_ candidate: String) -> String {
        let allowed = CharacterSet(charactersIn: "abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789-")
        guard !candidate.isEmpty, candidate.utf8.count <= 128,
              candidate.unicodeScalars.allSatisfy(allowed.contains)
        else { return UUID().uuidString.lowercased() }
        return candidate
    }

    static func sanitize(
        _ rawEvent: ObservabilityEventSnapshot,
        includeSensitive: Bool,
        catalog: ObservabilityCatalog,
        buildScope: ObservabilitySafetyPolicy.BuildScope
    ) -> ObservabilityEventSnapshot? {
        guard validateEnvelope(rawEvent, catalog: catalog, buildScope: buildScope) else {
            return nil
        }
        var event = rawEvent
        var attributes: [ObservabilityAttributeSnapshot] = []
        for var attribute in event.attributes {
            guard case .success = ObservabilitySafetyPolicy.assess(attribute: attribute) else {
                return nil
            }
            if attribute.privacy == "sensitive", !includeSensitive {
                attribute.value = "[REDACTED]"
            }
            attributes.append(attribute)
        }
        event.attributes = attributes
        guard sanitizeFreeText(&event, includeSensitive: includeSensitive) else { return nil }
        if event.error?.technicalDetails != nil { event.error?.technicalDetails = "[REDACTED]" }
        return event
    }

    static func sanitizedNote(_ note: String?) -> String? {
        guard let note else { return nil }
        let bounded = String(note.prefix(8192)).trimmingCharacters(in: .whitespacesAndNewlines)
        guard !bounded.isEmpty else { return nil }
        return containsProhibitedPattern(bounded) ? "[REDACTED]" : bounded
    }

    static func privacyFloorIsValid(_ event: ObservabilityEventSnapshot) -> Bool {
        guard let eventPrivacy = ObservabilitySafetyPolicy.PrivacyClass(event.privacy),
              eventPrivacy != .prohibited
        else { return false }
        let assessments = event.attributes.compactMap { attribute -> ObservabilitySafetyPolicy.AttributeAssessment? in
            guard case let .success(assessment) = ObservabilitySafetyPolicy.assess(attribute: attribute) else {
                return nil
            }
            return assessment
        }
        guard assessments.count == event.attributes.count else { return false }
        let attributeFloor = assessments.map(\.privacy.rawValue).max() ?? 0
        let resourceFloor = event.resources.isEmpty ? 0 : 1
        let errorFloor = event.error?.technicalDetails == nil ? 0 : 2
        let messageFloor = event.message.map {
            ObservabilitySafetyPolicy.assess(text: $0).locator == .none ? 0 : 2
        } ?? 0
        return eventPrivacy.rawValue >= max(attributeFloor, resourceFloor, errorFloor, messageFloor)
    }

    static func saturatingSum(_ values: [UInt64]) -> UInt64 {
        values.reduce(0) { partial, value in
            let (sum, overflow) = partial.addingReportingOverflow(value)
            return overflow ? .max : sum
        }
    }

    static func milliseconds(_ date: Date) -> Int64 {
        ObservabilityTime.milliseconds(date)
    }

    static func increment(_ value: inout UInt64) {
        if value < .max { value += 1 }
    }

    static func tagged(
        _ event: ObservabilityEventSnapshot,
        incidentID: String
    ) -> ObservabilityEventSnapshot {
        var event = event
        event.incidentID = incidentID
        return event
    }

    static func makeHealth(
        state: ObservabilityHubHealthState,
        core: ObservabilityHealth?
    ) -> AppObservabilityHealth {
        let droppedTrace = core?.droppedTrace ?? 0
        let droppedDebug = core?.droppedDebug ?? 0
        let droppedInfo = core?.droppedInfo ?? 0
        let droppedWarn = core?.droppedWarn ?? 0
        let droppedError = core?.droppedError ?? 0
        let coreDrops = saturatingSum([
            droppedTrace, droppedDebug, droppedInfo, droppedWarn, droppedError
        ])
        let coreRejected = core?.redactionRejected ?? 0
        let totalRejected = saturatingSum([state.rejectedEvents, coreRejected])
        let issues = healthIssues(state: state, core: core)
        let elapsed = nonnegativeDifference(
            state.observedAtMilliseconds,
            state.modeActivatedAtMilliseconds
        )
        let estimatedGrowth = estimatedGrowthBytesPerHour(
            currentBytes: state.fileUsageBytes,
            baselineBytes: state.modeUsageBaselineBytes,
            elapsedMilliseconds: elapsed,
            persistsToDisk: state.configuration.mode.persistsToDisk
        )
        return AppObservabilityHealth(
            initialized: core?.initialized ?? false,
            mode: state.configuration.mode,
            memoryEventCount: state.memoryEventCount,
            memoryCapacity: state.memoryCapacity,
            oldestEventTimestampMilliseconds: state.oldestEventTimestampMilliseconds,
            fileUsageBytes: state.fileUsageBytes,
            diskBudgetBytes: state.configuration.diskBudgetBytes,
            modeElapsedMilliseconds: elapsed,
            estimatedGrowthBytesPerHour: estimatedGrowth,
            droppedEvents: saturatingSum([coreDrops, state.ingressDroppedEvents]),
            droppedTraceEvents: droppedTrace,
            droppedDebugEvents: droppedDebug,
            droppedInfoEvents: droppedInfo,
            droppedWarnEvents: droppedWarn,
            droppedErrorEvents: droppedError,
            ingressDroppedEvents: state.ingressDroppedEvents,
            rejectedEvents: totalRejected,
            coreRedactionRejectedEvents: coreRejected,
            coreQueueDepth: core?.queueDepth ?? 0,
            coreQueueCapacity: core?.queueCapacity ?? 0,
            writerAvailable: state.writerAvailable,
            coreCallbackConnected: core?.callbackConnected ?? false,
            lastRotationAtMilliseconds: state.lastRotationAtMilliseconds,
            incidentCount: state.incidentCount,
            activeIncidentID: state.activeIncidentID,
            degradedReason: issues.first?.code,
            issues: issues
        )
    }

    static func estimatedGrowthBytesPerHour(
        currentBytes: Int64,
        baselineBytes: Int64,
        elapsedMilliseconds: Int64,
        persistsToDisk: Bool
    ) -> Int64? {
        guard persistsToDisk, elapsedMilliseconds > 0 else { return nil }
        let delta = nonnegativeDifference(currentBytes, baselineBytes)
        let (scaled, overflow) = delta.multipliedReportingOverflow(by: 3_600_000)
        return overflow ? .max : scaled / elapsedMilliseconds
    }

    static func nonnegativeDifference(_ end: Int64, _ start: Int64) -> Int64 {
        let (difference, overflow) = end.subtractingReportingOverflow(start)
        if overflow { return end >= start ? .max : 0 }
        return max(0, difference)
    }
}

extension AppObservabilityConfiguration {
    var observabilityMemoryCapacity: Int {
        ObservabilityHubPolicy.memoryCapacity(for: mode)
    }
}

struct ObservabilityHubHealthState {
    let configuration: AppObservabilityConfiguration
    let memoryEventCount: Int
    let memoryCapacity: Int
    let oldestEventTimestampMilliseconds: Int64?
    let fileUsageBytes: Int64
    let modeActivatedAtMilliseconds: Int64
    let modeUsageBaselineBytes: Int64
    let observedAtMilliseconds: Int64
    let writerAvailable: Bool
    let lastRotationAtMilliseconds: Int64?
    let incidentCount: Int
    let activeIncidentID: String?
    let catalogFailureReason: String?
    let writerFailureReason: String?
    let resourceIdentityFailureReason: String?
    let ingressFailureReason: String?
    let signpostRejectedIntervalCount: UInt64
    let ingressDroppedEvents: UInt64
    let rejectedEvents: UInt64
}

private extension ObservabilityHubPolicy {
    static func validateEnvelope(
        _ event: ObservabilityEventSnapshot,
        catalog: ObservabilityCatalog,
        buildScope: ObservabilitySafetyPolicy.BuildScope
    ) -> Bool {
        let isLegacy = event.schemaVersion == 1
        guard event.schemaVersion == 2 || isLegacy,
              case .success = ObservabilitySafetyPolicy.validate(
                  buildContext: event.buildContext,
                  schemaVersion: event.schemaVersion,
                  scope: buildScope
              ),
              validID(event.eventID),
              validID(event.sessionID),
              validID(event.traceID),
              validID(event.spanID),
              validID(event.actionID),
              validID(event.componentID),
              validID(event.phase),
              ["swift_ui", "platform", "bridge", "core", "database", "filesystem", "network"]
              .contains(event.layer),
              ["none", "started", "succeeded", "failed", "cancelled", "skipped", "degraded"]
              .contains(event.outcome),
              privacyFloorIsValid(event),
              event.privacy != "prohibited",
              event.attributes.count <= DiagnosticPackageFormat.maximumAttributeCount,
              event.resources.count <= DiagnosticPackageFormat.maximumResourceCount
        else { return false }
        if !isLegacy, !catalog.containsAction(event.actionID) || !catalog.containsComponent(event.componentID) {
            return false
        }
        return event.attributes.allSatisfy(validAttribute) && event.resources.allSatisfy {
            if case .success = ObservabilitySafetyPolicy.validate(resource: $0) { return true }
            return false
        }
    }

    static func validAttribute(_ attribute: ObservabilityAttributeSnapshot) -> Bool {
        guard validID(attribute.key), attribute.value.utf8.count <= 4096 else { return false }
        if case .success = ObservabilitySafetyPolicy.assess(attribute: attribute) { return true }
        return false
    }

    static func validID(_ value: String) -> Bool {
        ObservabilitySafetyPolicy.validIdentifier(value)
    }

    static func containsProhibitedPattern(_ value: String) -> Bool {
        ObservabilitySafetyPolicy.assess(text: value).containsCredential
    }

    static func sanitizeFreeText(
        _ event: inout ObservabilityEventSnapshot,
        includeSensitive: Bool
    ) -> Bool {
        let detail = event.error?.technicalDetails.map(ObservabilitySafetyPolicy.assess)
        let message = event.message.map(ObservabilitySafetyPolicy.assess)
        let target = event.target.map(ObservabilitySafetyPolicy.assess)
        let threadName = event.threadName.map(ObservabilitySafetyPolicy.assess)
        guard [detail, message, target, threadName].compactMap({ $0 }).allSatisfy({ !$0.containsCredential }) else {
            return false
        }
        if let message, message.locator != .none {
            event.message = "[REDACTED]"
        } else if event.privacy == "sensitive", !includeSensitive, event.message != nil {
            event.message = "[REDACTED]"
        }
        if let target, target.locator != .none || event.target.map(validID) == false {
            event.target = nil
        }
        if let threadName, threadName.locator != .none || event.threadName.map(validID) == false {
            event.threadName = nil
        }
        return true
    }

    static func healthIssues(
        state: ObservabilityHubHealthState,
        core: ObservabilityHealth?
    ) -> [ObservabilityHealthIssue] {
        var issues: [ObservabilityHealthIssue] = []
        appendIssue(state.catalogFailureReason, source: .catalog, to: &issues)
        appendIssue(state.writerFailureReason, source: .writer, to: &issues)
        appendIssue(state.resourceIdentityFailureReason, source: .resourceIdentity, to: &issues)
        appendIssue(state.ingressFailureReason, source: .ingress, to: &issues)
        appendIssue(core?.degradedReason, source: .core, to: &issues)
        if state.signpostRejectedIntervalCount > 0 {
            appendIssue("signpost-pairing-rejected", source: .signpost, to: &issues)
        }
        if core?.initialized != true {
            appendIssue("core-not-initialized", source: .core, to: &issues)
        }
        if let core, AppObservabilityMode(coreMode: core.mode) != state.configuration.mode {
            appendIssue("mode-mismatch", source: .core, to: &issues)
        }
        return issues
    }

    static func appendIssue(
        _ code: String?,
        source: ObservabilityHealthIssue.Source,
        to issues: inout [ObservabilityHealthIssue]
    ) {
        guard let code, !code.isEmpty else { return }
        let issue = ObservabilityHealthIssue(source: source, code: code)
        if !issues.contains(issue) { issues.append(issue) }
    }
}
