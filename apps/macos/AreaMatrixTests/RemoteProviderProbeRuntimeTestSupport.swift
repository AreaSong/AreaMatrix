@testable import AreaMatrix
import Foundation

func makeRemoteProviderProbeTemporaryRepoURL() throws -> URL {
    try makeTestTemporaryDirectory(named: "AreaMatrixRemoteProviderProbeRuntimeTests")
}

@MainActor
func aiCategorySuggestionPrivacyRuleReferenceModel(
    ruleID: String,
    bridge: any CoreAIPrivacyRulesManaging
) -> AIClassificationPrivacyRuleReferenceModel {
    AIClassificationPrivacyRuleReferenceModel(
        repoPath: "/tmp/repo",
        ruleID: ruleID,
        bridge: bridge,
        errorMapper: AIPrivacyRuleErrorMapper()
    )
}

final class ProbeRuntimeRecorder {
    let endpointURL = "http://127.0.0.1:1/probe"
    let evidenceURL: URL
    let runtimeURL: URL

    init() throws {
        let directory = try makeTestTemporaryDirectory(named: "AreaMatrixRemoteProviderProbeRuntimeTests")
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

final class ProbeRuntimeEnvironment {
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

func environmentString(_ key: String) -> String? {
    guard let pointer = getenv(key) else { return nil }
    return String(cString: pointer)
}

actor AIPrivacyRulesFailingBridge: CoreAIPrivacyRulesManaging {
    func loadAIPrivacyRules(repoPath _: String) async throws -> AiPrivacyRulesSnapshot {
        throw CoreError.Db(message: "privacy rules read failed")
    }

    func updateAIPrivacyRules(
        repoPath _: String,
        request _: AiPrivacyRulesUpdateRequest
    ) async throws -> AiPrivacyRulesSnapshot {
        throw CoreError.Db(message: "privacy rules write failed")
    }
}

struct AIPrivacyRuleErrorMapper: CoreErrorMapping {
    func mapCoreError(_: CoreError) async -> CoreErrorMappingSnapshot {
        CoreErrorMappingSnapshot(
            kind: .db,
            userMessage: "Mapped ai-privacy-rules-core core error",
            severity: .medium,
            suggestedAction: "Open privacy rules",
            recoverability: .userActionRequired,
            rawContext: "ai-category-suggestion ai-privacy-rules-core"
        )
    }
}

extension AIClassificationSuggestionState {
    static func aiCategorySuggestionPrivacySkipped(fileID: Int64) -> AIClassificationSuggestionState {
        AIClassificationSuggestionState(
            fileID: fileID,
            status: .skipped,
            currentCategory: "inbox",
            suggestedCategory: nil,
            confidence: 0,
            reason: nil,
            route: nil,
            usedContext: [],
            skippedReason: .privacyRule,
            privacyRuleID: "rule-confidential",
            callLogID: 305,
            requiresUserConfirmation: true
        )
    }
}
