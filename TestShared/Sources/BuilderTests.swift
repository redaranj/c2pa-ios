import C2PA
import Foundation

/// Builder tests - pure Swift implementation
public final class BuilderTests {
    
    private let impl = BuilderTestsImpl()
    
    public init() {}
    
    public func runAllTests() -> [TestResult] {
        return impl.runAllTests()
    }
    
    // Individual test methods for UI or direct calling
    public func testBuilderAPI() -> TestResult { 
        impl.testBuilderAPI() 
    }
    
    public func testBuilderNoEmbed() -> TestResult { 
        impl.testBuilderNoEmbed() 
    }
    
    public func testBuilderAddResource() -> TestResult { 
        impl.testBuilderAddResource() 
    }
    
    public func testBuilderAddIngredient() -> TestResult { 
        impl.testBuilderAddIngredient() 
    }
    
    public func testBuilderFromArchive() -> TestResult { 
        impl.testBuilderFromArchive() 
    }
    
    public func testBuilderRemoteURL() -> TestResult { 
        impl.testBuilderRemoteURL() 
    }
    
    public func testReadIngredient() -> TestResult { 
        impl.testReadIngredient() 
    }
}