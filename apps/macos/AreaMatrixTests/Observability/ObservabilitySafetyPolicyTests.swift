@testable import AreaMatrix
import XCTest

final class ObservabilitySafetyPolicyTests: XCTestCase {
    func testCamelCaseCredentialAndLocatorKeysMatchCorePolicy() {
        assertAttributeFailure(key: "accessToken", value: "opaque", privacy: "public", .credentialMaterial)
        assertAttributeFailure(key: "clientSecret", value: "opaque", privacy: "sensitive", .credentialMaterial)
        assertAttributeFailure(key: "repositoryURL", value: "opaque", privacy: "public", .privacyBelowFloor)
        assertAttributeFailure(key: "sourceName", value: "report.txt", privacy: "public", .privacyBelowFloor)

        let accepted = ObservabilitySafetyPolicy.assess(attribute: .init(
            key: "diagnostic.value",
            value: "completed",
            privacy: "public"
        ))
        guard case let .success(assessment) = accepted else {
            return XCTFail("Expected a public non-locator attribute.")
        }
        XCTAssertEqual(assessment.locator, .none)
        XCTAssertEqual(assessment.minimumPrivacy, .public)
    }

    func testRepositoryNameIsGeneralSensitiveMetadataRatherThanAFileName() {
        for key in ["repository.name", "repositoryName"] {
            let result = ObservabilitySafetyPolicy.assess(attribute: .init(
                key: key,
                value: "PrivateRepository",
                privacy: "sensitive"
            ))
            guard case let .success(assessment) = result else {
                return XCTFail("Expected sensitive repository metadata for \(key).")
            }
            XCTAssertEqual(assessment.locator, .none)
            XCTAssertEqual(assessment.minimumPrivacy, .sensitive)
            assertAttributeFailure(key: key, value: "PrivateRepository", privacy: "public", .privacyBelowFloor)
        }
    }

    func testFreeTextCredentialMarkersRejectCamelCaseAndCompatibilityForms() {
        for value in [
            "apiKey: opaque",
            "accessToken opaque",
            "refreshToken=opaque",
            "clientSecret: opaque",
            "privateKey=opaque",
            "accessＴoken＝opaque"
        ] {
            XCTAssertTrue(
                ObservabilitySafetyPolicy.assess(text: value).containsCredential,
                value
            )
        }
    }

    func testUnicodeConfusableAttributeKeyIsRejected() {
        assertAttributeFailure(
            key: "accessＴoken",
            value: "opaque",
            privacy: "sensitive",
            .invalidAttributeKey
        )
    }

    func testUnicodeBoundaryLocatorsTakeHighestClassification() {
        XCTAssertEqual(
            ObservabilitySafetyPolicy.assess(text: "source is private-client.pdf").locator,
            .fileName
        )
        XCTAssertEqual(
            ObservabilitySafetyPolicy.assess(text: "source\u{00a0}private-client.pdf").locator,
            .fileName
        )
        XCTAssertEqual(
            ObservabilitySafetyPolicy.assess(text: "report\u{3002}pdf").locator,
            .fileName
        )
        XCTAssertEqual(
            ObservabilitySafetyPolicy.assess(text: "source is /Users/person/private-client.pdf").locator,
            .fullPath
        )
        XCTAssertEqual(
            ObservabilitySafetyPolicy.assess(text: "source=/.ssh/id_ed25519").locator,
            .fullPath
        )
        XCTAssertEqual(
            ObservabilitySafetyPolicy.assess(text: "来源，/用户/机密.txt").locator,
            .fullPath
        )
        XCTAssertEqual(
            ObservabilitySafetyPolicy.assess(text: "来源\u{00a0}/用户/机密.txt").locator,
            .fullPath
        )
    }

    func testResourceContractAcceptsOnlyCanonicalWireShape() {
        let valid = ObservabilityResourceSnapshot(
            resourceID: UUID().uuidString.lowercased(),
            alias: "file.0123456789abcdef01234567",
            pathExtension: "pdf",
            sizeBucket: "lt_1mb",
            storageMode: "copied"
        )
        assertSuccess(ObservabilitySafetyPolicy.validate(resource: valid))

        var invalid = valid
        invalid.resourceID = "resource-id"
        assertFailure(ObservabilitySafetyPolicy.validate(resource: invalid), .invalidResource)
        invalid = valid
        invalid.alias = "file.0123456789ABCDEF01234567"
        assertFailure(ObservabilitySafetyPolicy.validate(resource: invalid), .invalidResource)
        invalid = valid
        invalid.pathExtension = "PDF"
        assertFailure(ObservabilitySafetyPolicy.validate(resource: invalid), .invalidResource)
        invalid = valid
        invalid.sizeBucket = "tiny"
        assertFailure(ObservabilitySafetyPolicy.validate(resource: invalid), .invalidResource)
        invalid = valid
        invalid.storageMode = "external"
        assertFailure(ObservabilitySafetyPolicy.validate(resource: invalid), .invalidResource)
    }

