import C2PA
import Foundation

/// Signing tests - pure Swift implementation
public final class SigningTests {
    
    private let impl = SigningTestsImpl()
    
    public init() {}
    
    public func runAllTests() -> [TestResult] {
        return impl.runAllTests()
    }
    
    // Individual test methods for UI or direct calling
    public func testSignerCreation() -> TestResult { 
        impl.testSignerCreation() 
    }
    
    public func testSignerWithCallback() -> TestResult { 
        impl.testSignerWithCallback() 
    }
    
    public func testSigningAlgorithms() -> TestResult { 
        impl.testSigningAlgorithms() 
    }
    
    public func testSignerReserveSize() -> TestResult { 
        impl.testSignerReserveSize() 
    }
    
    public func testSignerWithTimestampAuthority() -> TestResult { 
        impl.testSignerWithTimestampAuthority() 
    }
    
    public func testWebServiceSignerCreation() -> TestResult { 
        impl.testWebServiceSignerCreation() 
    }
    
    public func testSignerMemoryManagement() -> TestResult { 
        impl.testSignerMemoryManagement() 
    }
    
    public func testSignerWithActualSigning() -> TestResult { 
        impl.testSignerWithActualSigning() 
    }
    
    public func testMultipleSigningAlgorithmsWithCallback() -> TestResult { 
        impl.testMultipleSigningAlgorithmsWithCallback() 
    }
}