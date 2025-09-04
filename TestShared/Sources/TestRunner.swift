import Foundation

/// Test runner for UI - aggregates all test suites
public final class TestRunner {
    
    public init() {}
    
    /// Run all test suites and return results
    public func runAllTests() -> [TestSuiteResult] {
        var suites: [TestSuiteResult] = []
        
        // Stream Tests
        let streamTests = StreamTests()
        let streamResults = streamTests.runAllTests()
        suites.append(TestSuiteResult(name: "Stream Tests", results: streamResults))
        
        // Builder Tests
        let builderTests = BuilderTests()
        let builderResults = builderTests.runAllTests()
        suites.append(TestSuiteResult(name: "Builder Tests", results: builderResults))
        
        // Reader Tests
        let readerTests = ReaderTests()
        let readerResults = readerTests.runAllTests()
        suites.append(TestSuiteResult(name: "Reader Tests", results: readerResults))
        
        // Signing Tests
        let signingTests = SigningTests()
        let signingResults = signingTests.runAllTests()
        suites.append(TestSuiteResult(name: "Signing Tests", results: signingResults))
        
        // Comprehensive Tests
        let comprehensiveTests = ComprehensiveTests()
        let comprehensiveResults = comprehensiveTests.runAllTests()
        suites.append(TestSuiteResult(name: "Comprehensive Tests", results: comprehensiveResults))
        
        return suites
    }
    
    /// Run a specific test suite
    public func runTestSuite(_ suite: TestSuite) -> [TestResult] {
        switch suite {
        case .stream:
            return StreamTests().runAllTests()
        case .builder:
            return BuilderTests().runAllTests()
        case .reader:
            return ReaderTests().runAllTests()
        case .signing:
            return SigningTests().runAllTests()
        case .comprehensive:
            return ComprehensiveTests().runAllTests()
        }
    }
}

/// Available test suites
public enum TestSuite: String, CaseIterable {
    case stream = "Stream"
    case builder = "Builder"
    case reader = "Reader"
    case signing = "Signing"
    case comprehensive = "Comprehensive"
    
    public var displayName: String {
        return rawValue + " Tests"
    }
}

/// Test suite result container
public struct TestSuiteResult {
    public let name: String
    public let results: [TestResult]
    
    public init(name: String, results: [TestResult]) {
        self.name = name
        self.results = results
    }
    
    public var passedCount: Int {
        results.filter { $0.passed }.count
    }
    
    public var failedCount: Int {
        results.filter { !$0.passed }.count
    }
    
    public var totalCount: Int {
        results.count
    }
    
    public var passRate: Double {
        guard totalCount > 0 else { return 0 }
        return Double(passedCount) / Double(totalCount)
    }
}