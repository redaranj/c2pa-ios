import Foundation
import Vapor

struct C2PASigningRequest: Content {
    let manifestJSON: String
    let format: String  // e.g., "image/jpeg"
}

struct C2PASigningResponse: Content {
    let manifestStore: Data
    let signatureInfo: SignatureInfo
}

struct SignatureInfo: Content {
    let algorithm: String
    let certificateChain: String?
    let timestamp: Date
}
