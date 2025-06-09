import XCTest
import C2PA
@testable import C2PAExample

final class C2PATests: XCTestCase {
    
    override func setUpWithError() throws {
        // Put setup code here. This method is called before the invocation of each test method in the class.
    }

    override func tearDownWithError() throws {
        // Put teardown code here. This method is called after the invocation of each test method in the class.
    }

    func testLibraryVersion() throws {
        let version = C2PAVersion
        XCTAssertFalse(version.isEmpty, "C2PA version should not be empty")
        XCTAssertTrue(version.contains("."), "Version should contain a dot separator")
        print("C2PA Version: \(version)")
    }
    
    func testErrorHandling() throws {
        XCTAssertThrowsError(try C2PA.readFile(at: URL(fileURLWithPath: "/non/existent/file.jpg"))) { error in
            XCTAssertTrue(error is C2PAError, "Should throw C2PAError")
            if let c2paError = error as? C2PAError {
                print("Expected error: \(c2paError.description)")
            }
        }
    }
    
    func testReadManifestFromTestImage() throws {
        guard let imageURL = Bundle.main.url(forResource: "adobe-20220124-CI", withExtension: "jpg") else {
            XCTFail("Could not find test image in bundle")
            return
        }
        
        let manifestJSON = try C2PA.readFile(at: imageURL)
        XCTAssertFalse(manifestJSON.isEmpty, "Manifest should not be empty")
        
        // Verify it's valid JSON
        let jsonData = manifestJSON.data(using: .utf8)!
        let jsonObject = try JSONSerialization.jsonObject(with: jsonData, options: [])
        XCTAssertNotNil(jsonObject, "Manifest should be valid JSON")
        
        print("Manifest size: \(manifestJSON.count) bytes")
    }
    
    func testStreamAPI() throws {
        guard let imageURL = Bundle.main.url(forResource: "adobe-20220124-CI", withExtension: "jpg") else {
            XCTFail("Could not find test image")
            return
        }
        
        let data = try Data(contentsOf: imageURL)
        let stream = try Stream(data: data)
        let reader = try Reader(format: "image/jpeg", stream: stream)
        let manifestJSON = try reader.json()
        
        XCTAssertFalse(manifestJSON.isEmpty, "Manifest from stream should not be empty")
        XCTAssertEqual(manifestJSON.first, "{", "Manifest should start with {")
    }
    
    func testBuilderCreation() throws {
        let manifestJSON = """
        {
            "claim_generator": "C2PATests/1.0",
            "title": "Test Manifest",
            "assertions": [
                {
                    "label": "c2pa.actions",
                    "data": {
                        "actions": []
                    }
                }
            ]
        }
        """
        
        let builder = try Builder(manifestJSON: manifestJSON)
        builder.setNoEmbed()
        
        // Test writing to archive
        let tempURL = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString + ".c2pa")
        defer { try? FileManager.default.removeItem(at: tempURL) }
        
        let archiveStream = try Stream(fileURL: tempURL)
        try builder.writeArchive(to: archiveStream)
        
        let fileExists = FileManager.default.fileExists(atPath: tempURL.path)
        XCTAssertTrue(fileExists, "Archive file should be created")
        
        let fileSize = try FileManager.default.attributesOfItem(atPath: tempURL.path)[.size] as? Int64 ?? 0
        XCTAssertGreaterThan(fileSize, 0, "Archive should have content")
    }
    
    func testFileStreamReadWrite() throws {
        let tempURL = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString + ".txt")
        defer { try? FileManager.default.removeItem(at: tempURL) }
        
        let testData = "Hello, C2PA!"
        
        // Write data
        let writeStream = try Stream(fileURL: tempURL, truncate: true, createIfNeeded: true)
        testData.withCString { ptr in
            _ = writeStream.rawPtr.pointee.write_fn?(
                writeStream.rawPtr.pointee.context,
                ptr,
                testData.count
            )
        }
        
        // Read data back
        let readData = try Data(contentsOf: tempURL)
        let readString = String(data: readData, encoding: .utf8)
        
        XCTAssertEqual(readString, testData, "Written data should match read data")
    }
    
    func testReadIngredient() throws {
        guard let imageURL = Bundle.main.url(forResource: "adobe-20220124-CI", withExtension: "jpg") else {
            XCTFail("Could not find test image")
            return
        }
        
        do {
            let ingredientJSON = try C2PA.readIngredient(at: imageURL)
            XCTAssertFalse(ingredientJSON.isEmpty, "Ingredient should not be empty if present")
        } catch {
            // It's OK if this fails - not all images have ingredient data
            if let c2paError = error as? C2PAError {
                print("No ingredient data (expected): \(c2paError.description)")
            } else {
                throw error
            }
        }
    }
    
    func testInvalidFileFormat() throws {
        let tempURL = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString + ".txt")
        defer { try? FileManager.default.removeItem(at: tempURL) }
        
        try "This is not a valid image file".write(to: tempURL, atomically: true, encoding: .utf8)
        
        XCTAssertThrowsError(try C2PA.readFile(at: tempURL)) { error in
            XCTAssertTrue(error is C2PAError, "Should throw C2PAError for invalid format")
        }
    }
    
    func testSignerInfoCreation() throws {
        let signerInfo = SignerInfo(
            algorithm: .es256,
            certificatePEM: "-----BEGIN CERTIFICATE-----\ntest\n-----END CERTIFICATE-----",
            privateKeyPEM: "-----BEGIN PRIVATE KEY-----\ntest\n-----END PRIVATE KEY-----",
            tsaURL: "https://timestamp.example.com"
        )
        
        XCTAssertEqual(signerInfo.algorithm.description, "es256")
        XCTAssertNotNil(signerInfo.tsaURL)
    }
    
    func testPerformanceReadManifest() throws {
        guard let imageURL = Bundle.main.url(forResource: "adobe-20220124-CI", withExtension: "jpg") else {
            XCTFail("Could not find test image")
            return
        }
        
        self.measure {
            do {
                _ = try C2PA.readFile(at: imageURL)
            } catch {
                XCTFail("Performance test failed: \(error)")
            }
        }
    }
}

// MARK: - Test Helpers
extension C2PATests {
    
    func createTestManifest() -> String {
        return """
        {
            "claim_generator": "C2PATests/1.0",
            "title": "Test Image",
            "assertions": [
                {
                    "label": "c2pa.actions",
                    "data": {
                        "actions": [
                            {
                                "action": "c2pa.created"
                            }
                        ]
                    }
                }
            ]
        }
        """
    }
    
    func verifyManifestStructure(_ manifestJSON: String) throws {
        let data = manifestJSON.data(using: .utf8)!
        let json = try JSONSerialization.jsonObject(with: data, options: [])
        
        guard let dict = json as? [String: Any] else {
            XCTFail("Manifest should be a dictionary")
            return
        }
        
        // Check for common C2PA manifest fields
        if let manifests = dict["manifests"] as? [Any] {
            XCTAssertGreaterThan(manifests.count, 0, "Should have at least one manifest")
        }
        
        if let validationStatus = dict["validation_status"] as? [[String: Any]] {
            for status in validationStatus {
                if let code = status["code"] as? String {
                    print("Validation status: \(code)")
                }
            }
        }
    }
}