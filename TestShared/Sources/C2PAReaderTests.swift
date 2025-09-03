import C2PA
import Foundation
import XCTest

/// Tests for C2PA Reader functionality and error handling
public final class C2PAReaderTests: XCTestCase {
    
    // MARK: - Helper Methods
    
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
    
    // MARK: - Reader Tests
    
    public func testReaderResourceErrorHandling() throws {
        let tempDir = FileManager.default.temporaryDirectory
        let fileURL = tempDir.appendingPathComponent("test_reader_\(UUID().uuidString).jpg")
        
        defer {
            try? FileManager.default.removeItem(at: fileURL)
        }
        
        // Write test image
        let imageData = createTestImageData()
        try imageData.write(to: fileURL)
        
        do {
            let reader = try Reader(fileURL: fileURL)
            
            // Try to get resources that might not exist
            let resourceURI = "http://example.com/nonexistent"
            
            do {
                _ = try reader.getResource(uri: resourceURI)
                print("Resource found (unexpected)")
            } catch let error as C2PAError {
                switch error {
                case .notFound:
                    print("Resource not found (expected)")
                case .api(let message):
                    print("API error getting resource: \(message)")
                default:
                    throw error
                }
            }
            
            // Try to get manifest JSON
            let manifestJSON = try reader.getManifestJSON()
            if manifestJSON.isEmpty {
                print("No manifest in test image (expected)")
            } else {
                print("Found manifest: \(manifestJSON.prefix(100))...")
            }
            
        } catch let error as C2PAError {
            switch error {
            case .manifestNotFound:
                print("No manifest found in test image (expected)")
            default:
                throw error
            }
        }
    }
    
    public func testReaderWithManifestData() throws {
        // Test reading manifest data from various sources
        let tempDir = FileManager.default.temporaryDirectory
        let fileURL = tempDir.appendingPathComponent("manifest_test_\(UUID().uuidString).jpg")
        
        defer {
            try? FileManager.default.removeItem(at: fileURL)
        }
        
        // Create test image
        let imageData = createTestImageData()
        try imageData.write(to: fileURL)
        
        do {
            // Test 1: Read from file URL
            let fileReader = try Reader(fileURL: fileURL)
            _ = try fileReader.getManifestJSON()
            print("Successfully created reader from file URL")
            
            // Test 2: Read from data
            let dataReader = try Reader(data: imageData, format: "image/jpeg")
            _ = try dataReader.getManifestJSON()
            print("Successfully created reader from data")
            
            // Test 3: Read from stream
            let stream = try Stream(fileURL: fileURL, truncate: false, createIfNeeded: false)
            let streamReader = try Reader(stream: stream, format: "image/jpeg")
            _ = try streamReader.getManifestJSON()
            print("Successfully created reader from stream")
            
        } catch let error as C2PAError {
            switch error {
            case .manifestNotFound:
                print("No manifest in test images (expected)")
            case .api(let message):
                print("API error: \(message)")
            default:
                throw error
            }
        }
    }
    
