import C2PA
import Foundation
import XCTest

/// Core C2PA library functionality tests
public final class C2PACoreTests: XCTestCase {
    
    // MARK: - Test Properties
    
    private var testImageURL: URL {
        // Try to find test image in bundle
        if let url = Bundle(for: type(of: self)).url(forResource: "adobe-20220124-CI", withExtension: "jpg") {
            return url
        }
        // Fallback to creating test data
        return createTestImageFile()
    }
    
    private func createTestImageFile() -> URL {
        let tempDir = FileManager.default.temporaryDirectory
        let testImageURL = tempDir.appendingPathComponent("test_image_\(UUID().uuidString).jpg")
        
        // Create a simple test image data
        let testData = createTestImageData()
        try? testData.write(to: testImageURL)
        
        return testImageURL
    }
    
    private func createTestImageData() -> Data {
        // Create a minimal valid JPEG
        var jpegData = Data()
        jpegData.append(contentsOf: [0xFF, 0xD8]) // JPEG Start
        jpegData.append(contentsOf: [0xFF, 0xE0]) // APP0 marker
        jpegData.append(contentsOf: [0x00, 0x10]) // Length
        jpegData.append("JFIF".data(using: .ascii)!)
        jpegData.append(contentsOf: [0x00, 0x01, 0x01, 0x00, 0x00, 0x01, 0x00, 0x01, 0x00, 0x00])
        jpegData.append(contentsOf: [0xFF, 0xD9]) // JPEG End
        return jpegData
    }
    
    // MARK: - Core Library Tests
    
    public func testLibraryVersion() throws {
        let version = C2PAVersion
        XCTAssertFalse(version.isEmpty, "C2PA library version should not be empty")
        XCTAssertTrue(version.contains("."), "Version should be semantic (contain dots)")
        print("C2PA Library Version: \(version)")
    }
    
    public func testErrorHandling() throws {
        // Test that reading a non-existent file throws the correct error
        let nonExistentURL = URL(fileURLWithPath: "/non/existent/file.jpg")
        
        XCTAssertThrowsError(try C2PA.readFile(at: nonExistentURL)) { error in
            guard let c2paError = error as? C2PAError else {
                XCTFail("Expected C2PAError but got \(type(of: error))")
                return
            }
            
            switch c2paError {
            case .api(let message):
                XCTAssertTrue(
                    message.contains("No such file") || 
                    message.contains("does not exist") ||
                    message.contains("couldn't be opened"),
                    "Error message should indicate file not found: \(message)"
                )
            default:
                XCTFail("Expected .api error but got \(c2paError)")
            }
        }
    }
    
    public func testReadImage() throws {
        let imageURL = testImageURL
        
        // Only test if we have a valid test image with C2PA data
        guard FileManager.default.fileExists(atPath: imageURL.path) else {
            throw XCTSkip("Test image not available")
        }
        
        do {
            let manifestJSON = try C2PA.readFile(at: imageURL)
            
            if manifestJSON.isEmpty {
                // No C2PA data in image is valid
                print("Image has no C2PA manifest data")
                return
            }
            
            XCTAssertFalse(manifestJSON.isEmpty, "Manifest JSON should not be empty")
            
            // Validate JSON structure
            guard let manifestData = manifestJSON.data(using: .utf8) else {
                XCTFail("Failed to convert manifest JSON to data")
                return
            }
            
            let jsonObject = try JSONSerialization.jsonObject(with: manifestData)
            guard let manifest = jsonObject as? [String: Any] else {
                XCTFail("Manifest should be a valid JSON object")
                return
            }
            
            // Check for expected keys
            XCTAssertNotNil(manifest["active_manifest"], "Manifest should have active_manifest")
            
            if let manifests = manifest["manifests"] as? [String: Any] {
                XCTAssertFalse(manifests.isEmpty, "Manifests should not be empty")
            }
            
            print("Successfully read C2PA manifest with \(manifestJSON.count) characters")
            
        } catch let error as C2PAError {
            switch error {
            case .manifestNotFound:
                // No manifest is acceptable for test images
                print("No C2PA manifest found in test image (acceptable)")
            default:
                throw error
            }
        }
    }
    
    public func testInvalidFileHandling() throws {
        let tempDir = FileManager.default.temporaryDirectory
        let invalidFileURL = tempDir.appendingPathComponent("invalid_\(UUID().uuidString).txt")
        
        // Create an invalid (non-image) file
        let invalidData = "This is not an image".data(using: .utf8)!
        try invalidData.write(to: invalidFileURL)
        
        defer {
            try? FileManager.default.removeItem(at: invalidFileURL)
        }
        
        XCTAssertThrowsError(try C2PA.readFile(at: invalidFileURL)) { error in
            guard let c2paError = error as? C2PAError else {
                XCTFail("Expected C2PAError but got \(type(of: error))")
                return
            }
            
            // Should fail because it's not a valid image format
            print("Got expected error for invalid file: \(c2paError)")
        }
    }
    
    public func testResourceReading() throws {
        // Test reading from bundle resources
        guard let resourceURL = Bundle(for: type(of: self)).url(forResource: "test-manifest", withExtension: "json") else {
            throw XCTSkip("Test manifest resource not available")
        }
        
        let data = try Data(contentsOf: resourceURL)
        XCTAssertFalse(data.isEmpty, "Resource data should not be empty")
        
        // Validate it's valid JSON
        let json = try JSONSerialization.jsonObject(with: data)
        XCTAssertNotNil(json, "Resource should be valid JSON")
    }
    
    public func testErrorEnumCoverage() throws {
        // Test various C2PAError cases
        let errors: [C2PAError] = [
            .api("Test API error"),
            .manifestNotFound,
            .invalidArgument("Test argument"),
            .unsupported("Test feature"),
            .notFound,
            .libraryError("Test library error")
        ]
        
        for error in errors {
            XCTAssertFalse(error.description.isEmpty, "Error should have description: \(error)")
            
            // Test error equality if available
            switch error {
            case .api(let message):
                XCTAssertEqual(message, "Test API error")
            case .invalidArgument(let arg):
                XCTAssertEqual(arg, "Test argument")
            case .unsupported(let feature):
                XCTAssertEqual(feature, "Test feature")
            case .libraryError(let message):
                XCTAssertEqual(message, "Test library error")
            default:
                break
            }
        }
    }
}