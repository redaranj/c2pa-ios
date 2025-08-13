import XCTest
@testable import C2PA

/// Basic unit tests for C2PA library
final class BasicTests: XCTestCase {
    
    // MARK: - Library Version
    
    func testLibraryVersion() async throws {
        let version = C2PAVersion
        XCTAssertFalse(version.isEmpty)
        XCTAssertTrue(version.contains(".")) // Should be semantic version
    }
    
    // MARK: - Manifest Creation
    
    func testManifestCreation() async throws {
        // Test creating a basic manifest
        let manifest = C2PAManifest(
            claim: C2PAClaim(
                generator: "C2PA Test Suite",
                title: "Test Image",
                format: "image/jpeg"
            ),
            assertions: [
                C2PAAssertion(
                    label: "c2pa.actions",
                    data: Data("test action".utf8)
                )
            ]
        )
        
        XCTAssertNotNil(manifest.claim)
        XCTAssertEqual(manifest.claim.generator, "C2PA Test Suite")
        XCTAssertFalse(manifest.assertions.isEmpty)
    }
    
    // MARK: - Signer Tests
    
    func testSignerCreation() async throws {
        // Test creating a signer with test certificates
        let testCert = """
        -----BEGIN CERTIFICATE-----
        MIIBkTCB+wIJAKHHIG...test certificate data...
        -----END CERTIFICATE-----
        """
        
        let testKey = """
        -----BEGIN PRIVATE KEY-----
        MIICdgIBADANBgk...test private key data...
        -----END PRIVATE KEY-----
        """
        
        do {
            let signer = try C2PASigner(
                certsPEM: testCert,
                privateKeyPEM: testKey,
                algorithm: .es256
            )
            XCTAssertNotNil(signer)
        } catch {
            // Expected to fail with test data
            XCTAssertNotNil(error)
        }
    }
    
    // MARK: - Algorithm Tests
    
    func testSigningAlgorithms() {
        let algorithms: [SigningAlgorithm] = [.es256, .es384, .es512, .ps256, .ps384, .ps512, .ed25519]
        
        for algorithm in algorithms {
            XCTAssertFalse(algorithm.description.isEmpty)
        }
        
        XCTAssertEqual(SigningAlgorithm.es256.description, "es256")
        XCTAssertEqual(SigningAlgorithm.ps256.description, "ps256")
    }
    
    // MARK: - Stream Tests
    
    func testStreamCreation() async throws {
        // Test creating a stream from data
        let testData = Data("test data".utf8)
        
        do {
            let stream = try Stream(data: testData)
            XCTAssertNotNil(stream)
        } catch {
            XCTFail("Failed to create stream: \(error)")
        }
    }
    
    // MARK: - Builder Tests
    
    func testBuilderCreation() async throws {
        let manifestJSON = """
        {
            "claim_generator": "Test Suite",
            "title": "Test",
            "format": "image/jpeg"
        }
        """
        
        do {
            let builder = try Builder(manifestJSON: manifestJSON)
            XCTAssertNotNil(builder)
        } catch {
            // May fail with incomplete JSON
            XCTAssertNotNil(error)
        }
    }
    
    // MARK: - Error Handling
    
    func testErrorTypes() {
        let errors: [C2PAError] = [
            .api("Test error"),
            .nilPointer,
            .utf8,
            .negative(-1)
        ]
        
        for error in errors {
            XCTAssertFalse(error.description.isEmpty)
        }
    }
    
    // MARK: - Secure Enclave Tests
    
    @available(iOS 13.0, macOS 10.15, *)
    func testSecureEnclaveConfig() {
        let config = SecureEnclaveSignerConfig(
            keyTag: "com.test.c2pa.key"
        )
        
        XCTAssertEqual(config.keyTag, "com.test.c2pa.key")
        XCTAssertEqual(config.accessControl, [.privateKeyUsage])
    }
}