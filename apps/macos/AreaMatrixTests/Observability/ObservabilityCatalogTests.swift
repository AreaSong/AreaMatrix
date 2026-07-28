@testable import AreaMatrix
import Foundation
import XCTest

final class ObservabilityCatalogTests: XCTestCase {
    func testSharedGoldenDocumentsHaveStrictParityClassification() throws {
        let expectations: [(String, ObservabilityCatalogError?)] = [
            ("valid-minimal-v1.json", nil),
            ("invalid-malformed.json", .invalidDocument),
            ("invalid-unknown-field.json", .invalidDocument),
            ("invalid-duplicate-id.json", .invalidDocument),
            ("invalid-non-ascii-id.json", .invalidDocument),
            ("invalid-dangling-reference.json", .invalidDocument),
            ("invalid-selector-shape.json", .invalidDocument),
            ("invalid-empty-flow.json", .invalidDocument),
            ("invalid-all-optional-flow.json", .invalidDocument),
            ("invalid-control-authority.json", .invalidDocument),
            ("unsupported-schema.json", .unsupportedSchema)
        ]

        for (name, expectedError) in expectations {
            let data = try Data(contentsOf: fixtureDirectoryURL.appendingPathComponent(name))
            XCTAssertEqual(decodeError(data), expectedError, name)
        }
    }

    func testProductionCatalogExposesCompleteImportFlow() throws {
        let catalog = try sourceCatalog()
        let flow = try XCTUnwrap(catalog.expectedFlows.first)

        XCTAssertEqual(catalog.schemaVersion, 1)
        XCTAssertEqual(catalog.actions.count, 30)
        XCTAssertEqual(catalog.components.count, 14)
        XCTAssertEqual(catalog.expectedFlows.map(\.id), ["repository.import"])
        XCTAssertEqual(flow.entryActionIDs, [
            "repository.import.confirmed",
            "repository.import.retry.confirmed",
            "repository.import.single.confirmed"
        ])
        XCTAssertEqual(flow.steps.first?.id, "ui.started")
        XCTAssertEqual(flow.steps.first?.matchAny.count, 5)
        XCTAssertEqual(flow.steps.last?.id, "ui.completed")
        XCTAssertEqual(flow.steps.last?.matchAny.count, 6)
        XCTAssertTrue(flow.steps.contains { $0.id == "core.started" && $0.required })
        XCTAssertTrue(flow.steps.contains { $0.id == "core.completed" && $0.required })
        XCTAssertTrue(flow.steps.contains { $0.id == "replacement_trash" && $0.required })
        XCTAssertTrue(flow.steps.contains { $0.id == "duplicate_detected" && !$0.required })
        XCTAssertTrue(flow.steps.contains { $0.id == "trash_fallback" && !$0.required })
        XCTAssertNil(flow.steps.first { $0.id == "validation" }?.matchAny.first?.phase)
    }

    func testBundledCatalogMatchesTheCoreSourceAndAuthoritiesExist() throws {
        let source = try sourceCatalog()
        let bundled: ObservabilityCatalog
        switch ObservabilityCatalog.loadBundled() {
        case let .success(catalog):
            bundled = catalog
        case let .failure(error):
            throw error
        }

        XCTAssertEqual(bundled, source)
        for component in source.components {
            let authorityURL = repositoryRootURL.appendingPathComponent(component.authority)
            XCTAssertTrue(FileManager.default.fileExists(atPath: authorityURL.path), component.authority)
        }
    }

    private func sourceCatalog() throws -> ObservabilityCatalog {
        let url = repositoryRootURL.appendingPathComponent("core/resources/observability_catalog.json")
        return try ObservabilityCatalog.decode(Data(contentsOf: url))
    }

    private func decodeError(_ data: Data) -> ObservabilityCatalogError? {
        do {
            _ = try ObservabilityCatalog.decode(data)
            return nil
        } catch let error as ObservabilityCatalogError {
            return error
        } catch {
            return .invalidDocument
        }
    }

    private var fixtureDirectoryURL: URL {
        repositoryRootURL.appendingPathComponent("core/tests/fixtures/observability_catalog", isDirectory: true)
    }

    private var repositoryRootURL: URL {
        var url = URL(fileURLWithPath: #filePath)
        for _ in 0 ..< 5 {
            url.deleteLastPathComponent()
        }
        return url
    }
}
