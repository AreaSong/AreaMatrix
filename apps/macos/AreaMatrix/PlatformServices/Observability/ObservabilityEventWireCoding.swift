import Foundation

extension ObservabilityBuildContextSnapshot: Codable {
    private enum CodingKeys: String, CodingKey, CaseIterable {
        case producer, version, build, configuration, platform, architecture
    }

    init(from decoder: Decoder) throws {
        try rejectObservabilityUnknownKeys(decoder, allowed: CodingKeys.wireNames)
        let values = try decoder.container(keyedBy: CodingKeys.self)
        producer = try values.decode(String.self, forKey: .producer)
        version = try values.decode(String.self, forKey: .version)
        build = try values.decodeIfPresent(String.self, forKey: .build)
        configuration = try values.decode(String.self, forKey: .configuration)
        platform = try values.decode(String.self, forKey: .platform)
        architecture = try values.decode(String.self, forKey: .architecture)
    }

    func encode(to encoder: Encoder) throws {
        var values = encoder.container(keyedBy: CodingKeys.self)
        try values.encode(producer, forKey: .producer)
        try values.encode(version, forKey: .version)
        try values.encode(build, forKey: .build)
        try values.encode(configuration, forKey: .configuration)
        try values.encode(platform, forKey: .platform)
        try values.encode(architecture, forKey: .architecture)
    }
}

extension ObservabilityAttributeSnapshot: Codable {
    private enum CodingKeys: String, CodingKey, CaseIterable {
        case key, value, privacy
    }

    init(from decoder: Decoder) throws {
        try rejectObservabilityUnknownKeys(decoder, allowed: CodingKeys.wireNames)
        let values = try decoder.container(keyedBy: CodingKeys.self)
        key = try values.decode(String.self, forKey: .key)
        value = try values.decode(String.self, forKey: .value)
        privacy = try values.decode(String.self, forKey: .privacy)
    }

    func encode(to encoder: Encoder) throws {
        var values = encoder.container(keyedBy: CodingKeys.self)
        try values.encode(key, forKey: .key)
        try values.encode(value, forKey: .value)
        try values.encode(privacy, forKey: .privacy)
    }
}

extension ObservabilityResourceSnapshot: Codable {
    private enum CodingKeys: String, CodingKey, CaseIterable {
        case resourceID = "resource_id"
        case alias
        case pathExtension = "extension"
        case sizeBucket = "size_bucket"
        case storageMode = "storage_mode"
    }

    init(from decoder: Decoder) throws {
        try rejectObservabilityUnknownKeys(decoder, allowed: CodingKeys.wireNames)
        let values = try decoder.container(keyedBy: CodingKeys.self)
        resourceID = try values.decode(String.self, forKey: .resourceID)
        alias = try values.decode(String.self, forKey: .alias)
        pathExtension = try values.decodeIfPresent(String.self, forKey: .pathExtension)
        sizeBucket = try values.decodeIfPresent(String.self, forKey: .sizeBucket)
        storageMode = try values.decodeIfPresent(String.self, forKey: .storageMode)
    }

    func encode(to encoder: Encoder) throws {
        var values = encoder.container(keyedBy: CodingKeys.self)
        try values.encode(resourceID, forKey: .resourceID)
        try values.encode(alias, forKey: .alias)
        try values.encode(pathExtension, forKey: .pathExtension)
        try values.encode(sizeBucket, forKey: .sizeBucket)
        try values.encode(storageMode, forKey: .storageMode)
    }
}

extension ObservabilityErrorSnapshot: Codable {
    private enum CodingKeys: String, CodingKey, CaseIterable {
        case code, kind
        case technicalDetails = "technical_details"
    }

    init(from decoder: Decoder) throws {
        try rejectObservabilityUnknownKeys(decoder, allowed: CodingKeys.wireNames)
        let values = try decoder.container(keyedBy: CodingKeys.self)
        code = try values.decode(String.self, forKey: .code)
        kind = try values.decodeIfPresent(String.self, forKey: .kind)
        technicalDetails = try values.decodeIfPresent(String.self, forKey: .technicalDetails)
    }

