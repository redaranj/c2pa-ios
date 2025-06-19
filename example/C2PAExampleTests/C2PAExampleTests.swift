import C2PA
@testable import C2PAExample
import XCTest

final class C2PATests: XCTestCase {
    
    // MARK: - Core Library Tests
    
    func testLibraryVersion() async throws {
        let result = await TestEngine.shared.runLibraryVersionTest()
        XCTAssertTrue(result.success, result.message)
    }
    
    func testErrorHandling() async throws {
        let result = await TestEngine.shared.runErrorHandlingTest()
        XCTAssertTrue(result.success, result.message)
    }
    
    func testReadImage() async throws {
        let result = await TestEngine.shared.runReadImageTest()
        XCTAssertTrue(result.success, result.message)
    }
    
    func testStreamAPI() async throws {
        let result = await TestEngine.shared.runStreamAPITest()
        XCTAssertTrue(result.success, result.message)
    }
    
    func testBuilderAPI() async throws {
        let result = await TestEngine.shared.runBuilderAPITest()
        XCTAssertTrue(result.success, result.message)
    }
    
    func testBuilderNoEmbed() async throws {
        let result = await TestEngine.shared.runBuilderNoEmbedTest()
        XCTAssertTrue(result.success, result.message)
    }
    
    func testReadIngredient() async throws {
        let result = await TestEngine.shared.runReadIngredientTest()
        XCTAssertTrue(result.success, result.message)
    }
    
    func testInvalidFileHandling() async throws {
        let result = await TestEngine.shared.runInvalidFileHandlingTest()
        XCTAssertTrue(result.success, result.message)
    }
    
    func testResourceReading() async throws {
        let result = await TestEngine.shared.runResourceReadingTest()
        XCTAssertTrue(result.success, result.message)
    }
    
    func testBuilderRemoteURL() async throws {
        let result = await TestEngine.shared.runBuilderRemoteURLTest()
        XCTAssertTrue(result.success, result.message)
    }
    
    func testBuilderAddResource() async throws {
        let result = await TestEngine.shared.runBuilderAddResourceTest()
        XCTAssertTrue(result.success, result.message)
    }
    
    func testBuilderAddIngredient() async throws {
        let result = await TestEngine.shared.runBuilderAddIngredientTest()
        XCTAssertTrue(result.success, result.message)
    }
    
    func testBuilderFromArchive() async throws {
        let result = await TestEngine.shared.runBuilderFromArchiveTest()
        XCTAssertTrue(result.success, result.message)
    }
    
    func testReaderWithManifestData() async throws {
        let result = await TestEngine.shared.runReaderWithManifestDataTest()
        XCTAssertTrue(result.success, result.message)
    }
    
    func testSignerWithCallback() async throws {
        let result = await TestEngine.shared.runSignerWithCallbackTest()
        XCTAssertTrue(result.success, result.message)
    }
    
    func testFileOperationsWithDataDir() async throws {
        let result = await TestEngine.shared.runFileOperationsWithDataDirTest()
        XCTAssertTrue(result.success, result.message)
    }
    
    func testWriteOnlyStreams() async throws {
        let result = await TestEngine.shared.runWriteOnlyStreamsTest()
        XCTAssertTrue(result.success, result.message)
    }
    
    func testCustomStreamCallbacks() async throws {
        let result = await TestEngine.shared.runCustomStreamCallbacksTest()
        XCTAssertTrue(result.success, result.message)
    }
    
    func testStreamFileOptions() async throws {
        let result = await TestEngine.shared.runStreamFileOptionsTest()
        XCTAssertTrue(result.success, result.message)
    }
    
    // MARK: - Signing Tests
    
    func testWebServiceSignerCreation() async throws {
        let result = await TestEngine.shared.runWebServiceSignerCreationTest()
        XCTAssertTrue(result.success, result.message)
    }
    
    func testKeychainSignerCreation() async throws {
        let result = await TestEngine.shared.runKeychainSignerCreationTest()
        XCTAssertTrue(result.success, result.message)
    }
    
    @available(iOS 13.0, macOS 10.15, *)
    func testSecureEnclaveSignerCreation() async throws {
        let result = await TestEngine.shared.runSecureEnclaveSignerCreationTest()
        XCTAssertTrue(result.success, result.message)
    }
    
    func testSigningAlgorithmTests() async throws {
        let result = await TestEngine.shared.runSigningAlgorithmTests()
        XCTAssertTrue(result.success, result.message)
    }
    
    func testSignerReserveSize() async throws {
        let result = await TestEngine.shared.runSignerReserveSizeTest()
        XCTAssertTrue(result.success, result.message)
    }
    
    func testReaderResourceErrorHandling() async throws {
        let result = await TestEngine.shared.runReaderResourceErrorHandlingTest()
        XCTAssertTrue(result.success, result.message)
    }
    
    func testErrorEnumCoverage() async throws {
        let result = await TestEngine.shared.runErrorEnumCoverageTest()
        XCTAssertTrue(result.success, result.message)
    }

}
