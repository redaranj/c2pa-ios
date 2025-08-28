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
        let bundle = Bundle(for: SigningHelper.self)
        
        // Load test certificate from resources
        if let certURL = bundle.url(forResource: "es256_certs", withExtension: "pem"),
           let certData = try? Data(contentsOf: certURL) {
            self.testCertificate = certData
        } else {
            self.testCertificate = Data()
        }
        
        // Load test private key
        if let keyURL = bundle.url(forResource: "es256_private", withExtension: "key"),
           let keyData = try? Data(contentsOf: keyURL) {
            self.testPrivateKey = SigningHelper.loadPrivateKey(from: keyData)
        } else {
            self.testPrivateKey = nil
        }
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
    
    /// Generate test image data
    public func generateTestImageData() -> Data? {
        // Create a simple 1x1 pixel PNG for testing
        let pngHeader = Data([0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A])
        return pngHeader
    }
    
    /// Generate a test certificate
    public func generateTestCertificate(commonName: String, organizationName: String) throws -> Data {
        // For testing, return a mock certificate
        return Data([0x30, 0x82]) // DER sequence start
    }
    
    /// Create a test CSR
    public func createTestCSR(commonName: String, organizationName: String) throws -> Data {
        // For testing, return a mock CSR
        return Data([0x30, 0x81]) // DER sequence start
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
