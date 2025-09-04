import C2PA
import Foundation

/// Stream tests - pure Swift implementation
public final class StreamTests {
    
    private let impl = StreamTestsImpl()
    
    public init() {}
    
    public func runAllTests() -> [TestResult] {
        return impl.runAllTests()
    }
    
    // Individual test methods for UI or direct calling
    public func testStreamOperations() -> TestResult { 
        impl.testStreamOperations() 
    }
    
    public func testStreamFileOperations() -> TestResult { 
        impl.testStreamFileOperations() 
    }
    
    public func testWriteOnlyStreams() -> TestResult { 
        impl.testWriteOnlyStreams() 
    }
    
    public func testCustomStreamCallbacks() -> TestResult { 
        impl.testCustomStreamCallbacks() 
    }
    
    public func testStreamWithLargeData() -> TestResult { 
        impl.testStreamWithLargeData() 
    }
    
    public func testMultipleStreams() -> TestResult { 
        impl.testMultipleStreams() 
    }
    
    public func testFileStreamOptions() -> TestResult { 
        impl.testFileStreamOptions() 
    }
    
    public func testStreamWithReader() -> TestResult { 
        impl.testStreamWithReader() 
    }
    
    public func testStreamWithBuilder() -> TestResult { 
        impl.testStreamWithBuilder() 
    }
}