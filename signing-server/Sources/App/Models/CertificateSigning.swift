import Foundation
import Vapor

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
