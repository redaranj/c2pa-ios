import Vapor
import Foundation

// MARK: - Certificate Models

struct CertificateSigningRequest: Content {
    let csr: String  // PEM-encoded CSR
    let metadata: CSRMetadata?
}

struct CSRMetadata: Content {
    let deviceId: String?
    let appVersion: String?
    let purpose: String?
}

struct SignedCertificateResponse: Content {
    let certificateId: String
    let certificateChain: String  // PEM-encoded certificate chain
    let expiresAt: Date
    let serialNumber: String
}


// MARK: - C2PA Models

struct C2PASigningRequest: Content {
    let manifestJSON: String
    let format: String  // e.g., "image/jpeg"
}

struct C2PASigningResponse: Content {
    let manifestStore: Data  // Binary manifest store data
    let signatureInfo: SignatureInfo
}

struct SignatureInfo: Content {
    let algorithm: String
    let certificateChain: String?
    let timestamp: Date
}


