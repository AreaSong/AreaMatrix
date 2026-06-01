import Foundation
import Security

protocol RemoteProviderProbeRuntimeInstalling {
    func ensureInstalled() throws -> String
}

struct RemoteProviderProbeRuntimeInstaller: RemoteProviderProbeRuntimeInstalling {
    static let environmentKey = "AREAMATRIX_REMOTE_PROVIDER_PROBE_RUNTIME"

    private let fileManager: FileManager
    private let processInfo: ProcessInfo

    init(fileManager: FileManager = .default, processInfo: ProcessInfo = .processInfo) {
        self.fileManager = fileManager
        self.processInfo = processInfo
    }

    func ensureInstalled() throws -> String {
        if let existing = installedRuntimePath {
            return existing
        }

        let runtimeURL = try runtimeDirectory().appendingPathComponent("remote-provider-probe-runtime.sh")
        try runtimeScript.write(to: runtimeURL, atomically: true, encoding: .utf8)
        try fileManager.setAttributes([.posixPermissions: 0o700], ofItemAtPath: runtimeURL.path)
        setenv(Self.environmentKey, runtimeURL.path, 1)
        return runtimeURL.path
    }

    private var installedRuntimePath: String? {
        if let value = getenv(Self.environmentKey) {
            let path = String(cString: value)
            if !path.isEmpty { return path }
        }
        guard let path = processInfo.environment[Self.environmentKey], !path.isEmpty else { return nil }
        return path
    }

    private func runtimeDirectory() throws -> URL {
        let baseURL = fileManager.temporaryDirectory.appendingPathComponent(
            "AreaMatrixRemoteProviderProbeRuntime",
            isDirectory: true
        )
        try fileManager.createDirectory(at: baseURL, withIntermediateDirectories: true)
        return baseURL
    }

    private var runtimeScript: String {
        #"""
        #!/bin/sh
        set -eu

        payload="$(mktemp "${TMPDIR:-/tmp}/areamatrix-remote-provider-probe.XXXXXX")"
        trap 'rm -f "$payload"' EXIT
        cat > "$payload"

        provider="$(/usr/bin/plutil -extract provider raw -o - "$payload")"
        method="$(/usr/bin/plutil -extract method raw -o - "$payload")"
        key_reference="$(/usr/bin/plutil -extract key_reference raw -o - "$payload")"
        if ! url="$(/usr/bin/plutil -extract url raw -o - "$payload")"; then
            printf 'ConnectionFailed\n'
            exit 0
        fi

        account="${key_reference#keychain:}"
        if [ "$account" = "$key_reference" ] || [ -z "$account" ]; then
            printf 'ConnectionFailed\n'
            exit 0
        fi

        credential="$(
            /usr/bin/security find-generic-password -s 'AreaMatrix.RemoteAI' -a "$account" -w 2>/dev/null || true
        )"
        if [ -z "$credential" ]; then
            printf 'ConnectionFailed\n'
            exit 0
        fi

        status="$({
            printf 'silent\n'
            printf 'show-error\n'
            printf 'output = "/dev/null"\n'
            printf 'write-out = "%%{http_code}"\n'
            printf 'request = "%s"\n' "$method"
            printf 'max-time = "10"\n'
            printf 'url = "%s"\n' "$url"
            case "$provider" in
                Anthropic)
                    printf 'header = "x-api-key: %s"\n' "$credential"
                    printf 'header = "anthropic-version: 2023-06-01"\n'
                    ;;
                *)
                    printf 'header = "Authorization: Bearer %s"\n' "$credential"
                    ;;
            esac
        } | /usr/bin/curl --config - 2>/dev/null || true)"
        case "$status" in
            2* ) printf 'Succeeded\n' ;;
            400|401|403|422 ) printf 'ProviderRejected\n' ;;
            404 )
                if [ "$provider" = "Other" ]; then
                    printf 'UnsupportedProvider\n'
                else
                    printf 'ProviderRejected\n'
                fi
                ;;
            408|425|429|5?? ) printf 'ConnectionFailed\n' ;;
            * ) printf 'UnsupportedProvider\n' ;;
        esac
        """#
    }
}
