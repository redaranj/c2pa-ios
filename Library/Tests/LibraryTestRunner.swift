import XCTest
@testable import C2PA
import TestShared

/// XCTest wrappers for TestShared implementations
/// These allow the pure Swift test implementations to be run with Command-U in Xcode

// MARK: - Stream Tests

final class StreamTests: XCTestCase {
    private let tests = TestShared.StreamTests()
    
    func testStreamOperations() throws {
        let result = tests.testStreamOperations()
        XCTAssertTrue(result.passed, result.message)
    }
    
    func testStreamFileOperations() throws {
        let result = tests.testStreamFileOperations()
        XCTAssertTrue(result.passed, result.message)
    }
    
    func testWriteOnlyStreams() throws {
        let result = tests.testWriteOnlyStreams()
        XCTAssertTrue(result.passed, result.message)
    }
    
    func testCustomStreamCallbacks() throws {
        let result = tests.testCustomStreamCallbacks()
        XCTAssertTrue(result.passed, result.message)
    }
    
    func testStreamWithLargeData() throws {
        let result = tests.testStreamWithLargeData()
        XCTAssertTrue(result.passed, result.message)
    }
    
    func testMultipleStreams() throws {
        let result = tests.testMultipleStreams()
        XCTAssertTrue(result.passed, result.message)
    }
    
    func testFileStreamOptions() throws {
        let result = tests.testFileStreamOptions()
        XCTAssertTrue(result.passed, result.message)
    }
    
    func testStreamWithReader() throws {
        let result = tests.testStreamWithReader()
        XCTAssertTrue(result.passed, result.message)
    }
    
    func testStreamWithBuilder() throws {
        let result = tests.testStreamWithBuilder()
        XCTAssertTrue(result.passed, result.message)
    }
}

// MARK: - Builder Tests

final class BuilderTests: XCTestCase {
    private let tests = TestShared.BuilderTests()
    
    func testBuilderAPI() throws {
        let result = tests.testBuilderAPI()
        XCTAssertTrue(result.passed, result.message)
    }
    
    func testBuilderNoEmbed() throws {
        let result = tests.testBuilderNoEmbed()
        XCTAssertTrue(result.passed, result.message)
    }
    
    func testBuilderAddResource() throws {
        let result = tests.testBuilderAddResource()
        XCTAssertTrue(result.passed, result.message)
    }
    
    func testBuilderAddIngredient() throws {
        let result = tests.testBuilderAddIngredient()
        XCTAssertTrue(result.passed, result.message)
    }
    
    func testBuilderFromArchive() throws {
        let result = tests.testBuilderFromArchive()
        XCTAssertTrue(result.passed, result.message)
    }
    
    func testBuilderRemoteURL() throws {
        let result = tests.testBuilderRemoteURL()
        XCTAssertTrue(result.passed, result.message)
    }
    
    func testReadIngredient() throws {
        let result = tests.testReadIngredient()
        XCTAssertTrue(result.passed, result.message)
    }
}

// MARK: - Reader Tests

final class ReaderTests: XCTestCase {
    private let tests = TestShared.ReaderTests()
    
    func testReaderResourceErrorHandling() throws {
        let result = tests.testReaderResourceErrorHandling()
        XCTAssertTrue(result.passed, result.message)
    }
    
    func testReaderWithManifestData() throws {
        let result = tests.testReaderWithManifestData()
        XCTAssertTrue(result.passed, result.message)
    }
    
    func testResourceReading() throws {
        let result = tests.testResourceReading()
        XCTAssertTrue(result.passed, result.message)
    }
    
    func testReaderValidation() throws {
        let result = tests.testReaderValidation()
        XCTAssertTrue(result.passed, result.message)
    }
    
    func testReaderThumbnailExtraction() throws {
        let result = tests.testReaderThumbnailExtraction()
        XCTAssertTrue(result.passed, result.message)
    }
    
    func testReaderIngredientExtraction() throws {
        let result = tests.testReaderIngredientExtraction()
        XCTAssertTrue(result.passed, result.message)
    }
    
    func testReaderJSONParsing() throws {
        let result = tests.testReaderJSONParsing()
        XCTAssertTrue(result.passed, result.message)
    }
    
    func testReaderWithMultipleStreams() throws {
        let result = tests.testReaderWithMultipleStreams()
        XCTAssertTrue(result.passed, result.message)
    }
}

// MARK: - Signing Tests

