import XCTest
import C2PA
import TestShared

/// Basic unit tests for C2PA library
final class BasicTests: TestSuiteCore {
    
    // MARK: - Library Version
    
    func testLibraryVersion() async throws {
        let version = c2pa.getVersion()
        XCTAssertFalse(version.isEmpty)
        XCTAssertTrue(version.contains(".")) // Should be semantic version
    }
    
    // MARK: - Manifest Detection
    
    func testHasManifest() async throws {
        // Test with unsigned image
        guard let imageData = generateTestImageData() else {
            XCTFail("Failed to generate test image")
            return
        }
        
        let hasManifest = try await c2pa.hasManifest(data: imageData)
        XCTAssertFalse(hasManifest, "Unsigned image should not have manifest")
    }
    
    func testHasManifestWithSignedImage() async throws {
        // Create and sign image
        guard let imageData = generateTestImageData() else {
            XCTFail("Failed to generate test image")
            return
        }
        
        let manifest = generateTestManifest()
        let signer = SigningHelper.shared.createTestSigner()
        
        let signedData = try await c2pa.sign(
            data: imageData,
            manifest: manifest,
            signer: signer
        )
        
        let hasManifest = try await c2pa.hasManifest(data: signedData)
        XCTAssertTrue(hasManifest, "Signed image should have manifest")
    }
    
    // MARK: - Manifest Creation
    
    func testCreateBasicManifest() throws {
        let manifest = C2PAManifest(
            claim: C2PAClaim(
                generator: "C2PA iOS Test",
                title: "Test Image",
                format: "image/jpeg"
            ),
            assertions: []
        )
        
        XCTAssertNotNil(manifest)
        XCTAssertEqual(manifest.claim.generator, "C2PA iOS Test")
        XCTAssertEqual(manifest.claim.title, "Test Image")
        XCTAssertEqual(manifest.claim.format, "image/jpeg")
    }
    
    func testCreateManifestWithAssertions() throws {
        let manifest = C2PAManifest(
            claim: C2PAClaim(
                generator: "C2PA iOS Test",
                title: "Test Image",
                format: "image/jpeg"
            ),
            assertions: [
                C2PAAssertion(
                    label: "c2pa.actions",
                    data: Data("{\"actions\":[{\"action\":\"c2pa.edited\"}]}".utf8)
                ),
                C2PAAssertion(
                    label: "c2pa.hash.data",
                    data: Data([0x01, 0x02, 0x03, 0x04])
                )
            ]
        )
        
        XCTAssertEqual(manifest.assertions.count, 2)
        XCTAssertEqual(manifest.assertions[0].label, "c2pa.actions")
        XCTAssertEqual(manifest.assertions[1].label, "c2pa.hash.data")
    }
    
    // MARK: - Signing Tests
    
    func testBasicSigning() async throws {
        guard let imageData = generateTestImageData() else {
            XCTFail("Failed to generate test image")
            return
        }
        
        let manifest = generateTestManifest()
        let signer = SigningHelper.shared.createTestSigner()
        
        let signedData = try await c2pa.sign(
            data: imageData,
            manifest: manifest,
            signer: signer
        )
        
        XCTAssertGreaterThan(signedData.count, imageData.count, "Signed data should be larger")
        try await assertImageHasC2PA(signedData)
    }
    
    func testSigningWithMetadata() async throws {
        guard let imageData = generateTestImageData() else {
            XCTFail("Failed to generate test image")
            return
        }
        
        let manifest = C2PAManifest(
            claim: C2PAClaim(
                generator: "C2PA iOS Test",
                title: "Test Image with Metadata",
                format: "image/jpeg",
                instanceID: UUID().uuidString,
                metadata: [
                    "author": "Test Author",
                    "copyright": "© 2024 Test"
                ]
            ),
            assertions: []
        )
        
        let signer = SigningHelper.shared.createTestSigner()
        
        let signedData = try await c2pa.sign(
            data: imageData,
            manifest: manifest,
            signer: signer
        )
        
        try await assertImageHasC2PA(signedData)
    }
    
