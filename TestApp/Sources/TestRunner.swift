import Foundation
import TestShared

/// Test runner wrapper for TestApp UI
/// This simply forwards to the TestShared TestRunner
extension TestRunner {
    
    /// Get list of available test suites
    func getTestSuites() -> [String] {
        return TestSuite.allCases.map { $0.displayName }
    }
    
    /// Run tests for a specific suite by name
    func runTestSuite(_ suiteName: String) async -> [TestResult] {
        // Find the matching test suite
        guard let suite = TestSuite.allCases.first(where: { $0.displayName == suiteName }) else {
            return []
        }
        
        // Run the test suite synchronously but wrap in async context
        return await withCheckedContinuation { continuation in
            let results = runTestSuite(suite)
            continuation.resume(returning: results)
        }
    }
    
    /// Run all tests
    func runAllTests() async -> [TestSuiteResult] {
        // Run all test suites
        return await withCheckedContinuation { continuation in
            let suiteResults = runAllTests()
            continuation.resume(returning: suiteResults)
        }
    }
}