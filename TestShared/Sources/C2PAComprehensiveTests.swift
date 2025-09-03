import C2PA
import CryptoKit
import Foundation
import Security
import XCTest

/// Comprehensive test suite for C2PA library functionality
/// Ported from hardware-signing branch TestEngine implementation
public final class C2PAComprehensiveTests: XCTestCase {
    
    // MARK: - Core Library Tests
    
    public func testLibraryVersion() throws {
        let version = C2PAVersion
        XCTAssertFalse(version.isEmpty, "Version should not be empty")
        XCTAssertTrue(version.contains("."), "Version should be semantic")
        XCTAssertTrue(version.contains("c2pa"), "Version should contain 'c2pa'")
    }
    
    public func testErrorHandling() throws {
        // Test that reading a non-existent file throws the correct error
        XCTAssertThrowsError(try C2PA.readFile(at: URL(fileURLWithPath: "/non/existent/file.jpg"))) { error in
            guard let c2paError = error as? C2PAError else {
                XCTFail("Expected C2PAError but got \(type(of: error))")
                return
            }
            
            switch c2paError {
            case .api(let message):
                XCTAssertTrue(
                    message.contains("No such file or directory") || message.contains("does not exist"),
                    "Error message should indicate file not found: \(message)"
                )
            default:
                XCTFail("Expected .api error but got \(c2paError)")
            }
        }
    }
    
    public func testReadImage() throws {
        // Get test image from TestShared resources
        guard let bundle = Bundle(for: type(of: self)).url(forResource: "adobe-20220124-CI", withExtension: "jpg") else {
            XCTFail("Could not find test image 'adobe-20220124-CI.jpg' in bundle")
            return
        }
        
        let manifestJSON = try C2PA.readFile(at: bundle)
        XCTAssertFalse(manifestJSON.isEmpty, "Manifest JSON should not be empty")
        
        // Validate JSON structure
        let manifestData = manifestJSON.data(using: .utf8)!
        let jsonObject = try JSONSerialization.jsonObject(with: manifestData, options: []) as! [String: Any]
        
        // Check for expected fields
        var hasClaimGenerator = false
        if let manifests = jsonObject["manifests"] as? [String: Any] {
            for (_, manifest) in manifests {
                if let manifestDict = manifest as? [String: Any],
                   let _ = manifestDict["claim_generator"] as? String {
                    hasClaimGenerator = true
                    break
                }
            }
        } else if let _ = jsonObject["claim_generator"] as? String {
            hasClaimGenerator = true
        }
        
        XCTAssertTrue(hasClaimGenerator, "Manifest should contain claim_generator")
    }
    
    // MARK: - Stream API Tests
    
    public func testStreamAPI() throws {
        let testData = "Hello C2PA Stream API".data(using: .utf8)!
        
        // Test creating stream from Data
        let stream = try Stream(data: testData)
        XCTAssertNotNil(stream, "Should create stream from data")
        
        // Test file-based stream
        let tempURL = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try testData.write(to: tempURL)
        defer { try? FileManager.default.removeItem(at: tempURL) }
        
        let fileStream = try Stream(fileURL: tempURL, truncate: false)
        XCTAssertNotNil(fileStream, "Should create stream from file")
    }
    
    // MARK: - Builder API Tests
    
    public func testBuilderAPI() throws {
        let manifestJSON = """
        {
            "claim_generator": "TestSuite/1.0",
            "format": "image/jpeg",
            "title": "Test Manifest"
        }
        """
        
        let builder = try Builder(manifestJSON: manifestJSON)
        XCTAssertNotNil(builder, "Should create builder from JSON")
    }
    
    public func testBuilderNoEmbed() throws {
        let manifestJSON = """
        {
            "claim_generator": "TestSuite/1.0",
            "format": "image/jpeg"
        }
        """
        
        let builder = try Builder(manifestJSON: manifestJSON)
        builder.setNoEmbed()
        // No assertion needed, just testing that method can be called
    }
    
    public func testBuilderRemoteURL() throws {
        let manifestJSON = """
        {
            "claim_generator": "TestSuite/1.0",
            "format": "image/jpeg"
        }
        """
        
        let builder = try Builder(manifestJSON: manifestJSON)
        try builder.setRemoteURL("https://example.com/manifest")
    }
    