    func encode(to encoder: Encoder) throws {
        var values = encoder.container(keyedBy: CodingKeys.self)
        try values.encode(code, forKey: .code)
        try values.encode(kind, forKey: .kind)
        try values.encode(technicalDetails, forKey: .technicalDetails)
    }
}

extension ObservabilityEventSnapshot: Codable {
    private enum CurrentKeys: String, CodingKey, CaseIterable {
        case schemaVersion = "schema_version"
        case eventID = "event_id"
        case wallTimestampMilliseconds = "wall_timestamp_ms"
        case monotonicTimestampNanoseconds = "monotonic_timestamp_ns"
        case sequenceNumber = "sequence_number"
        case sessionID = "session_id"
        case incidentID = "incident_id"
        case traceID = "trace_id"
        case spanID = "span_id"
        case parentSpanID = "parent_span_id"
        case operationID = "operation_id"
        case retryOfOperationID = "retry_of_operation_id"
        case actionID = "action_id"
        case componentID = "component_id"
        case layer, phase, severity, outcome
        case durationMilliseconds = "duration_ms"
        case resources = "resource_refs"
        case error, attributes
        case privacy = "privacy_level"
        case message, target
        case threadName = "thread_name"
        case buildContext = "build_context"
    }

    private enum LegacyKeys: String, CodingKey, CaseIterable {
        case schemaVersion, eventID, wallTimestampMilliseconds, monotonicTimestampNanoseconds
        case sequenceNumber, sessionID, incidentID, traceID, spanID, parentSpanID
        case operationID, retryOfOperationID, actionID, componentID, layer, phase
        case severity, outcome, durationMilliseconds, resources, error, attributes
        case privacy, message, target, threadName
    }

    init(from decoder: Decoder) throws {
        let keys = try observabilityWireKeys(decoder)
        let hasCurrentDiscriminator = keys.contains(CurrentKeys.schemaVersion.rawValue)
        let hasLegacyDiscriminator = keys.contains(LegacyKeys.schemaVersion.rawValue)
        guard hasCurrentDiscriminator != hasLegacyDiscriminator else {
            throw observabilityDecodingError(decoder, "Event schema discriminator is missing or mixed.")
        }
        self = if hasCurrentDiscriminator {
            try Self.decodeCurrent(from: decoder)
        } else {
            try Self.decodeLegacy(from: decoder)
        }
    }

    func encode(to encoder: Encoder) throws {
        switch schemaVersion {
        case 1:
            try encodeLegacy(to: encoder)
        case 2:
            try encodeCurrent(to: encoder)
        default:
            throw EncodingError.invalidValue(self, .init(
                codingPath: encoder.codingPath,
                debugDescription: "Unsupported observability event schema."
            ))
        }
    }
}

