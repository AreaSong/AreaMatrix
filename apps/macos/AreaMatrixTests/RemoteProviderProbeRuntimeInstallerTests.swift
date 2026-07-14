@testable import AreaMatrix
import Foundation
import XCTest

final class RemoteProviderProbeRuntimeInstallerTests: XCTestCase {
    func testInstallerRegistersVersionedCredentialBackedRuntime() async throws {
        let directory = try makeTestTemporaryDirectory(named: "AreaMatrixRemoteProviderProbeRuntimeInstaller")
        defer { removeTestTemporaryItems(directory) }
        let environment = ProbeRuntimeEnvironment(runtimePath: nil, evidencePath: nil)
        environment.clearRuntime()
        defer { environment.restore() }
        let installer = RemoteProviderProbeRuntimeInstaller(baseDirectory: directory)

        let descriptor = try await installer.ensureInstalled()
        let attributes = try FileManager.default.attributesOfItem(atPath: descriptor.executablePath)
        let permissions = try XCTUnwrap(attributes[.posixPermissions] as? Int)
        let script = try String(contentsOfFile: descriptor.executablePath, encoding: .utf8)
        let syntaxCheck = Process()
        syntaxCheck.executableURL = URL(fileURLWithPath: "/bin/sh")
        syntaxCheck.arguments = ["-n", descriptor.executablePath]
        try syntaxCheck.run()
        syntaxCheck.waitUntilExit()

        XCTAssertEqual(
            environmentString(RemoteProviderProbeRuntimeInstaller.environmentKey),
            descriptor.executablePath
        )
        XCTAssertEqual(descriptor.version, RemoteProviderProbeRuntimeInstaller.runtimeVersion)
        XCTAssertEqual(descriptor.contentHash.count, 64)
        XCTAssertGreaterThan(descriptor.inode, 0)
        XCTAssertEqual(permissions, 0o700)
        XCTAssertEqual(syntaxCheck.terminationStatus, 0)
        XCTAssertTrue(script.contains("/usr/bin/security find-generic-password"))
        XCTAssertTrue(script.contains("--request \"$method\""))
        XCTAssertTrue(script.contains("--url \"$url\""))
        XCTAssertTrue(script.contains("--header @-"))
        XCTAssertTrue(script.contains("printf 'Authorization: Bearer %s\\n' \"$credential\""))
        XCTAssertTrue(script.contains("printf 'x-api-key: %s\\nanthropic-version: 2023-06-01\\n' \"$credential\""))
        XCTAssertTrue(script.contains("000|408|425|429|5?? ) printf 'ConnectionFailed\\n'"))
        XCTAssertFalse(script.contains("curl --config -"))
        XCTAssertFalse(script.contains("--header \"Authorization: Bearer $credential\""))
        XCTAssertFalse(script.contains("--header \"x-api-key: $credential\""))
    }

    func testInstallerRepairsRuntimeWithWeakPermissionsOrUnexpectedContent() async throws {
        let directory = try makeTestTemporaryDirectory(named: "AreaMatrixRemoteProviderProbeRuntimeUntrusted")
        defer { removeTestTemporaryItems(directory) }
        try FileManager.default.setAttributes([.posixPermissions: 0o700], ofItemAtPath: directory.path)
        let runtimeURL = directory.appendingPathComponent(RemoteProviderProbeRuntimeInstaller.runtimeFileName)
        try "#!/bin/sh\nprintf 'unexpected-runtime\\n'\n".write(
            to: runtimeURL,
            atomically: true,
            encoding: .utf8
        )
        try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: runtimeURL.path)

        let installer = RemoteProviderProbeRuntimeInstaller(baseDirectory: directory)
        let descriptor = try await installer.ensureInstalled()
        let attributes = try FileManager.default.attributesOfItem(atPath: descriptor.executablePath)
        let permissions = try XCTUnwrap(attributes[.posixPermissions] as? Int)
        let script = try String(contentsOfFile: descriptor.executablePath, encoding: .utf8)

        XCTAssertEqual(descriptor.executablePath, runtimeURL.path)
        XCTAssertEqual(permissions, 0o700)
        XCTAssertTrue(script.contains("AreaMatrix.RemoteAI"))
        XCTAssertFalse(script.contains("unexpected-runtime"))
    }

    func testInstallerReplacesRuntimeSymlinkWithoutChangingItsTarget() async throws {
        let directory = try makeTestTemporaryDirectory(named: "AreaMatrixRemoteProviderProbeRuntimeSymlink")
        defer { removeTestTemporaryItems(directory) }
        try FileManager.default.setAttributes([.posixPermissions: 0o700], ofItemAtPath: directory.path)
        let targetURL = directory.appendingPathComponent("target-runtime.sh")
        let runtimeURL = directory.appendingPathComponent(RemoteProviderProbeRuntimeInstaller.runtimeFileName)
        try "#!/bin/sh\nprintf 'symlink-target\\n'\n".write(to: targetURL, atomically: true, encoding: .utf8)
        try FileManager.default.setAttributes([.posixPermissions: 0o700], ofItemAtPath: targetURL.path)
        try FileManager.default.createSymbolicLink(at: runtimeURL, withDestinationURL: targetURL)

        let installer = RemoteProviderProbeRuntimeInstaller(baseDirectory: directory)
        let descriptor = try await installer.ensureInstalled()
        let installedAttributes = try FileManager.default.attributesOfItem(atPath: descriptor.executablePath)
        let targetContents = try String(contentsOf: targetURL, encoding: .utf8)

        XCTAssertEqual(installedAttributes[.type] as? FileAttributeType, .typeRegular)
        XCTAssertEqual(targetContents, "#!/bin/sh\nprintf 'symlink-target\\n'\n")
    }

    func testInstallerRevalidatesAndRepairsCachedDescriptor() async throws {
        let directory = try makeTestTemporaryDirectory(named: "AreaMatrixRemoteProviderProbeRuntimeRevalidation")
        defer { removeTestTemporaryItems(directory) }
        let installer = RemoteProviderProbeRuntimeInstaller(baseDirectory: directory)
        let initial = try await installer.ensureInstalled()
        try "#!/bin/sh\nprintf 'mutated\\n'\n".write(
            toFile: initial.executablePath,
            atomically: true,
            encoding: .utf8
        )
        try FileManager.default.setAttributes([.posixPermissions: 0o700], ofItemAtPath: initial.executablePath)

        let repaired = try await installer.ensureInstalled()
        let repairedScript = try String(contentsOfFile: repaired.executablePath, encoding: .utf8)

        XCTAssertEqual(repaired.version, initial.version)
        XCTAssertEqual(repaired.contentHash, initial.contentHash)
        XCTAssertNotEqual(repaired.inode, initial.inode)
        XCTAssertFalse(repairedScript.contains("mutated"))
    }
}
