import XCTest
import C2PA
import TestShared

/// Integration tests for signing operations
final class SigningIntegrationTests: TestSuiteCore {
    
    override func setUp() async throws {
        try await super.setUp()
    }
    
    func testFullSigningFlow() async throws {
        // Load test image
        guard let imageData = generateTestImageData() else {
            XCTFail("Failed to generate test image")
            return
        }
        
        // Create manifest
        let manifest = generateTestManifest()
        
        // Create signer
        let signer = SigningHelper.shared.createTestSigner()
        
        // Sign the image
        let signedData = try await c2pa.sign(
            data: imageData,
            manifest: manifest,
            signer: signer
        )
        
        // Verify the signature
        try await assertImageHasC2PA(signedData)
        
        // Extract and verify manifest
        let extractedManifest = try await c2pa.extractManifest(from: signedData)
        assertManifestValid(extractedManifest)
    }
    
    func testHardwareSigningFlow() async throws {
        // Skip if not running on device
        #if targetEnvironment(simulator)
        throw XCTSkip("Hardware signing requires physical device")
        #endif
        
        // Create hardware signer mock
        let signer = SigningHelper.shared.createHardwareSignerMock()
        
        // Generate test data
        guard let imageData = generateTestImageData() else {
            XCTFail("Failed to generate test image")
            return
        }
        
        let manifest = generateTestManifest()
        
        // Sign with hardware key
        let signedData = try await c2pa.sign(
            data: imageData,
            manifest: manifest,
            signer: signer
        )
        
        // Verify signature
        try await assertImageHasC2PA(signedData)
    }
    
    func testSigningServerIntegration() async throws {
        // Skip if server not available
        guard ProcessInfo.processInfo.environment["SIGNING_SERVER_URL"] != nil else {
            throw XCTSkip("Signing server not configured")
        }
        
        // Create server signer
        let serverURL = URL(string: ProcessInfo.processInfo.environment["SIGNING_SERVER_URL"]!)!
        let signer = RemoteSigner(serverURL: serverURL)
        
        // Generate test data
        guard let imageData = generateTestImageData() else {
            XCTFail("Failed to generate test image")
            return
        }
        
        let manifest = generateTestManifest()
        
        // Sign via server
        let signedData = try await c2pa.sign(
            data: imageData,
            manifest: manifest,
            signer: signer
        )
        
        // Verify signature
        try await assertImageHasC2PA(signedData)
    }
    
    func testBatchSigning() async throws {
        let signer = SigningHelper.shared.createTestSigner()
        let manifest = generateTestManifest()
        
        // Generate multiple images
        let imageCount = 10
        var images: [Data] = []
        
        for i in 0..<imageCount {
            guard let imageData = generateTestImageData(
                size: CGSize(width: 100 + i * 10, height: 100 + i * 10)
            ) else {
                XCTFail("Failed to generate test image \(i)")
                return
            }
            images.append(imageData)
        }
        
        // Sign all images
        await measureAsyncPerformance(name: "batch_signing") {
            for imageData in images {
                _ = try await c2pa.sign(
                    data: imageData,
                    manifest: manifest,
                    signer: signer
                )
            }
        }
        
        // Log performance metrics
        if let batchTime = performanceMetrics["batch_signing"] {
            let avgTime = batchTime / Double(imageCount)
            print("Average signing time: \(avgTime)s per image")
        }
    }
}

// MARK: - Remote Signer

class RemoteSigner: C2PASigner {
    let serverURL: URL
    
    init(serverURL: URL) {
        self.serverURL = serverURL
    }
    
    func sign(data: Data) async throws -> Data {
        var request = URLRequest(url: serverURL.appendingPathComponent("sign"))
        request.httpMethod = "POST"
        request.httpBody = data
        request.setValue("application/octet-stream", forHTTPHeaderField: "Content-Type")
        
        let (responseData, _) = try await URLSession.shared.data(for: request)
        return responseData
    }
    
    func getCertificateChain() async throws -> Data {
        let request = URLRequest(url: serverURL.appendingPathComponent("certificate"))
        let (responseData, _) = try await URLSession.shared.data(for: request)
        return responseData
    }
    
    func getAlgorithm() -> String {
        return "es256"
    }
}