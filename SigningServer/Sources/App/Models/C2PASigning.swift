import Foundation
import Vapor

struct C2PASigningRequest: Content {
    let claim: String  // Base64-encoded bytes to be signed
}

struct C2PASigningResponse: Content {
    let signature: String  // Base64 encoded signature
}