    // MARK: - Signer Tests
    
    public func testSignerCreation() throws {
        guard let bundle = Bundle(for: type(of: self)).url(forResource: "es256_certs", withExtension: "pem"),
              let certData = try? Data(contentsOf: bundle),
              let certsPEM = String(data: certData, encoding: .utf8) else {
            XCTFail("Could not load test certificates")
            return
        }
        
        guard let keyBundle = Bundle(for: type(of: self)).url(forResource: "es256_private", withExtension: "key"),
              let keyData = try? Data(contentsOf: keyBundle),
              let privateKeyPEM = String(data: keyData, encoding: .utf8) else {
            XCTFail("Could not load test private key")
            return
        }
        
        let signer = try Signer(
            certsPEM: certsPEM,
            privateKeyPEM: privateKeyPEM,
            algorithm: .es256
        )
        XCTAssertNotNil(signer, "Should create signer with PEM certificates")
        
        // Test reserve size
        let reserveSize = try signer.reserveSize()
        XCTAssertGreaterThan(reserveSize, 0, "Reserve size should be positive")
    }
    
    public func testSignerWithCallback() throws {
        guard let bundle = Bundle(for: type(of: self)).url(forResource: "es256_certs", withExtension: "pem"),
              let certData = try? Data(contentsOf: bundle),
              let certsPEM = String(data: certData, encoding: .utf8) else {
            XCTFail("Could not load test certificates")
            return
        }
        
        // Create signer with callback
        let signer = try Signer(
            algorithm: .es256,
            certificateChainPEM: certsPEM
        ) { dataToSign in
            // Mock signing - just return a dummy signature
            return Data(repeating: 0x42, count: 64)
        }
        
        XCTAssertNotNil(signer, "Should create callback-based signer")
    }
    
    // MARK: - Keychain Signer Tests
    
    public func testKeychainSignerCreation() throws {
        guard let bundle = Bundle(for: type(of: self)).url(forResource: "es256_certs", withExtension: "pem"),
              let certData = try? Data(contentsOf: bundle),
              let certsPEM = String(data: certData, encoding: .utf8) else {
            XCTFail("Could not load test certificates")
            return
        }
        
        let keyTag = "com.c2pa.test.keychain.\(UUID().uuidString)"
        defer {
            // Clean up keychain
            let deleteQuery: [String: Any] = [
                kSecClass as String: kSecClassKey,
                kSecAttrApplicationTag as String: keyTag
            ]
            SecItemDelete(deleteQuery as CFDictionary)
        }
        
        // Create test key in keychain
        let keyAttributes: [String: Any] = [
            kSecAttrKeyType as String: kSecAttrKeyTypeECSECPrimeRandom,
            kSecAttrKeySizeInBits as String: 256,
            kSecPrivateKeyAttrs as String: [
                kSecAttrIsPermanent as String: true,
                kSecAttrApplicationTag as String: keyTag,
                kSecAttrAccessible as String: kSecAttrAccessibleWhenUnlocked
            ]
        ]
        
        var error: Unmanaged<CFError>?
        guard let privateKey = SecKeyCreateRandomKey(keyAttributes as CFDictionary, &error) else {
            if let error = error?.takeRetainedValue() {
                XCTFail("Failed to create test key: \(error)")
            } else {
                XCTFail("Failed to create test key")
            }
            return
        }
        
        // Store the key
        let addQuery: [String: Any] = [
            kSecClass as String: kSecClassKey,
            kSecValueRef as String: privateKey,
            kSecAttrApplicationTag as String: keyTag
        ]
        SecItemAdd(addQuery as CFDictionary, nil)
        
        // Test creating signer with keychain key
        let signer = try Signer(
            algorithm: .es256,
            certificateChainPEM: certsPEM,
            keychainKeyTag: keyTag
        )
        
        XCTAssertNotNil(signer, "Should create keychain-based signer")
    }
    
    // MARK: - Secure Enclave Tests
    
