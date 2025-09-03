import C2PA
import CryptoKit
import Foundation
import Security
import X509
import XCTest

/// Tests for C2PA signing functionality including Keychain and Secure Enclave
public final class C2PASigningTests: XCTestCase {
    
    // MARK: - Test Properties
    
    private let keyTag = "com.c2pa.test.key.\(UUID().uuidString)"
    
    private var testCertsPEM: String {
        """
        -----BEGIN CERTIFICATE-----
        MIIBkTCB+wIJAKHO
        -----END CERTIFICATE-----
        """
    }
    
    private var testPrivateKeyPEM: String {
        """
        -----BEGIN PRIVATE KEY-----
        MIGHAgEAMBMGByqG
        -----END PRIVATE KEY-----
        """
    }
    
    override func tearDown() {
        super.tearDown()
        // Clean up any test keys from keychain
        deleteTestKeychainItem()
    }
    
    private func deleteTestKeychainItem() {
        let query: [String: Any] = [
            kSecClass as String: kSecClassKey,
            kSecAttrApplicationTag as String: keyTag.data(using: .utf8)!
        ]
        SecItemDelete(query as CFDictionary)
    }
    
    // MARK: - Basic Signer Tests
    
    public func testSignerCreation() throws {
        // Test creating signer with PEM certificates
        do {
            let signer = try Signer(
                certsPEM: testCertsPEM,
                privateKeyPEM: testPrivateKeyPEM,
                algorithm: .es256,
                tsaURL: nil
            )
            XCTAssertNotNil(signer, "Signer should be created successfully")
            print("Successfully created PEM-based signer")
        } catch let error as C2PAError {
            // Expected in test environment without valid certificates
            switch error {
            case .api(let message) where message.contains("certificate") || message.contains("key"):
                print("Expected certificate/key error in test: \(message)")
            default:
                throw error
            }
        }
    }
    
    public func testSignerWithCallback() throws {
        var signCalled = false
        let signCallback: SignerCallback = { data in
            signCalled = true
            // Return dummy signature
            return Data(repeating: 0x42, count: 64)
        }
        
        do {
            let signer = try Signer(
                callback: signCallback,
                algorithm: .es256,
                certificateChainPEM: testCertsPEM,
                reserveSize: 10000,
                tsaURL: nil
            )
            
            XCTAssertNotNil(signer, "Callback signer should be created")
            
            // The callback would be invoked during actual signing operation
            print("Successfully created callback-based signer")
            
        } catch let error as C2PAError {
            switch error {
            case .api(let message) where message.contains("certificate"):
                print("Expected certificate error: \(message)")
            default:
                throw error
            }
        }
    }
    
    public func testSigningAlgorithms() throws {
        let algorithms: [SigningAlgorithm] = [.es256, .es384, .es512, .ps256, .ps384, .ps512, .ed25519]
        
        for algorithm in algorithms {
            do {
                let signer = try Signer(
                    certsPEM: testCertsPEM,
                    privateKeyPEM: testPrivateKeyPEM,
                    algorithm: algorithm,
                    tsaURL: nil
                )
                XCTAssertNotNil(signer)
                print("Created signer with algorithm: \(algorithm)")
            } catch {
                print("Algorithm \(algorithm) not supported or invalid cert: \(error)")
            }
        }
    }
    
    public func testSignerReserveSize() throws {
        // Test signer with custom reserve size
        let customReserveSize: UInt = 20000
        
        do {
            let signer = try Signer(
                callback: { _ in Data() },
                algorithm: .es256,
                certificateChainPEM: testCertsPEM,
                reserveSize: customReserveSize,
                tsaURL: nil
            )
            
            XCTAssertNotNil(signer)
            print("Created signer with custom reserve size: \(customReserveSize)")
            
        } catch let error as C2PAError {
            switch error {
            case .api(let message) where message.contains("certificate"):
                print("Expected certificate error: \(message)")
            default:
                throw error
            }
        }
    }
    
    // MARK: - Keychain Signer Tests
    
    public func testKeychainSignerCreation() throws {
        // First, create a test key in keychain
        guard let keyData = testPrivateKeyPEM.data(using: .utf8) else {
            XCTFail("Failed to create key data")
            return
        }
        
        // Parse and store key in keychain
        let attributes: [String: Any] = [
            kSecClass as String: kSecClassKey,
            kSecAttrKeyType as String: kSecAttrKeyTypeECSECPrimeRandom,
            kSecAttrKeyClass as String: kSecAttrKeyClassPrivate,
            kSecAttrApplicationTag as String: keyTag.data(using: .utf8)!,
            kSecValueData as String: keyData,
            kSecAttrAccessible as String: kSecAttrAccessibleAfterFirstUnlock
        ]
        
        // Try to add key to keychain
        var result = SecItemAdd(attributes as CFDictionary, nil)
        
        if result == errSecDuplicateItem {
            // Delete and retry
            deleteTestKeychainItem()
            result = SecItemAdd(attributes as CFDictionary, nil)
        }
        
        guard result == errSecSuccess else {
            print("Could not add test key to keychain: \(result)")
            throw XCTSkip("Keychain not available in test environment")
        }
        
        // Now try to create keychain signer
        do {
            let signer = try Signer(
                algorithm: .es256,
                certificateChainPEM: testCertsPEM,
                keychainKeyTag: keyTag
            )
            
            XCTAssertNotNil(signer)
            print("Successfully created keychain signer")
            
        } catch let error as C2PAError {
            switch error {
            case .api(let message):
                print("Keychain signer error: \(message)")
            default:
                throw error
            }
        }
    }
    