private extension ObservabilityEventSnapshot {
    static func decodeCurrent(from decoder: Decoder) throws -> Self {
        try rejectObservabilityUnknownKeys(decoder, allowed: CurrentKeys.wireNames)
        let values = try decoder.container(keyedBy: CurrentKeys.self)
        let version = try values.decode(UInt64.self, forKey: .schemaVersion)
        guard version == 2 else {
            throw DecodingError.dataCorruptedError(
                forKey: .schemaVersion,
                in: values,
                debugDescription: "Current observability wire requires schema 2."
            )
        }
        return try Self(
            schemaVersion: version,
            eventID: values.decode(String.self, forKey: .eventID),
            wallTimestampMilliseconds: values.decode(Int64.self, forKey: .wallTimestampMilliseconds),
            monotonicTimestampNanoseconds: values.decode(UInt64.self, forKey: .monotonicTimestampNanoseconds),
            sequenceNumber: values.decode(UInt64.self, forKey: .sequenceNumber),
            sessionID: values.decode(String.self, forKey: .sessionID),
            incidentID: values.decodeIfPresent(String.self, forKey: .incidentID),
            traceID: values.decode(String.self, forKey: .traceID),
            spanID: values.decode(String.self, forKey: .spanID),
            parentSpanID: values.decodeIfPresent(String.self, forKey: .parentSpanID),
            operationID: values.decodeIfPresent(String.self, forKey: .operationID),
            retryOfOperationID: values.decodeIfPresent(String.self, forKey: .retryOfOperationID),
            actionID: values.decode(String.self, forKey: .actionID),
            componentID: values.decode(String.self, forKey: .componentID),
            layer: values.decode(String.self, forKey: .layer),
            phase: values.decode(String.self, forKey: .phase),
            severity: values.decode(AppObservabilitySeverity.self, forKey: .severity),
            outcome: values.decode(String.self, forKey: .outcome),
            durationMilliseconds: values.decodeIfPresent(UInt64.self, forKey: .durationMilliseconds),
            resources: values.decode([ObservabilityResourceSnapshot].self, forKey: .resources),
            error: values.decodeIfPresent(ObservabilityErrorSnapshot.self, forKey: .error),
            attributes: values.decode([ObservabilityAttributeSnapshot].self, forKey: .attributes),
            privacy: values.decode(String.self, forKey: .privacy),
            message: values.decodeIfPresent(String.self, forKey: .message),
            target: values.decodeIfPresent(String.self, forKey: .target),
            threadName: values.decodeIfPresent(String.self, forKey: .threadName),
            buildContext: values.decode(ObservabilityBuildContextSnapshot.self, forKey: .buildContext)
        )
    }

    static func decodeLegacy(from decoder: Decoder) throws -> Self {
        try rejectObservabilityUnknownKeys(decoder, allowed: LegacyKeys.wireNames)
        let values = try decoder.container(keyedBy: LegacyKeys.self)
        let version = try values.decode(UInt64.self, forKey: .schemaVersion)
        guard version == 1 else {
            throw DecodingError.dataCorruptedError(
                forKey: .schemaVersion,
                in: values,
                debugDescription: "Legacy observability wire requires schema 1."
            )
        }
        return try Self(
            schemaVersion: version,
            eventID: values.decode(String.self, forKey: .eventID),
            wallTimestampMilliseconds: values.decode(Int64.self, forKey: .wallTimestampMilliseconds),
            monotonicTimestampNanoseconds: values.decode(UInt64.self, forKey: .monotonicTimestampNanoseconds),
            sequenceNumber: values.decode(UInt64.self, forKey: .sequenceNumber),
            sessionID: values.decode(String.self, forKey: .sessionID),
            incidentID: values.decodeIfPresent(String.self, forKey: .incidentID),
            traceID: values.decode(String.self, forKey: .traceID),
            spanID: values.decode(String.self, forKey: .spanID),
            parentSpanID: values.decodeIfPresent(String.self, forKey: .parentSpanID),
            operationID: values.decodeIfPresent(String.self, forKey: .operationID),
            retryOfOperationID: values.decodeIfPresent(String.self, forKey: .retryOfOperationID),
            actionID: values.decode(String.self, forKey: .actionID),
            componentID: values.decode(String.self, forKey: .componentID),
            layer: values.decode(String.self, forKey: .layer),
            phase: values.decode(String.self, forKey: .phase),
            severity: values.decode(AppObservabilitySeverity.self, forKey: .severity),
            outcome: values.decode(String.self, forKey: .outcome),
            durationMilliseconds: values.decodeIfPresent(UInt64.self, forKey: .durationMilliseconds),
            resources: values.decode([LegacyResource].self, forKey: .resources).map(\.snapshot),
            error: values.decodeIfPresent(LegacyError.self, forKey: .error)?.snapshot,
            attributes: values.decode([ObservabilityAttributeSnapshot].self, forKey: .attributes),
            privacy: values.decode(String.self, forKey: .privacy),
            message: values.decodeIfPresent(String.self, forKey: .message),
            target: values.decodeIfPresent(String.self, forKey: .target),
            threadName: values.decodeIfPresent(String.self, forKey: .threadName),
            buildContext: nil
        )
    }