    func testBuildContextRequiresProducerSpecificTuple() {
        let app = ObservabilityBuildContextSnapshot.currentApp
        let core = buildContext(producer: "area_matrix_core", architecture: "aarch64")
        assertSuccess(ObservabilitySafetyPolicy.validate(
            buildContext: app,
            schemaVersion: 2,
            scope: .liveApp
        ))
        assertSuccess(ObservabilitySafetyPolicy.validate(
            buildContext: core,
            schemaVersion: 2,
            scope: .liveCore(expected: core)
        ))
        assertSuccess(ObservabilitySafetyPolicy.validate(
            buildContext: core,
            schemaVersion: 2,
            scope: .diagnosticPackage
        ))
        assertSuccess(ObservabilitySafetyPolicy.validate(
            buildContext: nil,
            schemaVersion: 1,
            scope: .diagnosticPackage
        ))
        assertBuildFailure(nil, schema: 1, scope: .liveApp)

        assertBuildFailure(buildContext(producer: "area_matrix_core", architecture: "arm64"), schema: 2)
        var linux = app
        linux.platform = "linux"
        assertBuildFailure(linux, schema: 2)
        assertBuildFailure(nil, schema: 2)
        assertBuildFailure(app, schema: 1)
    }

    func testLiveBuildScopeRejectsHistoricalAppIdentityWithoutRejectingHistoricalPackages() {
        var historical = ObservabilityBuildContextSnapshot.currentApp
        historical.version = historical.version == "0.0.1" ? "0.0.2" : "0.0.1"

        assertBuildFailure(historical, schema: 2, scope: .liveApp)
        assertSuccess(ObservabilitySafetyPolicy.validate(
            buildContext: historical,
            schemaVersion: 2,
            scope: .diagnosticPackage
        ))
    }

    func testHistoricalCoreIdentityRemainsReadableFromSchemaTwoPackage() {
        var historical = buildContext(producer: "area_matrix_core", architecture: "aarch64")
        historical.version = "0.0.1"

        assertSuccess(ObservabilitySafetyPolicy.validate(
            buildContext: historical,
            schemaVersion: 2,
            scope: .diagnosticPackage
        ))
    }

    func testLiveCoreBuildScopeRequiresExactLoadedIdentity() {
        let expected = buildContext(producer: "area_matrix_core", architecture: "aarch64")
        var wrongProducer = expected
        wrongProducer.producer = "areamatrix_macos"
        var wrongVersion = expected
        wrongVersion.version = "0.2.0"
        var wrongBuild = expected
        wrongBuild.build = "other"
        var wrongConfiguration = expected
        wrongConfiguration.configuration = "release"
        var wrongPlatform = expected
        wrongPlatform.platform = "linux"
        var wrongArchitecture = expected
        wrongArchitecture.architecture = "x86_64"

        let mismatches = [
            wrongProducer,
            wrongVersion,
            wrongBuild,
            wrongConfiguration,
            wrongPlatform,
            wrongArchitecture
        ]
        for candidate in mismatches {
            assertBuildFailure(
                candidate,
                schema: 2,
                scope: .liveCore(expected: expected)
            )
        }
        assertSuccess(ObservabilitySafetyPolicy.validate(
            buildContext: expected,
            schemaVersion: 2,
            scope: .liveCore(expected: expected)
        ))
    }
}

private extension ObservabilitySafetyPolicyTests {
    func buildContext(producer: String, architecture: String) -> ObservabilityBuildContextSnapshot {
        ObservabilityBuildContextSnapshot(
            producer: producer,
            version: "0.1.0",
            build: "test",
            configuration: "debug",
            platform: "macos",
            architecture: architecture
        )
    }

    func assertAttributeFailure(
        key: String,
        value: String,
        privacy: String,
        _ expected: ObservabilitySafetyPolicy.Violation,
        file: StaticString = #filePath,
        line: UInt = #line
    ) {
        assertFailure(
            ObservabilitySafetyPolicy.assess(attribute: .init(key: key, value: value, privacy: privacy)),
            expected,
            file: file,
            line: line
        )
    }

    func assertBuildFailure(
        _ context: ObservabilityBuildContextSnapshot?,
        schema: UInt64,
        scope: ObservabilitySafetyPolicy.BuildScope = .diagnosticPackage,
        file: StaticString = #filePath,
        line: UInt = #line
    ) {
        assertFailure(
            ObservabilitySafetyPolicy.validate(
                buildContext: context,
                schemaVersion: schema,
                scope: scope
            ),
            .invalidBuildContext,
            file: file,
            line: line
        )
    }

    func assertSuccess(
        _ result: Result<some Any, ObservabilitySafetyPolicy.Violation>,
        file: StaticString = #filePath,
        line: UInt = #line
    ) {
        guard case .success = result else {
            return XCTFail("Expected success, got \(result).", file: file, line: line)
        }
    }

    func assertFailure(
        _ result: Result<some Any, ObservabilitySafetyPolicy.Violation>,
        _ expected: ObservabilitySafetyPolicy.Violation,
        file: StaticString = #filePath,
        line: UInt = #line
    ) {
        guard case let .failure(actual) = result else {
            return XCTFail("Expected \(expected), got \(result).", file: file, line: line)
        }
        XCTAssertEqual(actual, expected, file: file, line: line)
    }
}
