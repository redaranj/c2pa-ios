import C2PA
import Foundation

/// Reader tests - pure Swift implementation
public final class ReaderTests {
    
    private let impl = ReaderTestsImpl()
    
    public init() {}
    
    public func runAllTests() -> [TestResult] {
        return impl.runAllTests()
    }
    
    // Individual test methods for UI or direct calling
    public func testReaderResourceErrorHandling() -> TestResult { 
        impl.testReaderResourceErrorHandling() 
    }
    
    public func testReaderWithManifestData() -> TestResult { 
        impl.testReaderWithManifestData() 
    }
    
    public func testResourceReading() -> TestResult { 
        impl.testResourceReading() 
    }
    
    public func testReaderValidation() -> TestResult { 
        impl.testReaderValidation() 
    }
    
    public func testReaderThumbnailExtraction() -> TestResult { 
        impl.testReaderThumbnailExtraction() 
    }
    
    public func testReaderIngredientExtraction() -> TestResult { 
        impl.testReaderIngredientExtraction() 
    }
    
    public func testReaderJSONParsing() -> TestResult { 
        impl.testReaderJSONParsing() 
    }
    
    public func testReaderWithMultipleStreams() -> TestResult { 
        impl.testReaderWithMultipleStreams() 
    }
}