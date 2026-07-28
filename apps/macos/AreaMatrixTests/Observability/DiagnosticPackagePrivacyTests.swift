@testable import AreaMatrix
import CryptoKit
import Foundation
import XCTest

final class DiagnosticPackagePrivacyTests: XCTestCase {
    private let exporter = DiagnosticPackageExporter()
    private let reader = DiagnosticPackageReader()

    func testPreviewSeparatesGeneralFileNameAndFullPathAuthorization() throws {
        var event = makeEvent()
        event.privacy = "sensitive"
        event.message = "Private repository"
        event.attributes = [
            attribute("repository.name", "PrivateRepository"),
            attribute("source.name", "report.txt"),
            attribute("source.path", "/Users/example/Private/report.txt")
        ]

        let general = try exportedEvent(
            event,
            selection: DiagnosticPackagePrivacySelection(includeSensitiveFields: true)
        )
        XCTAssertEqual(general.message, "Private repository")
        XCTAssertEqual(attributeValues(general), [
            "repository.name": "PrivateRepository",
            "source.name": DiagnosticPackageRedactor.redactedValue,
            "source.path": DiagnosticPackageRedactor.redactedValue
        ])

        let fileName = try exportedEvent(
            event,
            selection: DiagnosticPackagePrivacySelection(includeFileNames: true)
        )
        XCTAssertEqual(fileName.message, DiagnosticPackageRedactor.redactedValue)
        XCTAssertEqual(attributeValues(fileName), [
            "repository.name": DiagnosticPackageRedactor.redactedValue,
            "source.name": "report.txt",
            "source.path": DiagnosticPackageRedactor.redactedValue
        ])

        let locator = try exportedEvent(
            event,
            selection: DiagnosticPackagePrivacySelection(
                includeFileNames: true,
                includeFullPaths: true
            )
        )
        XCTAssertEqual(locator.message, DiagnosticPackageRedactor.redactedValue)
        XCTAssertEqual(attributeValues(locator), [
            "repository.name": DiagnosticPackageRedactor.redactedValue,
            "source.name": "report.txt",
            "source.path": "/Users/example/Private/report.txt"
        ])

        let all = try exportedEvent(event, selection: .allSensitive())
        XCTAssertEqual(all.message, "Private repository")
        XCTAssertEqual(all.attributes, event.attributes)
    }

    func testUnstructuredLocatorsAreAlwaysRedacted() throws {
        var event = makeEvent()
        event.privacy = "sensitive"
        event.message = "/Users/example/Private/report.txt"
        event.target = "file:///Users/example/Private/report.txt"
        event.threadName = "来源，/用户/机密.txt"

        let decoded = try exportedEvent(event, selection: .allSensitive())

        XCTAssertEqual(decoded.message, DiagnosticPackageRedactor.redactedValue)
        XCTAssertEqual(decoded.target, DiagnosticPackageRedactor.redactedValue)
        XCTAssertEqual(decoded.threadName, DiagnosticPackageRedactor.redactedValue)
    }

    func testPreviewRejectsCredentialAndConfusableKeyBypasses() {
        var credential = makeEvent()
        credential.message = "accessToken opaque"
        assertPackageError(.redactionFailed) {
            try exporter.preview(events: [credential])
        }

        var confusableKey = makeEvent()
        confusableKey.attributes = [attribute("accessＴoken", "opaque")]
        assertPackageError(.invalidPackage) {
            try exporter.preview(events: [confusableKey])
        }
    }

    func testPreviewRejectsPublicLocatorAttributeAndInvalidPathSelection() {
        var event = makeEvent()
        event.attributes = [
            ObservabilityAttributeSnapshot(
                key: "source.path",
                value: "/Users/example/Private/report.txt",
                privacy: "public"
            )
        ]
        assertPackageError(.redactionFailed) {
            try exporter.preview(events: [event])
        }
        assertPackageError(.invalidPackage) {
            try exporter.preview(
                events: [makeEvent()],
                privacySelection: DiagnosticPackagePrivacySelection(includeFullPaths: true)
            )
        }
    }