    public func testResourceReading() throws {
        // Test reading various resource types
        guard let testFile = Bundle(for: type(of: self)).url(forResource: "test-with-resources", withExtension: "jpg") else {
            throw XCTSkip("Test file with resources not available")
        }
        
        do {
            let reader = try Reader(fileURL: testFile)
            let manifestJSON = try reader.getManifestJSON()
            
            guard let data = manifestJSON.data(using: .utf8),
                  let manifest = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
                print("Could not parse manifest")
                return
            }
            
            // Check for assertions with resources
            if let assertions = manifest["assertions"] as? [[String: Any]] {
                for assertion in assertions {
                    if let uri = assertion["uri"] as? String {
                        do {
                            let resourceData = try reader.getResource(uri: uri)
                            print("Successfully read resource: \(uri) (\(resourceData.count) bytes)")
                        } catch {
                            print("Could not read resource \(uri): \(error)")
                        }
                    }
                }
            }
            
        } catch let error as C2PAError {
            switch error {
            case .manifestNotFound:
                print("No manifest in test file")
            default:
                throw error
            }
        }
    }
    
    public func testReaderValidation() throws {
        // Test validation functionality if available
        guard let testFile = Bundle(for: type(of: self)).url(forResource: "signed-image", withExtension: "jpg") else {
            throw XCTSkip("Signed test image not available")
        }
        
        do {
            let reader = try Reader(fileURL: testFile)
            
            // Try to validate the manifest
            let validationResult = try reader.validate()
            
            if let status = validationResult["validation_status"] as? [String: Any] {
                print("Validation status: \(status)")
                
                if let code = status["code"] as? String {
                    switch code {
                    case "validated":
                        print("✓ Manifest validated successfully")
                    case "otf_not_validated":
                        print("⚠️ Manifest present but not validated")
                    default:
                        print("Validation code: \(code)")
                    }
                }
            }
            
        } catch let error as C2PAError {
            switch error {
            case .manifestNotFound:
                print("No manifest to validate")
            case .unsupported:
                print("Validation not supported")
            default:
                throw error
            }
        }
    }
    
    public func testReaderThumbnailExtraction() throws {
        // Test extracting thumbnails from manifests
        guard let testFile = Bundle(for: type(of: self)).url(forResource: "image-with-thumbnail", withExtension: "jpg") else {
            throw XCTSkip("Test image with thumbnail not available")
        }
        
        do {
            let reader = try Reader(fileURL: testFile)
            let manifestJSON = try reader.getManifestJSON()
            
            guard let data = manifestJSON.data(using: .utf8),
                  let manifest = try JSONSerialization.jsonObject(with: data) as? [String: Any],
                  let activeManifest = manifest["active_manifest"] as? String,
                  let manifests = manifest["manifests"] as? [String: Any],
                  let active = manifests[activeManifest] as? [String: Any] else {
                print("Could not parse manifest structure")
                return
            }
            
            // Look for thumbnail in manifest
            if let thumbnail = active["thumbnail"] as? [String: Any],
               let format = thumbnail["format"] as? String,
               let identifier = thumbnail["identifier"] as? String {
                
                print("Found thumbnail: \(identifier) (format: \(format))")
                
                // Try to get thumbnail data
                do {
                    let thumbnailData = try reader.getResource(uri: identifier)
                    print("Successfully extracted thumbnail: \(thumbnailData.count) bytes")
                } catch {
                    print("Could not extract thumbnail: \(error)")
                }
            } else {
                print("No thumbnail in manifest")
            }
            
        } catch let error as C2PAError {
            switch error {
            case .manifestNotFound:
                print("No manifest found")
            default:
                throw error
            }
        }
    }
    
    public func testReaderIngredientExtraction() throws {
        // Test extracting ingredient information
        guard let testFile = Bundle(for: type(of: self)).url(forResource: "image-with-ingredients", withExtension: "jpg") else {
            throw XCTSkip("Test image with ingredients not available")
        }
        
        do {
            let reader = try Reader(fileURL: testFile)
            let manifestJSON = try reader.getManifestJSON()
            
            guard let data = manifestJSON.data(using: .utf8),
                  let manifest = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
                print("Could not parse manifest")
                return
            }
            
            // Look for ingredients
            if let ingredients = manifest["ingredients"] as? [[String: Any]] {
                print("Found \(ingredients.count) ingredient(s)")
                
                for (index, ingredient) in ingredients.enumerated() {
                    if let title = ingredient["title"] as? String {
                        print("Ingredient \(index + 1): \(title)")
                    }
                    
                    if let relationship = ingredient["relationship"] as? String {
                        print("  Relationship: \(relationship)")
                    }
                    
                    if let format = ingredient["format"] as? String {
                        print("  Format: \(format)")
                    }
                    
                    if let instanceID = ingredient["instance_id"] as? String {
                        print("  Instance ID: \(instanceID)")
                    }
                }
            } else {
                print("No ingredients in manifest")
            }
            
        } catch let error as C2PAError {
            switch error {
            case .manifestNotFound:
                print("No manifest found")
            default:
                throw error
            }
        }
    }
}