    // MARK: - Manifest Extraction
    
    func testExtractManifest() async throws {
        // Sign an image first
        guard let imageData = generateTestImageData() else {
            XCTFail("Failed to generate test image")
            return
        }
        
        let originalManifest = generateTestManifest()
        let signer = SigningHelper.shared.createTestSigner()
        
        let signedData = try await c2pa.sign(
            data: imageData,
            manifest: originalManifest,
            signer: signer
        )
        
        // Extract manifest
        let extractedManifest = try await c2pa.extractManifest(from: signedData)
        
        assertManifestValid(extractedManifest)
        XCTAssertEqual(extractedManifest.claim.generator, originalManifest.claim.generator)
    }
    
    // MARK: - Validation Tests
    
    func testValidateSignedImage() async throws {
        guard let imageData = generateTestImageData() else {
            XCTFail("Failed to generate test image")
            return
        }
        
        let manifest = generateTestManifest()
        let signer = SigningHelper.shared.createTestSigner()
        
        let signedData = try await c2pa.sign(
            data: imageData,
            manifest: manifest,
            signer: signer
        )
        
        let validationResult = try await c2pa.validate(data: signedData)
        XCTAssertTrue(validationResult.isValid)
        XCTAssertNil(validationResult.error)
    }
    
    // MARK: - Error Handling
    
    func testInvalidDataHandling() async throws {
        let invalidData = Data("Not an image".utf8)
        
        do {
            _ = try await c2pa.hasManifest(data: invalidData)
            XCTFail("Should throw error for invalid data")
        } catch {
            // Expected error
            XCTAssertNotNil(error)
        }
    }
    
    func testEmptyDataHandling() async throws {
        let emptyData = Data()
        
        do {
            _ = try await c2pa.hasManifest(data: emptyData)
            XCTFail("Should throw error for empty data")
        } catch {
            // Expected error
            XCTAssertNotNil(error)
        }
    }
    
    // MARK: - Resource Tests
    
    func testLoadTestResources() throws {
        // Test loading PEM certificate
        let certURL = testBundle.url(forResource: "es256_certs", withExtension: "pem")
        XCTAssertNotNil(certURL, "Test certificate should exist")
        
        // Test loading private key
        let keyURL = testBundle.url(forResource: "es256_private", withExtension: "key")
        XCTAssertNotNil(keyURL, "Test private key should exist")
        
        // Test loading test images
        let imageURL = testBundle.url(forResource: "adobe-20220124-CI", withExtension: "jpg")
        XCTAssertNotNil(imageURL, "Test image should exist")
    }
    
    // MARK: - Stream API Tests
    
    func testStreamReading() async throws {
        // Create test file
        guard let imageData = generateTestImageData() else {
            XCTFail("Failed to generate test image")
            return
        }
        
        let tempURL = try createTemporaryFile(data: imageData, extension: "jpg")
        
        // Test stream reading
        let hasManifest = try await c2pa.hasManifest(url: tempURL)
        XCTAssertFalse(hasManifest)
    }
    
    func testStreamWriting() async throws {
        guard let imageData = generateTestImageData() else {
            XCTFail("Failed to generate test image")
            return
        }
        
        let manifest = generateTestManifest()
        let signer = SigningHelper.shared.createTestSigner()
        
        let inputURL = try createTemporaryFile(data: imageData, extension: "jpg")
        let outputURL = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString)
            .appendingPathExtension("jpg")
        
        // Sign to file
        try await c2pa.sign(
            inputURL: inputURL,
            outputURL: outputURL,
            manifest: manifest,
            signer: signer
        )
        
        // Verify output file exists and has manifest
        XCTAssertTrue(FileManager.default.fileExists(atPath: outputURL.path))
        
        let hasManifest = try await c2pa.hasManifest(url: outputURL)
        XCTAssertTrue(hasManifest)
        
        // Cleanup
        try? FileManager.default.removeItem(at: outputURL)
    }
}