    @available(iOS 13.0, macOS 10.15, *)
    public func testSecureEnclaveSignerCreation() throws {
        #if targetEnvironment(simulator)
        throw XCTSkip("Secure Enclave not available on simulator")
        #else
        
        guard let bundle = Bundle(for: type(of: self)).url(forResource: "es256_certs", withExtension: "pem"),
              let certData = try? Data(contentsOf: bundle),
              let certsPEM = String(data: certData, encoding: .utf8) else {
            XCTFail("Could not load test certificates")
            return
        }
        
        let keyTag = "com.c2pa.test.secure-enclave.\(UUID().uuidString)"
        let config = SecureEnclaveSignerConfig(
            keyTag: keyTag,
            accessControl: [.privateKeyUsage]
        )
        
        defer {
            // Clean up
            _ = Signer.deleteSecureEnclaveKey(keyTag: keyTag)
        }
        
        // Create Secure Enclave key
        let secKey = try Signer.createSecureEnclaveKey(config: config)
        XCTAssertNotNil(secKey, "Should create Secure Enclave key")
        
        // Extract public key
        guard let publicKey = SecKeyCopyPublicKey(secKey) else {
            XCTFail("Failed to extract public key from Secure Enclave")
            return
        }
        XCTAssertNotNil(publicKey, "Should extract public key")
        
        // Test creating signer with Secure Enclave
        let signer = try Signer(
            algorithm: .es256,
            certificateChainPEM: certsPEM,
            secureEnclaveConfig: config
        )
        
        XCTAssertNotNil(signer, "Should create Secure Enclave-based signer")
        
        // Test exporting public key as PEM
        let publicKeyPEM = try Signer.exportPublicKeyPEM(fromKeychainTag: keyTag)
        XCTAssertTrue(publicKeyPEM.contains("BEGIN PUBLIC KEY"), "Should export public key as PEM")
        XCTAssertTrue(publicKeyPEM.contains("END PUBLIC KEY"), "Should export public key as PEM")
        
        #endif
    }
    
    @available(iOS 13.0, macOS 10.15, *)
    public func testSecureEnclaveWithBiometrics() throws {
        #if targetEnvironment(simulator)
        throw XCTSkip("Secure Enclave not available on simulator")
        #else
        
        let keyTag = "com.c2pa.test.secure-enclave-bio.\(UUID().uuidString)"
        let config = SecureEnclaveSignerConfig(
            keyTag: keyTag,
            accessControl: [.privateKeyUsage, .biometryCurrentSet]
        )
        
        defer {
            _ = Signer.deleteSecureEnclaveKey(keyTag: keyTag)
        }
        
        // Create key with biometric protection
        let secKey = try Signer.createSecureEnclaveKey(config: config)
        XCTAssertNotNil(secKey, "Should create biometric-protected Secure Enclave key")
        
        // Verify key attributes indicate biometric protection
        guard let attributes = SecKeyCopyAttributes(secKey) as? [String: Any] else {
            XCTFail("Failed to get key attributes")
            return
        }
        
        // Check that access control is set
        XCTAssertNotNil(attributes[kSecAttrAccessControl as String], "Key should have access control")
        
        #endif
    }
    
    // MARK: - Signing Algorithm Tests
    
    public func testSigningAlgorithmDescriptions() {
        let algorithms: [SigningAlgorithm] = [.es256, .es384, .es512, .ps256, .ps384, .ps512, .ed25519]
        let expectedDescriptions = ["es256", "es384", "es512", "ps256", "ps384", "ps512", "ed25519"]
        
        for (algorithm, expected) in zip(algorithms, expectedDescriptions) {
            XCTAssertEqual(algorithm.description, expected, "Algorithm description should match")
        }
    }
    
    // MARK: - Error Enum Coverage
    
    public func testErrorEnumCoverage() {
        let apiError = C2PAError.api("Test error")
        XCTAssertEqual(apiError.description, "C2PA-API error: Test error")
        
        let nilError = C2PAError.nilPointer
        XCTAssertEqual(nilError.description, "Unexpected NULL pointer")
        
        let utf8Error = C2PAError.utf8
        XCTAssertEqual(utf8Error.description, "Invalid UTF-8 from C2PA")
        
        let negativeError = C2PAError.negative(42)
        XCTAssertEqual(negativeError.description, "C2PA negative status 42")
    }
    
