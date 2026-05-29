@testable import AreaMatrix
import Foundation
import XCTest

final class RemoteProviderProbeRuntimeTests: XCTestCase {
    @MainActor
    func testCoreBridgeUsesInstalledRuntimeForKeychainReferenceProviderProbe() async throws {
        let runtime = try ProbeRuntimeRecorder()
        let environment = ProbeRuntimeEnvironment(
            runtimePath: runtime.runtimeURL.path,
            evidencePath: runtime.evidenceURL.path
        )
        environment.install()
        defer { environment.restore() }

        let repoURL = try makeTemporaryRepoURL()
        defer { try? FileManager.default.removeItem(at: repoURL) }
        try initRepo(repoPath: repoURL.path, options: RepoInitOptions(
            mode: .createEmpty,
            createDefaultCategories: false,
            overviewOutput: .generatedOnly
        ))
        let keyReference = "keychain:remote-ai-other-runtime-test"

        let bridge = CoreBridge()
        let testResult = try await bridge.testRemoteProvider(
            repoPath: repoURL.path,
            request: RemoteProviderTestRequestState(
                provider: .other,
                modelID: "gpt-4.1-mini",
                endpointURL: runtime.endpointURL,
                keyReference: keyReference
            )
        )

        let verificationToken = try XCTUnwrap(testResult.verificationToken)
        let enableSnapshot = try await bridge.enableRemoteProvider(
            repoPath: repoURL.path,
            request: RemoteProviderEnableRequestState(
                provider: .other,
                modelID: "gpt-4.1-mini",
                endpointURL: runtime.endpointURL,
                keyReference: keyReference,
                featureScope: [.autoSummaries],
                verificationToken: verificationToken,
                dataFlowConfirmed: true
            )
        )

        XCTAssertEqual(testResult.status, .succeeded)
        XCTAssertTrue(testResult.providerVerified)
        XCTAssertTrue(enableSnapshot.remoteProviderEnabled)
        let evidence = try runtime.evidence()
        XCTAssertTrue(evidence.contains("provider=Other"))
        XCTAssertTrue(evidence.contains("url=\(runtime.endpointURL)"))
        XCTAssertTrue(evidence.contains("key_reference=\(keyReference)"))
        XCTAssertTrue(evidence.contains("credential_reference_shape=keychain"))
    }

    func testInstallerRegistersExecutableCredentialBackedRuntime() throws {
        let environment = ProbeRuntimeEnvironment(runtimePath: nil, evidencePath: nil)
        environment.clearRuntime()
        defer { environment.restore() }
        let installer = RemoteProviderProbeRuntimeInstaller()
        let runtimePath = try installer.ensureInstalled()

        let attributes = try FileManager.default.attributesOfItem(atPath: runtimePath)
        let permissions = try XCTUnwrap(attributes[.posixPermissions] as? Int)
        let script = try String(contentsOfFile: runtimePath, encoding: .utf8)
        let installedPath = environmentString(RemoteProviderProbeRuntimeInstaller.environmentKey)
        XCTAssertEqual(installedPath, runtimePath)
        XCTAssertEqual(permissions & 0o111, 0o100)
        XCTAssertTrue(script.contains("/usr/bin/security find-generic-password"))
        XCTAssertTrue(script.contains("Authorization: Bearer %s"))
        XCTAssertTrue(script.contains("x-api-key: %s"))
        XCTAssertTrue(script.contains("$credential"))
        XCTAssertFalse(script.contains("Authorization: Bearer %s\"\\n' \"$key_reference\""))
        XCTAssertFalse(script.contains("x-api-key: %s\"\\n' \"$key_reference\""))
    }
}

private func makeTemporaryRepoURL() throws -> URL {
    let url = FileManager.default.temporaryDirectory
        .appendingPathComponent("AreaMatrixRemoteProviderProbeRuntimeTests-\(UUID().uuidString)", isDirectory: true)
    try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
    return url
}

private final class ProbeRuntimeRecorder {
    let endpointURL = "http://127.0.0.1:1/probe"
    let evidenceURL: URL
    let runtimeURL: URL

    init() throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("AreaMatrixRemoteProviderProbeRuntimeTests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        evidenceURL = directory.appendingPathComponent("probe-runtime-evidence.txt")
        runtimeURL = directory.appendingPathComponent("probe-runtime-recorder.sh")
        try recorderScript.write(to: runtimeURL, atomically: true, encoding: .utf8)
        try FileManager.default.setAttributes([.posixPermissions: 0o700], ofItemAtPath: runtimeURL.path)
    }

    func evidence() throws -> String {
        try String(contentsOf: evidenceURL, encoding: .utf8)
    }

    private var recorderScript: String {
        #"""
        #!/bin/sh
        set -eu
        payload="$(mktemp "${TMPDIR:-/tmp}/areamatrix-remote-provider-probe-test.XXXXXX")"
        trap 'rm -f "$payload"' EXIT
        cat > "$payload"
        provider="$(/usr/bin/plutil -extract provider raw -o - "$payload")"
        url="$(/usr/bin/plutil -extract url raw -o - "$payload")"
        key_reference="$(/usr/bin/plutil -extract key_reference raw -o - "$payload")"
        if [ "${key_reference#keychain:}" != "$key_reference" ]; then
            credential_reference_shape='keychain'
            status='Succeeded'
        else
            credential_reference_shape='unsupported'
            status='ConnectionFailed'
        fi
        {
            printf 'provider=%s\n' "$provider"
            printf 'url=%s\n' "$url"
            printf 'key_reference=%s\n' "$key_reference"
            printf 'credential_reference_shape=%s\n' "$credential_reference_shape"
        } > "$AREAMATRIX_REMOTE_PROVIDER_PROBE_EVIDENCE"
        printf '%s\n' "$status"
        """#
    }
}

private final class ProbeRuntimeEnvironment {
    private let oldRuntime: String?
    private let oldEvidence: String?
    private let runtimePath: String?
    private let evidencePath: String?

    init(runtimePath: String?, evidencePath: String?) {
        oldRuntime = environmentString(RemoteProviderProbeRuntimeInstaller.environmentKey)
        oldEvidence = environmentString("AREAMATRIX_REMOTE_PROVIDER_PROBE_EVIDENCE")
        self.runtimePath = runtimePath
        self.evidencePath = evidencePath
    }

    func install() {
        setEnvironmentValue(runtimePath, for: RemoteProviderProbeRuntimeInstaller.environmentKey)
        setEnvironmentValue(evidencePath, for: "AREAMATRIX_REMOTE_PROVIDER_PROBE_EVIDENCE")
    }

    func clearRuntime() {
        unsetenv(RemoteProviderProbeRuntimeInstaller.environmentKey)
    }

    func restore() {
        setEnvironmentValue(oldRuntime, for: RemoteProviderProbeRuntimeInstaller.environmentKey)
        setEnvironmentValue(oldEvidence, for: "AREAMATRIX_REMOTE_PROVIDER_PROBE_EVIDENCE")
    }

    private func setEnvironmentValue(_ value: String?, for key: String) {
        if let value {
            setenv(key, value, 1)
        } else {
            unsetenv(key)
        }
    }
}

private func environmentString(_ key: String) -> String? {
    guard let pointer = getenv(key) else { return nil }
    return String(cString: pointer)
}