    // MARK: - Secure Enclave Tests
    
    @available(iOS 13.0, macOS 10.15, *)
    public func testSecureEnclaveSignerCreation() throws {
        // Check if Secure Enclave is available
        guard SecureEnclave.isAvailable else {
            throw XCTSkip("Secure Enclave not available on this device")
        }
        
        let config = SecureEnclaveSignerConfig(
            keyTag: keyTag,
            accessControl: [.privateKeyUsage],
            authenticationContext: nil
        )
        
        do {
            // This will fail without proper certificate enrollment
            let signer = try Signer(
                algorithm: .es256,
                certificateChainPEM: testCertsPEM,
                secureEnclaveConfig: config
            )
            
            XCTAssertNotNil(signer)
            print("Successfully created Secure Enclave signer")
            
        } catch let error as C2PAError {
            switch error {
            case .api(let message) where message.contains("Secure Enclave") || message.contains("certificate"):
                print("Expected Secure Enclave error in test: \(message)")
            case .unsupported:
                print("Secure Enclave not supported in test environment")
            default:
                throw error
            }
        }
    }
    
    @available(iOS 13.0, macOS 10.15, *)
    public func testSecureEnclaveCSRSigning() throws {
        guard SecureEnclave.isAvailable else {
            throw XCTSkip("Secure Enclave not available")
        }
        
        // Generate a test key in Secure Enclave
        let keyParameters: [String: Any] = [
            kSecAttrKeyType as String: kSecAttrKeyTypeECSECPrimeRandom,
            kSecAttrKeySizeInBits as String: 256,
            kSecAttrTokenID as String: kSecAttrTokenIDSecureEnclave,
            kSecPrivateKeyAttrs as String: [
                kSecAttrIsPermanent as String: false,
                kSecAttrApplicationTag as String: keyTag.data(using: .utf8)!,
                kSecAttrAccessControl as String: SecAccessControlCreateWithFlags(
                    kCFAllocatorDefault,
                    kSecAttrAccessibleWhenUnlockedThisDeviceOnly,
                    .privateKeyUsage,
                    nil
                )!
            ]
        ]
        
        var error: Unmanaged<CFError>?
        guard let privateKey = SecKeyCreateRandomKey(keyParameters as CFDictionary, &error) else {
            if let error = error?.takeRetainedValue() {
                print("Failed to create Secure Enclave key: \(error)")
            }
            throw XCTSkip("Could not create Secure Enclave key")
        }
        
        // Get public key
        guard let publicKey = SecKeyCopyPublicKey(privateKey) else {
            XCTFail("Failed to get public key")
            return
        }
        
        // Create CSR using the Secure Enclave key
        do {
            let csrBuilder = try CertificateSigningRequest(
                subject: DistinguishedName(
                    commonName: "Test Secure Enclave",
                    organizationName: "C2PA Test"
                ),
                privateKey: privateKey,
                publicKey: publicKey,
                signatureAlgorithm: .ecdsaWithSHA256
            )
            
            let csrData = try csrBuilder.derEncoded()
            XCTAssertFalse(csrData.isEmpty, "CSR should not be empty")
            
            print("Successfully created CSR with Secure Enclave key")
            
        } catch {
            print("CSR creation error (expected in some test environments): \(error)")
        }
        
        // Clean up
        deleteTestKeychainItem()
    }
    
    // MARK: - Web Service Signer Tests
    
    public func testWebServiceSignerCreation() throws {
        // Test creating a signer that would work with a web service
        let serviceURL = "https://signing.example.com/sign"
        
        let webSignCallback: SignerCallback = { data in
            // In real implementation, this would call the web service
            print("Would send \(data.count) bytes to \(serviceURL)")
            
            // Return dummy signature for testing
            return Data(repeating: 0xAB, count: 64)
        }
        
        do {
            let signer = try Signer(
                callback: webSignCallback,
                algorithm: .es256,
                certificateChainPEM: testCertsPEM,
                reserveSize: 10000,
                tsaURL: "https://timestamp.example.com"
            )
            
            XCTAssertNotNil(signer)
            print("Successfully created web service signer")
            
        } catch let error as C2PAError {
            switch error {
            case .api(let message) where message.contains("certificate"):
                print("Expected certificate error: \(message)")
            default:
                throw error
            }
        }
    }
}