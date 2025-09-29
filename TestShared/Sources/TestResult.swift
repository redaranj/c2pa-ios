import Foundation

// Test result structure for UI display
public struct TestResult: Sendable {
    public let testName: String
    public let passed: Bool
    public let message: String
    public let details: String?
    public let duration: TimeInterval?

    public init(testName: String, passed: Bool, message: String, details: String? = nil, duration: TimeInterval? = nil)
    {
        self.testName = testName
        self.passed = passed
        self.message = message
        self.details = details
        self.duration = duration
    }

    // Create a success result
    public static func success(_ testName: String, _ message: String, details: String? = nil)
        -> TestResult
    {
        TestResult(testName: testName, passed: true, message: message, details: details)
    }

    // Create a failure result
    public static func failure(_ testName: String, _ message: String, details: String? = nil)
        -> TestResult
    {
        TestResult(testName: testName, passed: false, message: message, details: details)
    }
}

// Protocol for test implementations
public protocol TestImplementation {
    func runAllTests() async -> [TestResult]
}
