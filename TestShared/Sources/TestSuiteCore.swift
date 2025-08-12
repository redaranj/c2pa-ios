import XCTest
import C2PA

/// Core test suite functionality matching Android's TestSuiteCore
open class TestSuiteCore: XCTestCase {
    
    // MARK: - Properties
    
    /// Shared C2PA instance for testing
    public var c2pa: C2PA!
    
    /// Test resources bundle
    public var testBundle: Bundle!
    
    /// Test image data
    public var testImageData: Data!
    
    /// Test manifest data
    public var testManifestData: Data!
    
    /// Performance metrics
    public var performanceMetrics: [String: TimeInterval] = [:]
    
    // MARK: - Setup and Teardown
    
    open override func setUp() async throws {
        try await super.setUp()
        
        // Initialize C2PA
        c2pa = C2PA()
        
        // Load test bundle
        testBundle = Bundle.module
        
        // Load test resources
        try loadTestResources()
        
        // Setup performance tracking
        setupPerformanceTracking()
    }
    
    open override func tearDown() async throws {
        // Clean up
        c2pa = nil
        testImageData = nil
        testManifestData = nil
        performanceMetrics.removeAll()
        
        try await super.tearDown()
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
        // Configure XCTest performance metrics
        if #available(iOS 16.0, macOS 13.0, *) {
            self.measureOptions = XCTMeasureOptions()
            self.measureOptions.invocationOptions = [.manuallyStart, .manuallyStop]
            self.measureOptions.iterationCount = 5
        }
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
    
    /// Assert manifest is valid
    public func assertManifestValid(_ manifest: C2PAManifest) {
        XCTAssertNotNil(manifest.claim)
        XCTAssertFalse(manifest.assertions.isEmpty)
        XCTAssertNotNil(manifest.signature)
    }
    
    /// Assert signature is valid
    public func assertSignatureValid(_ signature: Data) {
        XCTAssertFalse(signature.isEmpty)
        XCTAssertGreaterThan(signature.count, 64) // Minimum ES256 signature size
    }
    
    /// Assert image has C2PA data
    public func assertImageHasC2PA(_ imageData: Data) async throws {
        let hasManifest = try await c2pa.hasManifest(data: imageData)
        XCTAssertTrue(hasManifest)
    }
    
    // MARK: - Test Data Generators
    
    /// Generate test manifest
    public func generateTestManifest() -> C2PAManifest {
        return C2PAManifest(
            claim: C2PAClaim(
                generator: "C2PA iOS Test Suite",
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
    }
    
    /// Generate test image data
    public func generateTestImageData(size: CGSize = CGSize(width: 100, height: 100)) -> Data? {
        #if canImport(UIKit)
        import UIKit
        
        UIGraphicsBeginImageContext(size)
        defer { UIGraphicsEndImageContext() }
        
        let context = UIGraphicsGetCurrentContext()
        context?.setFillColor(UIColor.blue.cgColor)
        context?.fill(CGRect(origin: .zero, size: size))
        
        let image = UIGraphicsGetImageFromCurrentImageContext()
        return image?.jpegData(compressionQuality: 0.8)
        #elseif canImport(AppKit)
        import AppKit
        
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
        
        // Register for cleanup
        addTeardownBlock {
            try? FileManager.default.removeItem(at: fileURL)
        }
        
        return fileURL
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
        
        XCTFail("Condition not met within timeout")
    }
}

// MARK: - XCTest Extensions

extension XCTestCase {
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