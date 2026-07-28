@testable import AreaMatrix
import Foundation
import XCTest

final class ObservabilityEventWireCodingTests: XCTestCase {
    func testSchemaTwoUsesExactWireKeysAndRoundTrips() throws {
        let source = currentEvent()
        let data = try encoder.encode(source)
        let object = try jsonObject(data)

        XCTAssertEqual(Set(object.keys), Self.currentEventKeys)
        XCTAssertEqual(object["privacy_level"] as? String, "sensitive")
        XCTAssertNil(object["privacy"])
        XCTAssertNil(object["lifecycle_step"])

        let attributes = try XCTUnwrap(object["attributes"] as? [[String: Any]])
        let attribute = try XCTUnwrap(attributes.first)
        XCTAssertEqual(Set(attribute.keys), ["key", "value", "privacy"])
        XCTAssertEqual(attribute["privacy"] as? String, "sensitive")
        XCTAssertNil(attribute["privacy_level"])

        let context = try XCTUnwrap(object["build_context"] as? [String: Any])
        XCTAssertEqual(Set(context.keys), [
            "producer", "version", "build", "configuration", "platform", "architecture"
        ])
        XCTAssertEqual(try decoder.decode(ObservabilityEventSnapshot.self, from: data), source)
    }

    func testLiteralSchemaOneDecodesAndReencodesOnlyLegacyKeys() throws {
        let source = Data(Self.legacyEventJSON.utf8)
        let event = try decoder.decode(ObservabilityEventSnapshot.self, from: source)

        XCTAssertEqual(event.schemaVersion, 1)
        XCTAssertEqual(event.eventID, "legacy-event")
        XCTAssertNil(event.buildContext)

        let object = try jsonObject(encoder.encode(event))
        XCTAssertEqual(object["schemaVersion"] as? Int, 1)
        XCTAssertEqual(object["privacy"] as? String, "public")
        XCTAssertNil(object["schema_version"])
        XCTAssertNil(object["privacy_level"])
        XCTAssertNil(object["build_context"])
    }

    func testMixedUnknownAndLifecycleAliasKeysAreRejected() throws {
        let source = try jsonObject(encoder.encode(currentEvent()))

        var mixed = source
        mixed["schemaVersion"] = 2
        try assertRejected(mixed)

        var unknown = source
        unknown["unexpected"] = true
        try assertRejected(unknown)

        var lifecycleAlias = source
        lifecycleAlias.removeValue(forKey: "phase")
        lifecycleAlias["lifecycle_step"] = "event"
        try assertRejected(lifecycleAlias)
    }

    func testBuildContextAndAttributeKeysFailClosed() throws {
        let source = try jsonObject(encoder.encode(currentEvent()))

        var missingContext = source
        missingContext.removeValue(forKey: "build_context")
        try assertRejected(missingContext)

        var unknownContext = source
        var context = try XCTUnwrap(unknownContext["build_context"] as? [String: Any])
        context["unexpected"] = "value"
        unknownContext["build_context"] = context
        try assertRejected(unknownContext)

        var renamedAttribute = source
        var attributes = try XCTUnwrap(renamedAttribute["attributes"] as? [[String: Any]])
        var attribute = try XCTUnwrap(attributes.first)
        attribute["privacy_level"] = attribute.removeValue(forKey: "privacy")
        attributes[0] = attribute
        renamedAttribute["attributes"] = attributes
        try assertRejected(renamedAttribute)

        var legacyWithBuildContext = try jsonObject(Data(Self.legacyEventJSON.utf8))
        legacyWithBuildContext["build_context"] = source["build_context"]
        try assertRejected(legacyWithBuildContext)
    }

    func testUnsupportedSchemaVersionsAreRejected() throws {
        var current = try jsonObject(encoder.encode(currentEvent()))
        current["schema_version"] = 1
        try assertRejected(current)

        var legacy = try jsonObject(Data(Self.legacyEventJSON.utf8))
        legacy["schemaVersion"] = 2
        try assertRejected(legacy)

        var unsupported = currentEvent()
        unsupported.schemaVersion = 3
        XCTAssertThrowsError(try encoder.encode(unsupported))
    }
}

private extension ObservabilityEventWireCodingTests {
    static let currentEventKeys: Set<String> = [
        "schema_version", "event_id", "wall_timestamp_ms", "monotonic_timestamp_ns",
        "sequence_number", "session_id", "incident_id", "trace_id", "span_id",
        "parent_span_id", "operation_id", "retry_of_operation_id", "action_id",
        "component_id", "layer", "phase", "severity", "outcome", "duration_ms",
        "resource_refs", "error", "attributes", "privacy_level", "message", "target",
        "thread_name", "build_context"
    ]

    static let legacyEventJSON = """
    {
      "schemaVersion": 1,
      "eventID": "legacy-event",
      "wallTimestampMilliseconds": 10,
      "monotonicTimestampNanoseconds": 20,
      "sequenceNumber": 30,
      "sessionID": "legacy-session",
      "traceID": "legacy-trace",
      "spanID": "legacy-span",
      "actionID": "diagnostics.export.confirmed",
      "componentID": "macos.observability.runtime",
      "layer": "platform",
      "phase": "event",
      "severity": "info",
      "outcome": "succeeded",
      "resources": [],
      "attributes": [],
      "privacy": "public"
    }
    """

    var encoder: JSONEncoder {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys, .withoutEscapingSlashes]
        return encoder
    }

    var decoder: JSONDecoder {
        JSONDecoder()
    }

    func currentEvent() -> ObservabilityEventSnapshot {
        var value = event(
            id: "wire-event",
            timestamp: 1_700_000_000_000,
            sessionID: "wire-session",
            message: "bounded detail"
        )
        value.incidentID = "wire-incident"
        value.parentSpanID = "parent-span"
        value.operationID = "operation-id"
        value.retryOfOperationID = "previous-operation-id"
        value.durationMilliseconds = 42
        value.resources = [ObservabilityResourceSnapshot(
            resourceID: "00000000-0000-4000-8000-000000000001",
            alias: "file.0123456789abcdef01234567",
            pathExtension: "txt",
            sizeBucket: "lt_1mb",
            storageMode: "copied"
        )]
        value.error = ObservabilityErrorSnapshot(
            code: "repository.read_failed",
            kind: "io",
            technicalDetails: DiagnosticPackageRedactor.redactedValue
        )
        value.attributes = [ObservabilityAttributeSnapshot(
            key: "source.path",
            value: DiagnosticPackageRedactor.redactedValue,
            privacy: "sensitive"
        )]
        value.privacy = "sensitive"
        value.target = "area_matrix_core"
        value.threadName = "worker"
        return value
    }

    func jsonObject(_ data: Data) throws -> [String: Any] {
        try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])
    }

    func assertRejected(
        _ object: [String: Any],
        file: StaticString = #filePath,
        line: UInt = #line
    ) throws {
        let data = try JSONSerialization.data(withJSONObject: object, options: [.sortedKeys])
        XCTAssertThrowsError(
            try decoder.decode(ObservabilityEventSnapshot.self, from: data),
            file: file,
            line: line
        )
    }
}
