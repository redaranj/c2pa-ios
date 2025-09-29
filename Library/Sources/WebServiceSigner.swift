import C2PAC
import Crypto
import Foundation
import SwiftASN1
import X509

public final class WebServiceSigner: @unchecked Sendable {
    private let configurationURL: String
    private let bearerToken: String?
    private let customHeaders: [String: String]
    private var signingURL: String?

    public init(configurationURL: String, bearerToken: String? = nil, headers: [String: String] = [:]) {
        self.configurationURL = configurationURL
        self.bearerToken = bearerToken
        self.customHeaders = headers
    }

    @MainActor
    public func createSigner() async throws -> Signer {
        let configuration = try await fetchConfiguration()
        let signingAlgorithm = try mapAlgorithm(configuration.algorithm)
        self.signingURL = configuration.signing_url
        let certificateChain = try parseCertificateChain(configuration.certificate_chain)

        // Use strong self capture to keep WebServiceSigner alive
        return try Signer(
            algorithm: signingAlgorithm,
            certificateChainPEM: certificateChain,
            tsaURL: configuration.timestamp_url,
            asyncSigner: { [self] data in
                print("[WebServiceSigner] AsyncSigner called with data size: \(data.count)")
                return try await self.signData(data, signingURL: configuration.signing_url)
            }
        )
    }

    private func mapAlgorithm(_ algorithmString: String) throws -> SigningAlgorithm {
        switch algorithmString.lowercased() {
        case "es256":
            return .es256
        case "es384":
            return .es384
        case "es512":
            return .es512
        case "ps256":
            return .ps256
        case "ps384":
            return .ps384
        case "ps512":
            return .ps512
        case "ed25519":
            return .ed25519
        default:
            throw SignerError.unsupportedAlgorithm(algorithmString)
        }
    }

    private func fetchConfiguration() async throws -> SignerConfiguration {
        guard let url = URL(string: configurationURL) else {
            throw SignerError.invalidURL
        }

        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        request.setValue("application/json", forHTTPHeaderField: "Accept")

        // Apply custom headers first
        for (key, value) in customHeaders {
            request.setValue(value, forHTTPHeaderField: key)
        }

        // Bearer token can override Authorization header if provided
        if let bearerToken = bearerToken {
            request.setValue("Bearer \(bearerToken)", forHTTPHeaderField: "Authorization")
        }

        let (data, response) = try await URLSession.shared.data(for: request)

        guard let httpResponse = response as? HTTPURLResponse else {
            throw SignerError.invalidResponse
        }

        guard httpResponse.statusCode == 200 else {
            throw SignerError.httpError(statusCode: httpResponse.statusCode)
        }

        let decoder = JSONDecoder()
        return try decoder.decode(SignerConfiguration.self, from: data)
    }

    private func signData(_ data: Data, signingURL: String) async throws -> Data {
        print("[WebServiceSigner] Starting signData with URL: \(signingURL)")
        print("[WebServiceSigner] Data size to sign: \(data.count) bytes")

        guard let url = URL(string: signingURL) else {
            print("[WebServiceSigner] ERROR: Invalid signing URL: \(signingURL)")
            throw SignerError.invalidURL
        }

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("application/json", forHTTPHeaderField: "Accept")

        // Apply custom headers first
        for (key, value) in customHeaders {
            request.setValue(value, forHTTPHeaderField: key)
        }

        // Bearer token can override Authorization header if provided
        if let bearerToken = bearerToken {
            request.setValue("Bearer \(bearerToken)", forHTTPHeaderField: "Authorization")
            print("[WebServiceSigner] Added bearer token to request")
        }

        let requestBody = SignRequest(claim: data.base64EncodedString())
        let encoder = JSONEncoder()
        request.httpBody = try encoder.encode(requestBody)
        print("[WebServiceSigner] Request body size: \(request.httpBody?.count ?? 0) bytes")
        print("[WebServiceSigner] Making POST request to: \(url.absoluteString)")

        let (responseData, response) = try await URLSession.shared.data(for: request)
        print("[WebServiceSigner] Received response")

        guard let httpResponse = response as? HTTPURLResponse else {
            print("[WebServiceSigner] ERROR: Response is not HTTPURLResponse")
            throw SignerError.invalidResponse
        }

        print("[WebServiceSigner] Response status code: \(httpResponse.statusCode)")

        guard httpResponse.statusCode == 200 else {
            print("[WebServiceSigner] ERROR: HTTP error \(httpResponse.statusCode)")
            if let errorBody = String(data: responseData, encoding: .utf8) {
                print("[WebServiceSigner] Error response body: \(errorBody)")
            }
            throw SignerError.httpError(statusCode: httpResponse.statusCode)
        }

        let decoder = JSONDecoder()
        let signResponse = try decoder.decode(SignResponse.self, from: responseData)

        guard let signatureData = Data(base64Encoded: signResponse.signature) else {
            print("[WebServiceSigner] ERROR: Failed to decode signature from base64")
            throw SignerError.invalidSignature
        }

        print("[WebServiceSigner] Successfully decoded signature, size: \(signatureData.count) bytes")
        return signatureData
    }

