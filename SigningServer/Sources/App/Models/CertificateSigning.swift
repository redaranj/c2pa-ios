import Foundation
import Vapor

struct CertificateSigningRequest: Content {
    let csr: String  // PEM-encoded CSR
    let metadata: CSRMetadata?
}

struct CSRMetadata: Content {
    let device_id: String?
    let app_version: String?
}

struct SignedCertificateResponse: Content {
    let certificate_id: String
    let certificate_chain: String  // PEM-encoded certificate chain
    let expires_at: Date
    let serial_number: String
}