final class SigningTests: XCTestCase {
    private let tests = TestShared.SigningTests()
    
    func testSignerCreation() throws {
        let result = tests.testSignerCreation()
        XCTAssertTrue(result.passed, result.message)
    }
    
    func testSignerWithCallback() throws {
        let result = tests.testSignerWithCallback()
        XCTAssertTrue(result.passed, result.message)
    }
    
    func testSigningAlgorithms() throws {
        let result = tests.testSigningAlgorithms()
        XCTAssertTrue(result.passed, result.message)
    }
    
    func testSignerReserveSize() throws {
        let result = tests.testSignerReserveSize()
        XCTAssertTrue(result.passed, result.message)
    }
    
    func testSignerWithTimestampAuthority() throws {
        let result = tests.testSignerWithTimestampAuthority()
        XCTAssertTrue(result.passed, result.message)
    }
    
    func testWebServiceSignerCreation() throws {
        let result = tests.testWebServiceSignerCreation()
        XCTAssertTrue(result.passed, result.message)
    }
    
    func testSignerMemoryManagement() throws {
        let result = tests.testSignerMemoryManagement()
        XCTAssertTrue(result.passed, result.message)
    }
    
    func testSignerWithActualSigning() throws {
        let result = tests.testSignerWithActualSigning()
        XCTAssertTrue(result.passed, result.message)
    }
    
    func testMultipleSigningAlgorithmsWithCallback() throws {
        let result = tests.testMultipleSigningAlgorithmsWithCallback()
        XCTAssertTrue(result.passed, result.message)
    }
}

// MARK: - Comprehensive Tests

final class ComprehensiveTests: XCTestCase {
    private let tests = TestShared.ComprehensiveTests()
    
    func testLibraryVersion() throws {
        let result = tests.testLibraryVersion()
        XCTAssertTrue(result.passed, result.message)
    }
    
    func testErrorHandling() throws {
        let result = tests.testErrorHandling()
        XCTAssertTrue(result.passed, result.message)
    }
    
    func testReadImageWithManifest() throws {
        let result = tests.testReadImageWithManifest()
        XCTAssertTrue(result.passed, result.message)
    }
    
    func testStreamFromData() throws {
        let result = tests.testStreamFromData()
        XCTAssertTrue(result.passed, result.message)
    }
    
    func testStreamFromFile() throws {
        let result = tests.testStreamFromFile()
        XCTAssertTrue(result.passed, result.message)
    }
    
    func testStreamWithCallbacks() throws {
        let result = tests.testStreamWithCallbacks()
        XCTAssertTrue(result.passed, result.message)
    }
    
    func testBuilderCreation() throws {
        let result = tests.testBuilderCreation()
        XCTAssertTrue(result.passed, result.message)
    }
    
    func testBuilderNoEmbed() throws {
        let result = tests.testBuilderNoEmbed()
        XCTAssertTrue(result.passed, result.message)
    }
    
    func testBuilderRemoteURL() throws {
        let result = tests.testBuilderRemoteURL()
        XCTAssertTrue(result.passed, result.message)
    }
    
    func testBuilderAddResource() throws {
        let result = tests.testBuilderAddResource()
        XCTAssertTrue(result.passed, result.message)
    }
    
    func testSignerCreation() throws {
        let result = tests.testSignerCreation()
        XCTAssertTrue(result.passed, result.message)
    }
    
    func testSignerWithCallback() throws {
        let result = tests.testSignerWithCallback()
        XCTAssertTrue(result.passed, result.message)
    }
    
    func testReaderCreation() throws {
        let result = tests.testReaderCreation()
        XCTAssertTrue(result.passed, result.message)
    }
    
    func testReaderWithTestImage() throws {
        let result = tests.testReaderWithTestImage()
        XCTAssertTrue(result.passed, result.message)
    }
    
    func testSigningAlgorithms() throws {
        let result = tests.testSigningAlgorithms()
        XCTAssertTrue(result.passed, result.message)
    }
    
    func testErrorEnumCases() throws {
        let result = tests.testErrorEnumCases()
        XCTAssertTrue(result.passed, result.message)
    }
    
    func testEndToEndSigning() throws {
        let result = tests.testEndToEndSigning()
        XCTAssertTrue(result.passed, result.message)
    }
    
    func testReadIngredient() throws {
        let result = tests.testReadIngredient()
        XCTAssertTrue(result.passed, result.message)
    }
}