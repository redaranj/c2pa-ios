import C2PA
import Foundation
import XCTest

/// Tests for C2PA Stream API functionality
public final class C2PAStreamTests: XCTestCase {
    
    // MARK: - Helper Methods
    
    private func createTestFile() -> URL {
        let tempDir = FileManager.default.temporaryDirectory
        let fileURL = tempDir.appendingPathComponent("test_\(UUID().uuidString).dat")
        let testData = "Test data".data(using: .utf8)!
        try? testData.write(to: fileURL)
        return fileURL
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
    
    // MARK: - Stream API Tests
    
    public func testStreamAPI() throws {
        let tempDir = FileManager.default.temporaryDirectory
        let fileURL = tempDir.appendingPathComponent("stream_test_\(UUID().uuidString).dat")
        
        defer {
            try? FileManager.default.removeItem(at: fileURL)
        }
        
        // Test creating a new file stream
        let stream = try Stream(fileURL: fileURL, truncate: true, createIfNeeded: true)
        XCTAssertNotNil(stream, "Stream should be created successfully")
        
        // Write some data
        let testData = "Hello, Stream API!".data(using: .utf8)!
        try stream.write(testData)
        
        // Verify file exists
        XCTAssertTrue(FileManager.default.fileExists(atPath: fileURL.path), "File should exist after writing")
        
        // Read back the data
        let readData = try Data(contentsOf: fileURL)
        XCTAssertEqual(readData, testData, "Written data should match read data")
    }
    
    public func testWriteOnlyStreams() throws {
        let tempDir = FileManager.default.temporaryDirectory
        let fileURL = tempDir.appendingPathComponent("write_only_\(UUID().uuidString).dat")
        
        defer {
            try? FileManager.default.removeItem(at: fileURL)
        }
        
        // Create write-only stream
        let stream = try Stream(fileURL: fileURL, truncate: true, createIfNeeded: true)
        
        // Write data multiple times
        let chunk1 = "First chunk".data(using: .utf8)!
        let chunk2 = "Second chunk".data(using: .utf8)!
        
        try stream.write(chunk1)
        try stream.write(chunk2)
        
        // Verify combined data
        let finalData = try Data(contentsOf: fileURL)
        let expectedData = chunk1 + chunk2
        XCTAssertEqual(finalData, expectedData, "Multiple writes should append data")
    }
    
    public func testCustomStreamCallbacks() throws {
        var readCalled = false
        var writeCalled = false
        var seekCalled = false
        var flushCalled = false
        
        // Create custom stream with callbacks
        let customStream = try Stream(
            readCallback: { buffer, count in
                readCalled = true
                return 0
            },
            writeCallback: { buffer, count in
                writeCalled = true
                return count
            },
            seekCallback: { offset in
                seekCalled = true
                return offset
            },
            flushCallback: {
                flushCalled = true
            }
        )
        
        XCTAssertNotNil(customStream, "Custom stream should be created")
        
        // Test write callback
        let testData = "Test".data(using: .utf8)!
        try customStream.write(testData)
        XCTAssertTrue(writeCalled, "Write callback should be called")
        
        // Test seek callback if available
        try? customStream.seek(to: 0)
        
        // Test flush callback
        try? customStream.flush()
        
        print("Custom stream callbacks tested")
    }
    
    public func testStreamFileOptions() throws {
        let tempDir = FileManager.default.temporaryDirectory
        
        // Test 1: Create new file with truncate
        let newFileURL = tempDir.appendingPathComponent("new_file_\(UUID().uuidString).dat")
        defer { try? FileManager.default.removeItem(at: newFileURL) }
        
        let newStream = try Stream(fileURL: newFileURL, truncate: true, createIfNeeded: true)
        XCTAssertNotNil(newStream)
        XCTAssertTrue(FileManager.default.fileExists(atPath: newFileURL.path))
        
        // Test 2: Open existing file without truncate
        let existingFileURL = tempDir.appendingPathComponent("existing_\(UUID().uuidString).dat")
        let initialData = "Initial content".data(using: .utf8)!
        try initialData.write(to: existingFileURL)
        defer { try? FileManager.default.removeItem(at: existingFileURL) }
        
        let existingStream = try Stream(fileURL: existingFileURL, truncate: false, createIfNeeded: false)
        XCTAssertNotNil(existingStream)
        
        // Verify content wasn't truncated
        let readData = try Data(contentsOf: existingFileURL)
        XCTAssertEqual(readData, initialData, "Existing content should be preserved")
        
        // Test 3: Error when file doesn't exist and createIfNeeded is false
        let nonExistentURL = tempDir.appendingPathComponent("nonexistent_\(UUID().uuidString).dat")
        
        XCTAssertThrowsError(try Stream(fileURL: nonExistentURL, truncate: false, createIfNeeded: false)) { error in
            print("Got expected error for non-existent file: \(error)")
        }
    }
    
    public func testFileOperationsWithDataDir() throws {
        // Test operations with specific data directory
        let dataDir = FileManager.default.temporaryDirectory.appendingPathComponent("test_data_\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: dataDir, withIntermediateDirectories: true)
        
        defer {
            try? FileManager.default.removeItem(at: dataDir)
        }
        
        // Create multiple files in data directory
        let file1 = dataDir.appendingPathComponent("file1.dat")
        let file2 = dataDir.appendingPathComponent("file2.dat")
        
        let stream1 = try Stream(fileURL: file1, truncate: true, createIfNeeded: true)
        let stream2 = try Stream(fileURL: file2, truncate: true, createIfNeeded: true)
        
        // Write to both streams
        try stream1.write("Data 1".data(using: .utf8)!)
        try stream2.write("Data 2".data(using: .utf8)!)
        
        // Verify both files exist in data directory
        let contents = try FileManager.default.contentsOfDirectory(at: dataDir, includingPropertiesForKeys: nil)
        XCTAssertEqual(contents.count, 2, "Should have two files in data directory")
        
        print("Successfully tested file operations with data directory")
    }
    
    public func testReaderWithManifestData() throws {
        // Test reading manifest data from a stream
        let tempDir = FileManager.default.temporaryDirectory
        let fileURL = tempDir.appendingPathComponent("manifest_\(UUID().uuidString).jpg")
        
        defer {
            try? FileManager.default.removeItem(at: fileURL)
        }
        
        // Create test image with potential manifest
        let imageData = createTestImageData()
        try imageData.write(to: fileURL)
        
        do {
            // Try to read as C2PA
            let reader = try Reader(fileURL: fileURL)
            let manifestJSON = try reader.getManifestJSON()
            
            if !manifestJSON.isEmpty {
                // Parse and validate manifest
                let data = manifestJSON.data(using: .utf8)!
                let manifest = try JSONSerialization.jsonObject(with: data) as? [String: Any]
                XCTAssertNotNil(manifest, "Manifest should be valid JSON")
                print("Successfully read manifest data")
            } else {
                print("No manifest data in test file")
            }
            
        } catch let error as C2PAError {
            switch error {
            case .manifestNotFound:
                print("No manifest found (expected for test image)")
            default:
                throw error
            }
        }
    }
}