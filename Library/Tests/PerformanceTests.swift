import XCTest
import C2PA
import TestShared

/// Performance tests for C2PA operations
final class PerformanceTests: TestSuiteCore {
    
    // Test data sizes
    let smallImageSize = CGSize(width: 640, height: 480)
    let mediumImageSize = CGSize(width: 1920, height: 1080)
    let largeImageSize = CGSize(width: 4096, height: 3072)
    
    override func setUp() async throws {
        try await super.setUp()
    }
    
    func testSigningPerformanceSmallImage() throws {
        guard let imageData = generateTestImageData(size: smallImageSize) else {
            XCTFail("Failed to generate test image")
            return
        }
        
        let manifest = generateTestManifest()
        let signer = SigningHelper.shared.createTestSigner()
        
        measure {
            Task {
                _ = try await c2pa.sign(
                    data: imageData,
                    manifest: manifest,
                    signer: signer
                )
            }
        }
    }
    
    func testSigningPerformanceMediumImage() throws {
        guard let imageData = generateTestImageData(size: mediumImageSize) else {
            XCTFail("Failed to generate test image")
            return
        }
        
        let manifest = generateTestManifest()
        let signer = SigningHelper.shared.createTestSigner()
        
        measure {
            Task {
                _ = try await c2pa.sign(
                    data: imageData,
                    manifest: manifest,
                    signer: signer
                )
            }
        }
    }
    
    func testSigningPerformanceLargeImage() throws {
        guard let imageData = generateTestImageData(size: largeImageSize) else {
            XCTFail("Failed to generate test image")
            return
        }
        
        let manifest = generateTestManifest()
        let signer = SigningHelper.shared.createTestSigner()
        
        measure {
            Task {
                _ = try await c2pa.sign(
                    data: imageData,
                    manifest: manifest,
                    signer: signer
                )
            }
        }
    }
    
    func testManifestExtractionPerformance() async throws {
        // Prepare signed image
        guard let imageData = generateTestImageData(size: mediumImageSize) else {
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
        
        // Measure extraction performance
        measure {
            Task {
                _ = try await c2pa.extractManifest(from: signedData)
            }
        }
    }
    
    func testValidationPerformance() async throws {
        // Prepare signed image
        guard let imageData = generateTestImageData(size: mediumImageSize) else {
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
        
        // Measure validation performance
        measure {
            Task {
                _ = try await c2pa.validate(data: signedData)
            }
        }
    }
    
    func testMemoryUsageForLargeManifest() async throws {
        guard let imageData = generateTestImageData(size: largeImageSize) else {
            XCTFail("Failed to generate test image")
            return
        }
        
        // Create large manifest with many assertions
        var manifest = generateTestManifest()
        for i in 0..<100 {
            manifest.assertions.append(
                C2PAAssertion(
                    label: "c2pa.test.\(i)",
                    data: Data(repeating: UInt8(i), count: 1024)
                )
            )
        }
        
        let signer = SigningHelper.shared.createTestSigner()
        
        // Monitor memory usage
        let initialMemory = getMemoryUsage()
        
        _ = try await c2pa.sign(
            data: imageData,
            manifest: manifest,
            signer: signer
        )
        
        let finalMemory = getMemoryUsage()
        let memoryIncrease = finalMemory - initialMemory
        
        // Assert reasonable memory usage (< 100MB increase)
        XCTAssertLessThan(memoryIncrease, 100_000_000, "Memory usage exceeded 100MB")
    }
    
    func testConcurrentOperations() async throws {
        let signer = SigningHelper.shared.createTestSigner()
        let manifest = generateTestManifest()
        
        // Create multiple images
        var images: [Data] = []
        for i in 0..<5 {
            guard let imageData = generateTestImageData(
                size: CGSize(width: 640 + i * 100, height: 480 + i * 100)
            ) else {
                XCTFail("Failed to generate test image \(i)")
                return
            }
            images.append(imageData)
        }
        
        // Measure concurrent signing
        measure {
            Task {
                await withTaskGroup(of: Data?.self) { group in
                    for imageData in images {
                        group.addTask {
                            try? await self.c2pa.sign(
                                data: imageData,
                                manifest: manifest,
                                signer: signer
                            )
                        }
                    }
                    
                    // Collect results
                    for await _ in group {
                        // Process result
                    }
                }
            }
        }
    }
    
    // MARK: - Helpers
    
    private func getMemoryUsage() -> Int64 {
        var info = mach_task_basic_info()
        var count = mach_msg_type_number_t(MemoryLayout<mach_task_basic_info>.size) / 4
        
        let result = withUnsafeMutablePointer(to: &info) {
            $0.withMemoryRebound(to: integer_t.self, capacity: Int(count)) {
                task_info(mach_task_self_,
                         task_flavor_t(MACH_TASK_BASIC_INFO),
                         $0,
                         &count)
            }
        }
        
        return result == KERN_SUCCESS ? Int64(info.resident_size) : 0
    }
}