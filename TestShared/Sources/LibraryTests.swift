import XCTest
@testable import C2PA
import TestShared

/// Main test suite for C2PA library using TestShared functionality
final class LibraryTests: XCTestCase {
    
    // MARK: - Run All Test Suites
    
    func testCoreLibraryFunctionality() throws {
        let coreTests = C2PACoreTests()
        
        try coreTests.testLibraryVersion()
        try coreTests.testErrorHandling()
        try coreTests.testReadImage()
        try coreTests.testInvalidFileHandling()
        try coreTests.testResourceReading()
        try coreTests.testErrorEnumCoverage()
    }
    
    func testBuilderAPI() throws {
        let builderTests = C2PABuilderTests()
        
        try builderTests.testBuilderAPI()
        try builderTests.testBuilderNoEmbed()
        try builderTests.testBuilderAddResource()
        try builderTests.testBuilderAddIngredient()
        try builderTests.testBuilderFromArchive()
        try builderTests.testBuilderRemoteURL()
        try builderTests.testReadIngredient()
    }
    
    func testStreamAPI() throws {
        let streamTests = C2PAStreamTests()
        
        try streamTests.testStreamAPI()
        try streamTests.testWriteOnlyStreams()
        try streamTests.testCustomStreamCallbacks()
        try streamTests.testStreamFileOptions()
        try streamTests.testFileOperationsWithDataDir()
        try streamTests.testReaderWithManifestData()
    }
    
    func testSigningFunctionality() throws {
        let signingTests = C2PASigningTests()
        
        try signingTests.testSignerCreation()
        try signingTests.testSignerWithCallback()
        try signingTests.testSigningAlgorithms()
        try signingTests.testSignerReserveSize()
        try signingTests.testKeychainSignerCreation()
        try signingTests.testWebServiceSignerCreation()
        
        if #available(iOS 13.0, macOS 10.15, *) {
            try signingTests.testSecureEnclaveSignerCreation()
            try signingTests.testSecureEnclaveCSRSigning()
        }
    }
    
    func testReaderFunctionality() throws {
        let readerTests = C2PAReaderTests()
        
        try readerTests.testReaderResourceErrorHandling()
        try readerTests.testReaderWithManifestData()
        try readerTests.testResourceReading()
        try readerTests.testReaderValidation()
        try readerTests.testReaderThumbnailExtraction()
        try readerTests.testReaderIngredientExtraction()
    }
    
    private var testCore: TestSuiteCore!
    private var signingHelper: SigningHelper!
    
    override func setUp() {
        super.setUp()
        testCore = TestSuiteCore()
        signingHelper = SigningHelper()
        
        Task {
            try await testCore.setUp()
        }
    }
    
    override func tearDown() {
        Task {
            try await testCore.tearDown()
        }
        super.tearDown()
    }
    
    // MARK: - Version Tests
    
    func testLibraryVersion() {
        let version = C2PAVersion
        XCTAssertFalse(version.isEmpty, "Version should not be empty")
        XCTAssertTrue(version.contains("."), "Version should be semantic")
    }
    
    // MARK: - Signing Tests
    
    func testCreateSigner() throws {
        let signer = signingHelper.createTestSigner()
        XCTAssertNotNil(signer)
        
        // Test signer can be created with test certificate
        let cert = try signingHelper.generateTestCertificate(
            commonName: "Test User",
            organizationName: "Test Org"
        )
        XCTAssertFalse(cert.isEmpty)
    }
    
    func testSignerWithMockData() async throws {
        guard let imageData = testCore.generateTestImageData() else {
            XCTFail("Failed to generate test image")
            return
        }
        
        XCTAssertFalse(imageData.isEmpty)
        XCTAssertGreaterThan(imageData.count, 100)
    }
    
    // MARK: - Performance Tests
    
    func testPerformanceOfImageDataCreation() {
        testCore.measurePerformance(name: "image_data_creation") {
            _ = testCore.generateTestImageData()
        }
        
        if let time = testCore.performanceMetrics["image_data_creation"] {
            XCTAssertLessThan(time, 1.0, "Image data creation should be fast")
        }
    }
    
    // MARK: - Integration Tests
    
    func testFullSigningFlow() async throws {
        // Generate test data
        guard let imageData = testCore.generateTestImageData(
            size: CGSize(width: 200, height: 200)
        ) else {
            XCTFail("Failed to generate test image")
            return
        }
        
        // Create signer
        _ = signingHelper.createTestSigner()
        
        // Create temp file for testing
        let tempFile = try testCore.createTemporaryFile(
            data: imageData,
            extension: "jpg"
        )
        
        // Verify file was created
        XCTAssertTrue(FileManager.default.fileExists(atPath: tempFile.path))
        
        // Clean up will happen automatically
    }
    
    // MARK: - Certificate Tests
    
    func testCertificateGeneration() throws {
        let cert = try signingHelper.generateTestCertificate(
            commonName: "Test Suite",
            organizationName: "C2PA Tests"
        )
        
        XCTAssertFalse(cert.isEmpty)
        // Convert Data to String for comparison
        if let certString = String(data: cert, encoding: .utf8) {
            XCTAssertTrue(certString.contains("BEGIN CERTIFICATE"))
            XCTAssertTrue(certString.contains("END CERTIFICATE"))
        } else {
            XCTFail("Failed to convert certificate data to string")
        }
    }
    
    func testCSRGeneration() throws {
        let csr = try signingHelper.createTestCSR(
            commonName: "Test CSR",
            organizationName: "C2PA Tests"
        )
        
        XCTAssertFalse(csr.isEmpty)
        // Convert Data to String for comparison
        if let csrString = String(data: csr, encoding: .utf8) {
            XCTAssertTrue(csrString.contains("BEGIN CERTIFICATE REQUEST"))
            XCTAssertTrue(csrString.contains("END CERTIFICATE REQUEST"))
        } else {
            XCTFail("Failed to convert CSR data to string")
        }
    }
    
    // MARK: - Mock Response Tests
    
    func testMockSigningResponse() {
        let mockResponse = testCore.createMockSigningResponse()
        
        XCTAssertFalse(mockResponse.isEmpty)
        
        // Should be valid JSON
        let json = try? JSONSerialization.jsonObject(
            with: mockResponse,
            options: []
        ) as? [String: Any]
        
        XCTAssertNotNil(json)
        XCTAssertNotNil(json?["signature"])
        XCTAssertNotNil(json?["certificate"])
        XCTAssertNotNil(json?["timestamp"])
    }
    
    // MARK: - Async Tests
    
    func testAsyncWaitCondition() async throws {
        var conditionMet = false
        
        // Set condition after delay
        Task {
            try await Task.sleep(nanoseconds: 100_000_000) // 100ms
            conditionMet = true
        }
        
        // Wait for condition
        try await testCore.waitForCondition(timeout: 1.0) {
            conditionMet
        }
        
        XCTAssertTrue(conditionMet)
    }
    
    func testRunWithTimeout() async throws {
        let result = try await testCore.runWithTimeout(1.0) {
            try await Task.sleep(nanoseconds: 50_000_000) // 50ms
            return "completed"
        }
        
        XCTAssertEqual(result, "completed")
    }
}