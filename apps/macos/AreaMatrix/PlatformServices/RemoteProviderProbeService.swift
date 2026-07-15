import Foundation
import Security

enum RemoteProviderCredentialKeychain {
    static let service = "AreaMatrix.RemoteAI"
}

extension String {
    var remoteProviderKeychainAccount: String? {
        guard hasPrefix("keychain:") else { return nil }
        let account = String(dropFirst("keychain:".count))
        return account.isEmpty ? nil : account
    }
}

enum RemoteProviderProbeMethodState: Equatable {
    case get
}

enum RemoteProviderProbeAuthorizationState: Equatable {
    case bearer
    case anthropicAPIKey
}

struct RemoteProviderProbeHeaderState: Equatable {
    let name: String
    let value: String
}

struct RemoteProviderProbePlanState: Equatable {
    let keyReference: String
    let probeToken: String
    let method: RemoteProviderProbeMethodState
    let url: String
    let headers: [RemoteProviderProbeHeaderState]
    let authorization: RemoteProviderProbeAuthorizationState
    let timeoutMilliseconds: UInt32
    let maximumResponseBodyBytes: UInt64
    let followRedirects: Bool
}

enum RemoteProviderProbeOutcomeState: Equatable {
    case httpResponse
    case connectionFailed
    case credentialUnavailable
}

struct RemoteProviderProbeObservationState: Equatable {
    let probeToken: String
    let outcome: RemoteProviderProbeOutcomeState
    let httpStatus: UInt32?
}

protocol RemoteProviderProbePerforming: Sendable {
    func perform(plan: RemoteProviderProbePlanState) async -> RemoteProviderProbeObservationState
}

protocol RemoteProviderProbeCredentialReading: Sendable {
    func credential(reference: String) -> String?
}

protocol RemoteProviderProbeHTTPTransporting: Sendable {
    func status(for request: RemoteProviderProbeHTTPRequest) async -> UInt32?
}

struct RemoteProviderProbeHTTPRequest {
    let url: URL
    let method: String
    let headers: [String: String]
    let timeout: TimeInterval
}

actor RemoteProviderProbeService: RemoteProviderProbePerforming {
    static let shared = RemoteProviderProbeService()

    private let credentialReader: any RemoteProviderProbeCredentialReading
    private let transport: any RemoteProviderProbeHTTPTransporting

    init(
        credentialReader: any RemoteProviderProbeCredentialReading = KeychainProbeCredentialReader(),
        transport: any RemoteProviderProbeHTTPTransporting = URLSessionRemoteProviderProbeTransport()
    ) {
        self.credentialReader = credentialReader
        self.transport = transport
    }

    func perform(plan: RemoteProviderProbePlanState) async -> RemoteProviderProbeObservationState {
        guard let credential = credentialReader.credential(reference: plan.keyReference),
              isUsableCredential(credential)
        else {
            return observation(plan: plan, outcome: .credentialUnavailable)
        }
        guard let request = makeRequest(plan: plan, credential: credential) else {
            return observation(plan: plan, outcome: .connectionFailed)
        }
        guard let status = await transport.status(for: request) else {
            return observation(plan: plan, outcome: .connectionFailed)
        }
        return observation(plan: plan, outcome: .httpResponse, httpStatus: status)
    }

    private func makeRequest(
        plan: RemoteProviderProbePlanState,
        credential: String
    ) -> RemoteProviderProbeHTTPRequest? {
        guard plan.method == .get,
              plan.maximumResponseBodyBytes == 0,
              !plan.followRedirects,
              let url = URL(string: plan.url),
              isAllowedURL(url),
              plan.timeoutMilliseconds > 0
        else {
            return nil
        }

        var headers = ["User-Agent": "AreaMatrix"]
        for header in plan.headers {
            guard isAllowedStaticHeader(header) else { return nil }
            headers[header.name] = header.value
        }
        switch plan.authorization {
        case .bearer:
            headers["Authorization"] = "Bearer \(credential)"
        case .anthropicAPIKey:
            headers["x-api-key"] = credential
        }
        return RemoteProviderProbeHTTPRequest(
            url: url,
            method: "GET",
            headers: headers,
            timeout: TimeInterval(plan.timeoutMilliseconds) / 1000
        )
    }

    private func observation(
        plan: RemoteProviderProbePlanState,
        outcome: RemoteProviderProbeOutcomeState,
        httpStatus: UInt32? = nil
    ) -> RemoteProviderProbeObservationState {
        RemoteProviderProbeObservationState(
            probeToken: plan.probeToken,
            outcome: outcome,
            httpStatus: httpStatus
        )
    }

    private func isUsableCredential(_ credential: String) -> Bool {
        !credential.isEmpty && !credential.unicodeScalars.contains { CharacterSet.controlCharacters.contains($0) }
    }

    private func isAllowedStaticHeader(_ header: RemoteProviderProbeHeaderState) -> Bool {
        let name = header.name.lowercased()
        return !header.name.isEmpty
            && !header.value.unicodeScalars.contains { CharacterSet.controlCharacters.contains($0) }
            && name != "authorization"
            && name != "x-api-key"
    }

    private func isAllowedURL(_ url: URL) -> Bool {
        guard url.user == nil, url.password == nil else { return false }
        if url.scheme?.lowercased() == "https" { return true }
        guard url.scheme?.lowercased() == "http" else { return false }
        return ["localhost", "127.0.0.1", "::1"].contains(url.host?.lowercased() ?? "")
    }
}