    func testPreviewRejectsUnderclassifiedAttributeResourceAndErrorFloors() {
        var attributeEvent = makeEvent()
        attributeEvent.attributes = [
            ObservabilityAttributeSnapshot(key: "resource.alias", value: "opaque", privacy: "pseudonymous")
        ]
        assertPackageError(.redactionFailed) {
            try exporter.preview(events: [attributeEvent])
        }

        var resourceEvent = makeEvent()
        resourceEvent.resources = [ObservabilityResourceSnapshot(
            resourceID: "00000000-0000-4000-8000-000000000001",
            alias: "file.0123456789abcdef01234567",
            pathExtension: "txt",
            sizeBucket: "lt_1mb",
            storageMode: "copied"
        )]
        assertPackageError(.redactionFailed) {
            try exporter.preview(events: [resourceEvent])
        }

        var errorEvent = makeEvent()
        errorEvent.privacy = "pseudonymous"
        errorEvent.error = ObservabilityErrorSnapshot(
            code: "repository.read_failed",
            kind: "io",
            technicalDetails: "bounded detail"
        )
        assertPackageError(.redactionFailed) {
            try exporter.preview(events: [errorEvent])
        }
    }

    func testReaderRejectsPrivacyFlagMismatchAndInvalidDependency() throws {
        let fixture = try makeExportedPackage(named: #function)
        defer { removeTestTemporaryItems(fixture.root) }

        let reportURL = fixture.package.appendingPathComponent("privacy-report.json")
        var report = try jsonObject(reportURL)
        report["includesFileNames"] = false
        try replacePayload(
            "privacy-report.json",
            with: JSONSerialization.data(withJSONObject: report, options: [.prettyPrinted, .sortedKeys]),
            in: fixture.package
        )
        assertPackageError(.invalidPackage) { try reader.inspect(fixture.package) }

        let second = try makeExportedPackage(named: #function + "-dependency")
        defer { removeTestTemporaryItems(second.root) }
        var manifest = second.preview.manifest
        manifest.includesFileNames = false
        manifest.includesFullPaths = true
        try replacePayload(
            "manifest.json",
            with: sortedEncoder().encode(manifest),
            in: second.package
        )
        assertPackageError(.invalidPackage) { try reader.inspect(second.package) }
    }

    func testReaderRejectsMissingOrMixedSchemaPrivacyFields() throws {
        let missing = try makeExportedPackage(named: #function + "-missing")
        defer { removeTestTemporaryItems(missing.root) }
        let manifestURL = missing.package.appendingPathComponent("manifest.json")
        var manifest = try jsonObject(manifestURL)
        manifest.removeValue(forKey: "includesFullPaths")
        try replacePayload(
            "manifest.json",
            with: JSONSerialization.data(withJSONObject: manifest, options: [.prettyPrinted, .sortedKeys]),
            in: missing.package
        )
        assertPackageError(.invalidPackage) { try reader.inspect(missing.package) }

        let mixed = try makeExportedPackage(named: #function + "-mixed")
        defer { removeTestTemporaryItems(mixed.root) }
        var mixedManifest = try jsonObject(mixed.package.appendingPathComponent("manifest.json"))
        mixedManifest["schemaVersion"] = 1
        mixedManifest["includesSensitiveMetadata"] = false
        try replacePayload(
            "manifest.json",
            with: JSONSerialization.data(withJSONObject: mixedManifest, options: [.prettyPrinted, .sortedKeys]),
            in: mixed.package
        )
        assertPackageError(.invalidPackage) { try reader.inspect(mixed.package) }
    }

    func testReaderRejectsUnknownManifestReportAndEnvironmentKeys() throws {
        for name in ["manifest.json", "privacy-report.json", "environment.json"] {
            let fixture = try makeExportedPackage(named: #function + "-" + name)
            defer { removeTestTemporaryItems(fixture.root) }
            var object = try jsonObject(fixture.package.appendingPathComponent(name))
            object["unexpected"] = true
            let data = try JSONSerialization.data(withJSONObject: object, options: [.prettyPrinted, .sortedKeys])
            try replacePayload(name, with: data, in: fixture.package)
            assertPackageError(.invalidPackage) { try reader.inspect(fixture.package) }
        }
    }

    func testReaderRejectsRechecksummedMaliciousEvents() throws {
        try assertUnderclassifiedResourceRejected()
        try assertMalformedResourceRejected()
        try assertInvalidBuildContextRejected()
        try assertCredentialMaterialRejected()
        try assertConfusableAttributeKeyRejected()
        try assertUnknownEventKeyRejected()
    }
}

private extension DiagnosticPackagePrivacyTests {
    func assertUnderclassifiedResourceRejected() throws {
        let underclassified = try makeExportedPackage(named: #function + "-privacy")
        defer { removeTestTemporaryItems(underclassified.root) }
        var eventObject = try jsonObject(underclassified.package.appendingPathComponent("events.jsonl"))
        eventObject["resource_refs"] = [[
            "resource_id": "00000000-0000-4000-8000-000000000001",
            "alias": "file.0123456789abcdef01234567",
            "extension": "txt",
            "size_bucket": "lt_1mb",
            "storage_mode": "copied"
        ]]
        try replaceEventPayload(eventObject, in: underclassified.package)
        assertPackageError(.redactionFailed) { try reader.inspect(underclassified.package) }
    }

    func assertMalformedResourceRejected() throws {
        let malformedResource = try makeExportedPackage(named: #function + "-resource")
        defer { removeTestTemporaryItems(malformedResource.root) }
        var malformedEvent = try jsonObject(malformedResource.package.appendingPathComponent("events.jsonl"))
        malformedEvent["privacy_level"] = "pseudonymous"
        malformedEvent["resource_refs"] = [[
            "resource_id": "00000000-0000-4000-8000-000000000001",
            "alias": "file.0123456789ABCDEF01234567",
            "extension": "txt",
            "size_bucket": "lt_1mb",
            "storage_mode": "copied"
        ]]
        try replaceEventPayload(malformedEvent, in: malformedResource.package)
        assertPackageError(.invalidPackage) { try reader.inspect(malformedResource.package) }
    }

    func assertInvalidBuildContextRejected() throws {
        let invalidBuild = try makeExportedPackage(named: #function + "-build")
        defer { removeTestTemporaryItems(invalidBuild.root) }
        var invalidBuildEvent = try jsonObject(invalidBuild.package.appendingPathComponent("events.jsonl"))
        invalidBuildEvent["build_context"] = [
            "producer": "area_matrix_core",
            "version": "0.1.0",
            "build": "test",
            "configuration": "debug",
            "platform": "macos",
            "architecture": "arm64"
        ]
        try replaceEventPayload(invalidBuildEvent, in: invalidBuild.package)
        assertPackageError(.invalidPackage) { try reader.inspect(invalidBuild.package) }
    }

    func assertCredentialMaterialRejected() throws {
        for (index, value) in [
            "privateKey=opaque",
            "Bearer\topaque",
            "auth = opaque",
            "x-api-token : opaque"
        ].enumerated() {
            let credential = try makeExportedPackage(named: #function + "-credential-\(index)")
            defer { removeTestTemporaryItems(credential.root) }
            var credentialEvent = try jsonObject(credential.package.appendingPathComponent("events.jsonl"))
            credentialEvent["thread_name"] = value
            try replaceEventPayload(credentialEvent, in: credential.package)
            assertPackageError(.redactionFailed) { try reader.inspect(credential.package) }
        }
    }

    func assertConfusableAttributeKeyRejected() throws {
        let confusableKey = try makeExportedPackage(named: #function + "-confusable-key")
        defer { removeTestTemporaryItems(confusableKey.root) }
        var confusableEvent = try jsonObject(confusableKey.package.appendingPathComponent("events.jsonl"))
        confusableEvent["privacy_level"] = "sensitive"
        confusableEvent["attributes"] = [[
            "key": "accessＴoken",
            "value": "opaque",
            "privacy": "sensitive"
        ]]
        try replaceEventPayload(confusableEvent, in: confusableKey.package)
        assertPackageError(.invalidPackage) { try reader.inspect(confusableKey.package) }
    }

    func assertUnknownEventKeyRejected() throws {
        let unknownKey = try makeExportedPackage(named: #function + "-unknown")
        defer { removeTestTemporaryItems(unknownKey.root) }
        var unknownEvent = try jsonObject(unknownKey.package.appendingPathComponent("events.jsonl"))
        unknownEvent["lifecycle_step"] = "event"
        try replaceEventPayload(unknownEvent, in: unknownKey.package)
        assertPackageError(.invalidPackage) { try reader.inspect(unknownKey.package) }
    }
}

private extension DiagnosticPackagePrivacyTests {
    struct ExportedFixture {
        let root: URL
        let package: URL
        let preview: DiagnosticPackagePreview
    }

    func attribute(_ key: String, _ value: String) -> ObservabilityAttributeSnapshot {
        ObservabilityAttributeSnapshot(key: key, value: value, privacy: "sensitive")
    }

    func attributeValues(_ event: ObservabilityEventSnapshot) -> [String: String] {
        Dictionary(uniqueKeysWithValues: event.attributes.map { ($0.key, $0.value) })
    }

    func exportedEvent(
        _ event: ObservabilityEventSnapshot,
        selection: DiagnosticPackagePrivacySelection
    ) throws -> ObservabilityEventSnapshot {
        let preview = try exporter.preview(events: [event], privacySelection: selection)
        var data = preview.eventsData
        if data.last == 0x0A { data.removeLast() }
        return try JSONDecoder().decode(ObservabilityEventSnapshot.self, from: data)
    }

    func makeExportedPackage(named name: String) throws -> ExportedFixture {
        let root = try makeTestTemporaryDirectory(named: name)
        let package = root.appendingPathComponent("fixture.amdiagnostic", isDirectory: true)
        let exporter = DiagnosticPackageExporter(
            stagingRootURL: root.appendingPathComponent("staging", isDirectory: true)
        )
        let preview = try exporter.preview(
            events: [makeEvent()],
            privacySelection: .allSensitive()
        )
        do {
            _ = try exporter.export(preview, to: package)
            return ExportedFixture(root: root, package: package, preview: preview)
        } catch {
            removeTestTemporaryItems(root)
            throw error
        }
    }

    func replacePayload(_ name: String, with data: Data, in package: URL) throws {
        try data.write(to: package.appendingPathComponent(name))
        let checksumsURL = package.appendingPathComponent("checksums.json")
        var checksums = try JSONDecoder().decode(
            [String: String].self,
            from: Data(contentsOf: checksumsURL)
        )
        checksums[name] = SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
        try sortedEncoder().encode(checksums).write(to: checksumsURL)
    }

    func replaceEventPayload(_ object: [String: Any], in package: URL) throws {
        var data = try JSONSerialization.data(withJSONObject: object, options: [.sortedKeys])
        data.append(0x0A)
        try replacePayload("events.jsonl", with: data, in: package)
    }

    func jsonObject(_ url: URL) throws -> [String: Any] {
        let data = try Data(contentsOf: url)
        return try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])
    }

    func sortedEncoder() -> JSONEncoder {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
        return encoder
    }

    func makeEvent() -> ObservabilityEventSnapshot {
        var value = event(
            id: UUID().uuidString.lowercased(),
            timestamp: 1_700_000_000_000,
            sessionID: UUID().uuidString.lowercased(),
            message: "Completed"
        )
        value.durationMilliseconds = 12
        value.target = "area_matrix_core"
        value.threadName = "main"
        return value
    }

    func assertPackageError(
        _ expected: DiagnosticPackageError,
        file: StaticString = #filePath,
        line: UInt = #line,
        operation: () throws -> some Any
    ) {
        do {
            _ = try operation()
            XCTFail("Expected \(expected)", file: file, line: line)
        } catch let error as DiagnosticPackageError {
            XCTAssertEqual(error, expected, file: file, line: line)
        } catch {
            XCTFail("Unexpected error: \(error)", file: file, line: line)
        }
    }
}