    func encodeCurrent(to encoder: Encoder) throws {
        guard let buildContext else {
            throw EncodingError.invalidValue(self, .init(
                codingPath: encoder.codingPath,
                debugDescription: "Schema 2 observability event requires build context."
            ))
        }
        var values = encoder.container(keyedBy: CurrentKeys.self)
        try values.encode(schemaVersion, forKey: .schemaVersion)
        try values.encode(eventID, forKey: .eventID)
        try values.encode(wallTimestampMilliseconds, forKey: .wallTimestampMilliseconds)
        try values.encode(monotonicTimestampNanoseconds, forKey: .monotonicTimestampNanoseconds)
        try values.encode(sequenceNumber, forKey: .sequenceNumber)
        try values.encode(sessionID, forKey: .sessionID)
        try values.encode(incidentID, forKey: .incidentID)
        try values.encode(traceID, forKey: .traceID)
        try values.encode(spanID, forKey: .spanID)
        try values.encode(parentSpanID, forKey: .parentSpanID)
        try values.encode(operationID, forKey: .operationID)
        try values.encode(retryOfOperationID, forKey: .retryOfOperationID)
        try values.encode(actionID, forKey: .actionID)
        try values.encode(componentID, forKey: .componentID)
        try values.encode(layer, forKey: .layer)
        try values.encode(phase, forKey: .phase)
        try values.encode(severity, forKey: .severity)
        try values.encode(outcome, forKey: .outcome)
        try values.encode(durationMilliseconds, forKey: .durationMilliseconds)
        try values.encode(resources, forKey: .resources)
        try values.encode(error, forKey: .error)
        try values.encode(attributes, forKey: .attributes)
        try values.encode(privacy, forKey: .privacy)
        try values.encode(message, forKey: .message)
        try values.encode(target, forKey: .target)
        try values.encode(threadName, forKey: .threadName)
        try values.encode(buildContext, forKey: .buildContext)
    }

    func encodeLegacy(to encoder: Encoder) throws {
        guard buildContext == nil else {
            throw EncodingError.invalidValue(self, .init(
                codingPath: encoder.codingPath,
                debugDescription: "Schema 1 observability event cannot contain build context."
            ))
        }
        var values = encoder.container(keyedBy: LegacyKeys.self)
        try values.encode(schemaVersion, forKey: .schemaVersion)
        try values.encode(eventID, forKey: .eventID)
        try values.encode(wallTimestampMilliseconds, forKey: .wallTimestampMilliseconds)
        try values.encode(monotonicTimestampNanoseconds, forKey: .monotonicTimestampNanoseconds)
        try values.encode(sequenceNumber, forKey: .sequenceNumber)
        try values.encode(sessionID, forKey: .sessionID)
        try values.encode(incidentID, forKey: .incidentID)
        try values.encode(traceID, forKey: .traceID)
        try values.encode(spanID, forKey: .spanID)
        try values.encode(parentSpanID, forKey: .parentSpanID)
        try values.encode(operationID, forKey: .operationID)
        try values.encode(retryOfOperationID, forKey: .retryOfOperationID)
        try values.encode(actionID, forKey: .actionID)
        try values.encode(componentID, forKey: .componentID)
        try values.encode(layer, forKey: .layer)
        try values.encode(phase, forKey: .phase)
        try values.encode(severity, forKey: .severity)
        try values.encode(outcome, forKey: .outcome)
        try values.encode(durationMilliseconds, forKey: .durationMilliseconds)
        try values.encode(resources.map(LegacyResource.init), forKey: .resources)
        try values.encode(error.map(LegacyError.init), forKey: .error)
        try values.encode(attributes, forKey: .attributes)
        try values.encode(privacy, forKey: .privacy)
        try values.encode(message, forKey: .message)
        try values.encode(target, forKey: .target)
        try values.encode(threadName, forKey: .threadName)
    }
}

