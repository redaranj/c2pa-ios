import C2PA
import Foundation

/// Comprehensive tests - pure Swift implementation
public final class ComprehensiveTests {
    
    private let impl = ComprehensiveTestsImpl()
    
    public init() {}
    
    public func runAllTests() -> [TestResult] {
        return impl.runAllTests()
    }
    
    // Individual test methods for UI or direct calling
    public func testLibraryVersion() -> TestResult { 
        impl.testLibraryVersion() 
    }
    
    public func testErrorHandling() -> TestResult { 
        impl.testErrorHandling() 
    }
    
    public func testReadImageWithManifest() -> TestResult { 
        impl.testReadImageWithManifest() 
    }
    
    public func testStreamFromData() -> TestResult { 
        impl.testStreamFromData() 
    }
    
    public func testStreamFromFile() -> TestResult { 
        impl.testStreamFromFile() 
    }
    
    public func testStreamWithCallbacks() -> TestResult { 
        impl.testStreamWithCallbacks() 
    }
    
    public func testBuilderCreation() -> TestResult { 
        impl.testBuilderCreation() 
    }
    
    public func testBuilderNoEmbed() -> TestResult { 
        impl.testBuilderNoEmbed() 
    }
    
    public func testBuilderRemoteURL() -> TestResult { 
        impl.testBuilderRemoteURL() 
    }
    
    public func testBuilderAddResource() -> TestResult { 
        impl.testBuilderAddResource() 
    }
    
    public func testSignerCreation() -> TestResult { 
        impl.testSignerCreation() 
    }
    
    public func testSignerWithCallback() -> TestResult { 
        impl.testSignerWithCallback() 
    }
    
    public func testReaderCreation() -> TestResult { 
        impl.testReaderCreation() 
    }
    
    public func testReaderWithTestImage() -> TestResult { 
        impl.testReaderWithTestImage() 
    }
    
    public func testSigningAlgorithms() -> TestResult { 
        impl.testSigningAlgorithms() 
    }
    
    public func testErrorEnumCases() -> TestResult { 
        impl.testErrorEnumCases() 
    }
    
    public func testEndToEndSigning() -> TestResult { 
        impl.testEndToEndSigning() 
    }
    
    public func testReadIngredient() -> TestResult { 
        impl.testReadIngredient() 
    }
}