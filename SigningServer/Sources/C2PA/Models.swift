import Foundation

// MARK: - Core Models

/// Represents a C2PA manifest
public struct Manifest {
    public let claim: Claim
    public let assertions: [Assertion]
    public let signature: Data?
    
    public init(claim: Claim, assertions: [Assertion] = [], signature: Data? = nil) {
        self.claim = claim
        self.assertions = assertions
        self.signature = signature
    }
}

/// Represents a C2PA claim
public struct Claim {
    public let generator: String
    public let title: String?
    public let format: String
    public let instanceID: String?
    public let metadata: [String: Any]?
    
    public init(
        generator: String,
        title: String? = nil,
        format: String,
        instanceID: String? = nil,
        metadata: [String: Any]? = nil
    ) {
        self.generator = generator
        self.title = title
        self.format = format
        self.instanceID = instanceID
        self.metadata = metadata
    }
}

/// Represents a C2PA assertion
public struct Assertion {
    public let label: String
    public let data: Data
    
    public init(label: String, data: Data) {
        self.label = label
        self.data = data
    }
}

/// Protocol for signing providers
public protocol Signer {
    func sign(data: Data) async throws -> Data
    func getCertificateChain() async throws -> Data
    func getAlgorithm() -> String
}

/// Validation result
public struct ValidationResult {
    public let isValid: Bool
    public let error: Error?
    public let details: [String: Any]?
    
    public init(isValid: Bool, error: Error? = nil, details: [String: Any]? = nil) {
        self.isValid = isValid
        self.error = error
        self.details = details
    }
}

// MARK: - Type Aliases for backward compatibility
// These maintain compatibility with existing test code

public typealias C2PAManifest = Manifest
public typealias C2PAClaim = Claim
public typealias C2PAAssertion = Assertion