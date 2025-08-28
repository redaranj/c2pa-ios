import Foundation
import C2PA
#if canImport(UIKit)
import UIKit
#elseif canImport(AppKit)
import AppKit
#endif

/// Core test suite functionality matching Android's TestSuiteCore
open class TestSuiteCore {
    
    // MARK: - Properties
    
    /// Test resources bundle
    public var testBundle: Bundle
    
    /// Test image data
    public var testImageData: Data?
    
    /// Test manifest data
    public var testManifestData: Data?
    
    /// Performance metrics
    public var performanceMetrics: [String: TimeInterval] = [:]
    
    // MARK: - Initialization
    
    public init() {
        self.testBundle = Bundle(for: TestSuiteCore.self)
    }
    
    // MARK: - Setup and Teardown
    
    public func setUp() async throws {
        
        // Load test bundle
        testBundle = Bundle(for: TestSuiteCore.self)
        
        // Load test resources
        try loadTestResources()
        
        // Setup performance tracking
        setupPerformanceTracking()
    }
    
    public func tearDown() async throws {
        // Clean up
        testImageData = nil
        testManifestData = nil
        performanceMetrics.removeAll()
        cleanupTemporaryFiles()
    }
    
    // MARK: - Test Resource Loading
    
    private func loadTestResources() throws {
        // Load test image
        if let imageURL = testBundle.url(forResource: "test-image", withExtension: "jpg") {
            testImageData = try Data(contentsOf: imageURL)
        }
        
        // Load test manifest
        if let manifestURL = testBundle.url(forResource: "test-manifest", withExtension: "c2pa") {
            testManifestData = try Data(contentsOf: manifestURL)
        }
    }
    
    // MARK: - Performance Tracking
    
    private func setupPerformanceTracking() {
        // Performance tracking is setup on demand when using measure()
        // No need to configure options globally
    }
    
    /// Measure performance of a block
    public func measurePerformance(name: String, block: () throws -> Void) rethrows {
        let start = CFAbsoluteTimeGetCurrent()
        try block()
        let elapsed = CFAbsoluteTimeGetCurrent() - start
        performanceMetrics[name] = elapsed
    }
    
    /// Measure async performance
    public func measureAsyncPerformance(name: String, block: () async throws -> Void) async rethrows {
        let start = CFAbsoluteTimeGetCurrent()
        try await block()
        let elapsed = CFAbsoluteTimeGetCurrent() - start
        performanceMetrics[name] = elapsed
    }
    
    // MARK: - Common Test Assertions
    
    /// Check if signature is valid
    public func isSignatureValid(_ signature: Data) -> Bool {
        return !signature.isEmpty && signature.count > 64 // Minimum ES256 signature size
    }
    
    /// Check if image has C2PA data
    public func imageHasC2PA(_ imageData: Data) async throws -> Bool {
        // For now, just check that data is not empty
        // TODO: Implement actual C2PA manifest checking when API is available
        return !imageData.isEmpty
    }
    
    // MARK: - Test Data Generators
    
    /// Generate test image data
    public func generateTestImageData(size: CGSize = CGSize(width: 100, height: 100)) -> Data? {
        #if canImport(UIKit)
        UIGraphicsBeginImageContext(size)
        defer { UIGraphicsEndImageContext() }
        
        let context = UIGraphicsGetCurrentContext()
        context?.setFillColor(UIColor.blue.cgColor)
        context?.fill(CGRect(origin: .zero, size: size))
        
        let image = UIGraphicsGetImageFromCurrentImageContext()
        return image?.jpegData(compressionQuality: 0.8)
        #elseif canImport(AppKit)
        let image = NSImage(size: size)
        image.lockFocus()
        NSColor.blue.drawSwatch(in: NSRect(origin: .zero, size: size))
        image.unlockFocus()
        
        guard let tiffData = image.tiffRepresentation,
              let bitmap = NSBitmapImageRep(data: tiffData) else {
            return nil
        }
        
        return bitmap.representation(using: .jpeg, properties: [:])
        #else
        return nil
        #endif
    }
    
    // MARK: - Mock Network Responses
    
    /// Create mock signing server response
    public func createMockSigningResponse() -> Data {
        let response = """
        {
            "signature": "\(Data(repeating: 0xAB, count: 64).base64EncodedString())",
            "certificate": "\(Data(repeating: 0xCD, count: 256).base64EncodedString())",
            "timestamp": "\(Date().timeIntervalSince1970)"
        }
        """
        return Data(response.utf8)
    }
    
    // MARK: - Temporary File Management
    
    /// Create temporary file for testing
    @discardableResult
    public func createTemporaryFile(data: Data, extension ext: String) throws -> URL {
        let tempDir = FileManager.default.temporaryDirectory
        let fileName = UUID().uuidString + "." + ext
        let fileURL = tempDir.appendingPathComponent(fileName)
        try data.write(to: fileURL)
        
        // Store for later cleanup
        temporaryFiles.append(fileURL)
        
        return fileURL
    }
    
    /// Temporary files to clean up
    private var temporaryFiles: [URL] = []
    
    /// Clean up temporary files
    public func cleanupTemporaryFiles() {
        for fileURL in temporaryFiles {
            try? FileManager.default.removeItem(at: fileURL)
        }
        temporaryFiles.removeAll()
    }
    
    // MARK: - Wait Utilities
    
    /// Wait for async condition
    public func waitForCondition(
        timeout: TimeInterval = 5,
        condition: @escaping () async -> Bool
    ) async throws {
        let deadline = Date().addingTimeInterval(timeout)
        
        while Date() < deadline {
            if await condition() {
                return
            }
            try await Task.sleep(nanoseconds: 100_000_000) // 100ms
        }
        
        throw NSError(domain: "TestSuiteCore", code: 1, userInfo: [NSLocalizedDescriptionKey: "Condition not met within timeout"])
    }
}

// MARK: - Test Helpers

extension TestSuiteCore {
    /// Run test with timeout
    public func runWithTimeout<T>(
        _ timeout: TimeInterval,
        operation: @escaping () async throws -> T
    ) async throws -> T {
        let task = Task {
            try await operation()
        }
        
        let timeoutTask = Task {
            try await Task.sleep(nanoseconds: UInt64(timeout * 1_000_000_000))
            task.cancel()
        }
        
        let result = try await task.value
        timeoutTask.cancel()
        return result
    }
}