    // MARK: - File Operations Tests
    
    public func testFileOperationsWithDataDir() throws {
        let tempDir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tempDir) }
        
        // Create a simple test image
        let imageData = createTestImageData()
        let sourceFile = tempDir.appendingPathComponent("source.jpg")
        let destFile = tempDir.appendingPathComponent("signed.jpg")
        let dataDir = tempDir.appendingPathComponent("data")
        
        try imageData.write(to: sourceFile)
        try FileManager.default.createDirectory(at: dataDir, withIntermediateDirectories: true)
        
        // Load test certificates and key
        guard let certBundle = Bundle(for: type(of: self)).url(forResource: "es256_certs", withExtension: "pem"),
              let certData = try? Data(contentsOf: certBundle),
              let certsPEM = String(data: certData, encoding: .utf8),
              let keyBundle = Bundle(for: type(of: self)).url(forResource: "es256_private", withExtension: "key"),
              let keyData = try? Data(contentsOf: keyBundle),
              let privateKeyPEM = String(data: keyData, encoding: .utf8) else {
            XCTFail("Could not load test certificates and key")
            return
        }
        
        let manifestJSON = """
        {
            "claim_generator": "TestSuite/1.0",
            "format": "image/jpeg",
            "title": "Test Signing"
        }
        """
        
        let signerInfo = SignerInfo(
            algorithm: .es256,
            certificatePEM: certsPEM,
            privateKeyPEM: privateKeyPEM
        )
        
        // Test signing with data directory
        XCTAssertNoThrow(
            try C2PA.signFile(
                source: sourceFile,
                destination: destFile,
                manifestJSON: manifestJSON,
                signerInfo: signerInfo,
                dataDir: dataDir
            )
        )
        
        XCTAssertTrue(FileManager.default.fileExists(atPath: destFile.path), "Signed file should exist")
    }
    
    // MARK: - Helper Methods
    
    private func createTestImageData() -> Data {
        // Create a minimal JPEG header
        var data = Data()
        
        // JPEG SOI marker
        data.append(contentsOf: [0xFF, 0xD8])
        
        // APP0 JFIF marker
        data.append(contentsOf: [0xFF, 0xE0])
        data.append(contentsOf: [0x00, 0x10]) // Length
        data.append(contentsOf: "JFIF".utf8)
        data.append(contentsOf: [0x00]) // null terminator
        data.append(contentsOf: [0x01, 0x01]) // Version
        data.append(contentsOf: [0x00]) // Units
        data.append(contentsOf: [0x00, 0x01, 0x00, 0x01]) // Density
        data.append(contentsOf: [0x00, 0x00]) // Thumbnail
        
        // SOF0 marker (baseline DCT)
        data.append(contentsOf: [0xFF, 0xC0])
        data.append(contentsOf: [0x00, 0x11]) // Length
        data.append(contentsOf: [0x08]) // Precision
        data.append(contentsOf: [0x00, 0x01, 0x00, 0x01]) // Height and width (1x1)
        data.append(contentsOf: [0x03]) // Components
        data.append(contentsOf: [0x01, 0x11, 0x00]) // Y component
        data.append(contentsOf: [0x02, 0x11, 0x01]) // Cb component
        data.append(contentsOf: [0x03, 0x11, 0x01]) // Cr component
        
        // SOS marker (start of scan)
        data.append(contentsOf: [0xFF, 0xDA])
        data.append(contentsOf: [0x00, 0x0C]) // Length
        data.append(contentsOf: [0x03]) // Components
        data.append(contentsOf: [0x01, 0x00]) // Y component
        data.append(contentsOf: [0x02, 0x01]) // Cb component
        data.append(contentsOf: [0x03, 0x01]) // Cr component
        data.append(contentsOf: [0x00, 0x3F, 0x00]) // Spectral selection
        
        // Minimal scan data
        data.append(contentsOf: [0x00, 0x00])
        
        // EOI marker
        data.append(contentsOf: [0xFF, 0xD9])
        
        return data
    }
}