    private func parseCertificateChain(_ base64Chain: String) throws -> String {
        guard let chainData = Data(base64Encoded: base64Chain) else {
            throw SignerError.invalidCertificateChain
        }

        guard let chainString = String(data: chainData, encoding: .utf8) else {
            throw SignerError.invalidCertificateChain
        }

        // Validate that we have at least one certificate
        guard chainString.contains("BEGIN CERTIFICATE") && chainString.contains("END CERTIFICATE") else {
            throw SignerError.noCertificatesFound
        }

        return chainString
    }
}

private struct SignerConfiguration: Codable {
    let algorithm: String
    let timestamp_url: String
    let signing_url: String
    let certificate_chain: String
}

private struct SignRequest: Codable {
    let claim: String  // Base64-encoded bytes to be signed
}

private struct SignResponse: Codable {
    let signature: String
}

public enum SignerError: LocalizedError {
    case invalidURL
    case invalidResponse
    case httpError(statusCode: Int)
    case unsupportedAlgorithm(String)
    case invalidCertificateChain
    case noCertificatesFound
    case invalidSignature
    case signerDeallocated

    public var errorDescription: String? {
        switch self {
        case .invalidURL:
            return "Invalid URL"
        case .invalidResponse:
            return "Invalid response from server"
        case .httpError(let statusCode):
            return "HTTP error: \(statusCode)"
        case .unsupportedAlgorithm(let algorithm):
            return "Unsupported algorithm: \(algorithm)"
        case .invalidCertificateChain:
            return "Invalid certificate chain"
        case .noCertificatesFound:
            return "No certificates found in chain"
        case .invalidSignature:
            return "Invalid signature format"
        case .signerDeallocated:
            return "WebServiceSigner was deallocated"
        }
    }
}

// MARK: - Convenience Extensions for Signer

extension Signer {
    /// Convenience initializer for async signing operations
    public convenience init(
        algorithm: SigningAlgorithm,
        certificateChainPEM: String,
        tsaURL: String? = nil,
        asyncSigner: @escaping @Sendable (Data) async throws -> Data
    ) throws {
        try self.init(
            algorithm: algorithm,
            certificateChainPEM: certificateChainPEM,
            tsaURL: tsaURL
        ) { data in
            // Thread-safe result container
            final class ResultBox: @unchecked Sendable {
                private let lock = NSLock()
                private var _result: Result<Data, Error>?

                func setResult(_ result: Result<Data, Error>) {
                    lock.lock()
                    defer { lock.unlock() }
                    _result = result
                }

                func getResult() -> Result<Data, Error>? {
                    lock.lock()
                    defer { lock.unlock() }
                    return _result
                }
            }

            let resultBox = ResultBox()
            let semaphore = DispatchSemaphore(value: 0)

            // Use a global queue to avoid main queue dependencies
            DispatchQueue.global().async {
                Task {
                    do {
                        let signature = try await asyncSigner(data)
                        resultBox.setResult(.success(signature))
                    } catch {
                        resultBox.setResult(.failure(error))
                    }
                    semaphore.signal()
                }
            }

            semaphore.wait()

            switch resultBox.getResult() {
            case .success(let signature):
                return signature
            case .failure(let error):
                throw error
            case .none:
                throw C2PAError.api("Async signing operation failed")
            }
        }
    }
}
