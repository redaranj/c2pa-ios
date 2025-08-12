import Foundation
import C2PA
import CryptoKit
import Security

/// Test helper for signing operations, matching Android's SigningHelper
public class SigningHelper {
    
    /// Shared instance for test convenience
    public static let shared = SigningHelper()
    
    /// Test certificate data
    public let testCertificate: Data
    
    /// Test private key
    public let testPrivateKey: SecKey?
    
    public init() {
        // Load test certificate from resources
        if let certURL = Bundle.module.url(forResource: "es256_certs", withExtension: "pem"),
           let certData = try? Data(contentsOf: certURL) {
            self.testCertificate = certData
        } else {
            self.testCertificate = Data()
        }
        
        // Load test private key
        if let keyURL = Bundle.module.url(forResource: "es256_private", withExtension: "key"),
           let keyData = try? Data(contentsOf: keyURL) {
            self.testPrivateKey = SigningHelper.loadPrivateKey(from: keyData)
        } else {
            self.testPrivateKey = nil
        }
    }
    
    /// Create a test signer for unit tests
    public func createTestSigner() -> C2PASigner {
        return MockSigner(
            certificate: testCertificate,
            privateKey: testPrivateKey
        )
    }
    
    /// Create a hardware signer mock for testing
    public func createHardwareSignerMock() -> C2PASigner {
        return MockHardwareSigner()
    }
    
    /// Helper to sign data with test key
    public func signData(_ data: Data) throws -> Data {
        guard let privateKey = testPrivateKey else {
            throw SigningError.noPrivateKey
        }
        
        guard let signature = SecKeyCreateSignature(
            privateKey,
            .ecdsaSignatureMessageX962SHA256,
            data as CFData,
            nil
        ) else {
            throw SigningError.signingFailed
        }
        
        return signature as Data
    }
    
    private static func loadPrivateKey(from data: Data) -> SecKey? {
        let keyDict: [String: Any] = [
            kSecAttrKeyType as String: kSecAttrKeyTypeECSECPrimeRandom,
            kSecAttrKeyClass as String: kSecAttrKeyClassPrivate,
            kSecAttrKeySizeInBits as String: 256
        ]
        
        return SecKeyCreateWithData(data as CFData, keyDict as CFDictionary, nil)
    }
}

public enum SigningError: Error {
    case noPrivateKey
    case signingFailed
    case invalidCertificate
}

// MARK: - Mock Implementations

/// Mock signer for testing
public class MockSigner: C2PASigner {
    let certificate: Data
    let privateKey: SecKey?
    
    init(certificate: Data, privateKey: SecKey?) {
        self.certificate = certificate
        self.privateKey = privateKey
    }
    
    public func sign(data: Data) async throws -> Data {
        guard let privateKey = privateKey else {
            throw SigningError.noPrivateKey
        }
        
        guard let signature = SecKeyCreateSignature(
            privateKey,
            .ecdsaSignatureMessageX962SHA256,
            data as CFData,
            nil
        ) else {
            throw SigningError.signingFailed
        }
        
        return signature as Data
    }
    
    public func getCertificateChain() async throws -> Data {
        return certificate
    }
    
    public func getAlgorithm() -> String {
        return "es256"
    }
}

/// Mock hardware signer for testing Secure Enclave functionality
public class MockHardwareSigner: C2PASigner {
    private let tag = "com.c2pa.test.hardware.key"
    
    public func sign(data: Data) async throws -> Data {
        // Simulate hardware signing delay
        try await Task.sleep(nanoseconds: 100_000_000) // 100ms
        
        // Return mock signature
        return Data(repeating: 0xAB, count: 64)
    }
    
    public func getCertificateChain() async throws -> Data {
        // Return mock certificate
        return Data([0x30, 0x82]) // DER sequence start
    }
    
    public func getAlgorithm() -> String {
        return "es256"
    }
}