private struct LegacyResource: Codable {
    private enum CodingKeys: String, CodingKey, CaseIterable {
        case resourceID, alias, pathExtension, sizeBucket, storageMode
    }

    let snapshot: ObservabilityResourceSnapshot

    init(_ snapshot: ObservabilityResourceSnapshot) {
        self.snapshot = snapshot
    }

    init(from decoder: Decoder) throws {
        try rejectObservabilityUnknownKeys(decoder, allowed: CodingKeys.wireNames)
        let values = try decoder.container(keyedBy: CodingKeys.self)
        snapshot = try ObservabilityResourceSnapshot(
            resourceID: values.decode(String.self, forKey: .resourceID),
            alias: values.decode(String.self, forKey: .alias),
            pathExtension: values.decodeIfPresent(String.self, forKey: .pathExtension),
            sizeBucket: values.decodeIfPresent(String.self, forKey: .sizeBucket),
            storageMode: values.decodeIfPresent(String.self, forKey: .storageMode)
        )
    }

    func encode(to encoder: Encoder) throws {
        var values = encoder.container(keyedBy: CodingKeys.self)
        try values.encode(snapshot.resourceID, forKey: .resourceID)
        try values.encode(snapshot.alias, forKey: .alias)
        try values.encode(snapshot.pathExtension, forKey: .pathExtension)
        try values.encode(snapshot.sizeBucket, forKey: .sizeBucket)
        try values.encode(snapshot.storageMode, forKey: .storageMode)
    }
}

private struct LegacyError: Codable {
    private enum CodingKeys: String, CodingKey, CaseIterable {
        case code, kind, technicalDetails
    }

    let snapshot: ObservabilityErrorSnapshot

    init(_ snapshot: ObservabilityErrorSnapshot) {
        self.snapshot = snapshot
    }

    init(from decoder: Decoder) throws {
        try rejectObservabilityUnknownKeys(decoder, allowed: CodingKeys.wireNames)
        let values = try decoder.container(keyedBy: CodingKeys.self)
        snapshot = try ObservabilityErrorSnapshot(
            code: values.decode(String.self, forKey: .code),
            kind: values.decodeIfPresent(String.self, forKey: .kind),
            technicalDetails: values.decodeIfPresent(String.self, forKey: .technicalDetails)
        )
    }

    func encode(to encoder: Encoder) throws {
        var values = encoder.container(keyedBy: CodingKeys.self)
        try values.encode(snapshot.code, forKey: .code)
        try values.encode(snapshot.kind, forKey: .kind)
        try values.encode(snapshot.technicalDetails, forKey: .technicalDetails)
    }
}

private struct ObservabilityWireCodingKey: CodingKey {
    let stringValue: String
    let intValue: Int? = nil

    init?(stringValue: String) {
        self.stringValue = stringValue
    }

    init?(intValue _: Int) {
        nil
    }
}

private func observabilityWireKeys(_ decoder: Decoder) throws -> Set<String> {
    let values = try decoder.container(keyedBy: ObservabilityWireCodingKey.self)
    return Set(values.allKeys.map(\.stringValue))
}

private func rejectObservabilityUnknownKeys(_ decoder: Decoder, allowed: Set<String>) throws {
    let unknown = try observabilityWireKeys(decoder).subtracting(allowed)
    guard unknown.isEmpty else {
        throw observabilityDecodingError(decoder, "Unknown observability keys: \(unknown.sorted())")
    }
}

private func observabilityDecodingError(_ decoder: Decoder, _ description: String) -> DecodingError {
    .dataCorrupted(.init(codingPath: decoder.codingPath, debugDescription: description))
}

private extension CaseIterable where Self: RawRepresentable, RawValue == String {
    static var wireNames: Set<String> {
        Set(allCases.map(\.rawValue))
    }
}