struct KeychainProbeCredentialReader: RemoteProviderProbeCredentialReading {
    func credential(reference: String) -> String? {
        guard let account = reference.remoteProviderKeychainAccount else { return nil }
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: RemoteProviderCredentialKeychain.service,
            kSecAttrAccount as String: account,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne
        ]
        var item: CFTypeRef?
        guard SecItemCopyMatching(query as CFDictionary, &item) == errSecSuccess,
              let data = item as? Data
        else {
            return nil
        }
        return String(data: data, encoding: .utf8)
    }
}

final class URLSessionRemoteProviderProbeTransport: RemoteProviderProbeHTTPTransporting, @unchecked Sendable {
    private let protocolClasses: [AnyClass]?

    init(protocolClasses: [AnyClass]? = nil) {
        self.protocolClasses = protocolClasses
    }

    func status(for request: RemoteProviderProbeHTTPRequest) async -> UInt32? {
        var urlRequest = URLRequest(
            url: request.url,
            cachePolicy: .reloadIgnoringLocalCacheData,
            timeoutInterval: request.timeout
        )
        urlRequest.httpMethod = request.method
        for (name, value) in request.headers {
            urlRequest.setValue(value, forHTTPHeaderField: name)
        }

        let sessionBox = RemoteProviderProbeSessionBox()
        return await withTaskCancellationHandler {
            await withCheckedContinuation { continuation in
                let delegate = RemoteProviderProbeSessionDelegate { status in
                    continuation.resume(returning: status)
                    sessionBox.cancel()
                }
                let configuration = URLSessionConfiguration.ephemeral
                configuration.timeoutIntervalForRequest = request.timeout
                configuration.timeoutIntervalForResource = request.timeout
                configuration.requestCachePolicy = .reloadIgnoringLocalCacheData
                configuration.urlCache = nil
                configuration.httpCookieStorage = nil
                configuration.httpShouldSetCookies = false
                configuration.waitsForConnectivity = false
                configuration.protocolClasses = protocolClasses
                let session = URLSession(configuration: configuration, delegate: delegate, delegateQueue: nil)
                sessionBox.install(session)
                session.dataTask(with: urlRequest).resume()
            }
        } onCancel: {
            sessionBox.cancel()
        }
    }
}

private final class RemoteProviderProbeSessionBox: @unchecked Sendable {
    private let lock = NSLock()
    private var session: URLSession?
    private var isCancelled = false

    func install(_ session: URLSession) {
        lock.lock()
        self.session = session
        let shouldCancel = isCancelled
        lock.unlock()
        if shouldCancel {
            session.invalidateAndCancel()
        }
    }

    func cancel() {
        lock.lock()
        isCancelled = true
        let session = session
        lock.unlock()
        session?.invalidateAndCancel()
    }
}

private final class RemoteProviderProbeSessionDelegate: NSObject,
    URLSessionDataDelegate,
    URLSessionTaskDelegate,
    @unchecked Sendable {
    private let lock = NSLock()
    private var completion: (@Sendable (UInt32?) -> Void)?

    init(completion: @escaping @Sendable (UInt32?) -> Void) {
        self.completion = completion
    }

    func urlSession(
        _: URLSession,
        dataTask _: URLSessionDataTask,
        didReceive response: URLResponse,
        completionHandler: @escaping (URLSession.ResponseDisposition) -> Void
    ) {
        resolve(status(from: response))
        completionHandler(.cancel)
    }

    func urlSession(
        _: URLSession,
        task _: URLSessionTask,
        willPerformHTTPRedirection response: HTTPURLResponse,
        newRequest _: URLRequest,
        completionHandler: @escaping (URLRequest?) -> Void
    ) {
        resolve(UInt32(response.statusCode))
        completionHandler(nil)
    }

    func urlSession(_: URLSession, task _: URLSessionTask, didCompleteWithError _: Error?) {
        resolve(nil)
    }

    private func status(from response: URLResponse) -> UInt32? {
        guard let response = response as? HTTPURLResponse,
              (100 ... 599).contains(response.statusCode)
        else {
            return nil
        }
        return UInt32(response.statusCode)
    }

    private func resolve(_ status: UInt32?) {
        lock.lock()
        let completion = completion
        self.completion = nil
        lock.unlock()
        completion?(status)
    }
}
