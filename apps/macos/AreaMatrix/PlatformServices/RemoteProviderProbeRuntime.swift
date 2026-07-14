import CryptoKit
import Darwin
import Foundation
import Security

struct RemoteProviderProbeRuntimeDescriptor: Equatable {
    let executablePath: String
    let version: String
    let contentHash: String
    let device: UInt64
    let inode: UInt64
}

protocol RemoteProviderProbeRuntimeInstalling: Sendable {
    func ensureInstalled() async throws -> RemoteProviderProbeRuntimeDescriptor
}

actor RemoteProviderProbeRuntimeInstaller: RemoteProviderProbeRuntimeInstalling {
    static let shared = RemoteProviderProbeRuntimeInstaller()
    static let environmentKey = "AREAMATRIX_REMOTE_PROVIDER_PROBE_RUNTIME"
    static let runtimeFileName = "remote-provider-probe-runtime-v1.sh"
    static let runtimeVersion = "remote-provider-probe-runtime-v1"

    private let fileManager: FileManager
    private let runtimeRoot: URL
    private var cachedDescriptor: RemoteProviderProbeRuntimeDescriptor?

    init(fileManager: FileManager = .default, baseDirectory: URL? = nil) {
        self.fileManager = fileManager
        runtimeRoot = baseDirectory ?? Self.defaultRuntimeRoot(fileManager: fileManager)
    }

    func ensureInstalled() async throws -> RemoteProviderProbeRuntimeDescriptor {
        let runtimeURL = runtimeRoot.appendingPathComponent(Self.runtimeFileName)
        if let cachedDescriptor, isTrusted(cachedDescriptor, at: runtimeURL) {
            try activate(cachedDescriptor)
            return cachedDescriptor
        }

        try prepareRuntimeRoot()
        if fileInfo(runtimeURL.path) != nil, descriptor(for: runtimeURL) == nil {
            try fileManager.removeItem(at: runtimeURL)
        }
        try runtimeScript.write(to: runtimeURL, atomically: true, encoding: .utf8)
        try fileManager.setAttributes([.posixPermissions: 0o700], ofItemAtPath: runtimeURL.path)
        guard let descriptor = descriptor(for: runtimeURL) else {
            throw CocoaError(.fileWriteUnknown, userInfo: [NSFilePathErrorKey: runtimeURL.path])
        }
        try activate(descriptor)
        cachedDescriptor = descriptor
        return descriptor
    }

    private static func defaultRuntimeRoot(fileManager: FileManager) -> URL {
        let appSupport = fileManager.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? fileManager.temporaryDirectory
        return appSupport
            .appendingPathComponent("AreaMatrix", isDirectory: true)
            .appendingPathComponent("RemoteProviderProbeRuntime", isDirectory: true)
            .appendingPathComponent(Self.runtimeVersion, isDirectory: true)
    }

    private func prepareRuntimeRoot() throws {
        try fileManager.createDirectory(at: runtimeRoot, withIntermediateDirectories: true)
        try fileManager.setAttributes([.posixPermissions: 0o700], ofItemAtPath: runtimeRoot.path)
        guard isTrustedDirectory(runtimeRoot.path) else {
            throw CocoaError(.fileWriteUnknown, userInfo: [NSFilePathErrorKey: runtimeRoot.path])
        }
    }

    private func descriptor(for url: URL) -> RemoteProviderProbeRuntimeDescriptor? {
        guard let info = trustedFileInfo(url.path),
              let data = try? Data(contentsOf: url),
              data == Data(runtimeScript.utf8)
        else {
            return nil
        }
        return RemoteProviderProbeRuntimeDescriptor(
            executablePath: url.path,
            version: Self.runtimeVersion,
            contentHash: contentHash(data),
            device: UInt64(info.st_dev),
            inode: UInt64(info.st_ino)
        )
    }

    private func isTrusted(
        _ descriptor: RemoteProviderProbeRuntimeDescriptor,
        at url: URL
    ) -> Bool {
        guard descriptor.executablePath == url.path,
              descriptor.version == Self.runtimeVersion,
              let current = self.descriptor(for: url)
        else {
            return false
        }
        return current == descriptor
    }

    private func activate(_ descriptor: RemoteProviderProbeRuntimeDescriptor) throws {
        guard setenv(Self.environmentKey, descriptor.executablePath, 1) == 0 else {
            throw CocoaError(.fileWriteUnknown, userInfo: [NSFilePathErrorKey: descriptor.executablePath])
        }
    }

    private func isTrustedDirectory(_ path: String) -> Bool {
        guard let info = fileInfo(path),
              (info.st_mode & S_IFMT) == S_IFDIR,
              (info.st_mode & 0o777) == 0o700,
              info.st_uid == geteuid()
        else {
            return false
        }
        return true
    }

    private func trustedFileInfo(_ path: String) -> stat? {
        guard let info = fileInfo(path),
              (info.st_mode & S_IFMT) == S_IFREG,
              (info.st_mode & 0o777) == 0o700,
              info.st_uid == geteuid()
        else {
            return nil
        }
        return info
    }

    private func fileInfo(_ path: String) -> stat? {
        var fileInfo = stat()
        return lstat(path, &fileInfo) == 0 ? fileInfo : nil
    }

    private func contentHash(_ data: Data) -> String {
        SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
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
        if printf '%s' "$credential" | LC_ALL=C /usr/bin/grep -q '[[:cntrl:]]'; then
            printf 'ConnectionFailed\n'
            exit 0
        fi

        case "$method" in
            GET|HEAD) ;;
            *) printf 'UnsupportedProvider\n'; exit 0 ;;
        esac

        case "$url" in
            https://*|http://localhost:*|http://127.0.0.1:*|http://\[::1\]:*) ;;
            *) printf 'UnsupportedProvider\n'; exit 0 ;;
        esac

        case "$provider" in
            Anthropic)
                if ! status="$(
                    printf 'x-api-key: %s\nanthropic-version: 2023-06-01\n' "$credential" |
                        /usr/bin/curl --silent --show-error --output /dev/null \
                            --write-out '%{http_code}' --request "$method" --max-time 10 --url "$url" \
                            --header @- 2>/dev/null
                )"; then
                    status="000"
                fi
                ;;
            OpenAi|Other)
                if ! status="$(
                    printf 'Authorization: Bearer %s\n' "$credential" |
                        /usr/bin/curl --silent --show-error --output /dev/null \
                            --write-out '%{http_code}' --request "$method" --max-time 10 --url "$url" \
                            --header @- 2>/dev/null
                )"; then
                    status="000"
                fi
                ;;
            *)
                printf 'UnsupportedProvider\n'
                exit 0
                ;;
        esac
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
            000|408|425|429|5?? ) printf 'ConnectionFailed\n' ;;
            * ) printf 'UnsupportedProvider\n' ;;
        esac
        """#
    }
}
