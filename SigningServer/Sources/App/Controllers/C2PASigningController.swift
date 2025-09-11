import Vapor

struct C2PASigningController {
    func signManifest(req: Request) async throws -> C2PASigningResponse {
        let signingRequest = try req.content.decode(C2PASigningRequest.self)

        print("[C2PA Controller] Received signing request")

        let certPath = FileManager.default.currentDirectoryPath + "/Resources/es256_certs.pem"
        let keyPath = FileManager.default.currentDirectoryPath + "/Resources/es256_private.key"

        let certificateChain = try String(contentsOfFile: certPath, encoding: .utf8)
        let privateKeyPEM = try String(contentsOfFile: keyPath, encoding: .utf8)

        guard certificateChain.contains("BEGIN CERTIFICATE") else {
            throw Abort(.internalServerError, reason: "Invalid certificate format")
        }

        guard privateKeyPEM.contains("BEGIN PRIVATE KEY") || privateKeyPEM.contains("BEGIN EC PRIVATE KEY") else {
            throw Abort(.internalServerError, reason: "Invalid private key format")
        }

        // Decode the base64-encoded data to sign
        guard let dataToSign = Data(base64Encoded: signingRequest.claim) else {
            throw Abort(.badRequest, reason: "Invalid base64-encoded data")
        }

        print("[C2PA] Creating signer for data signing")
        print("[C2PA] Data to sign size: \(dataToSign.count) bytes")
        print("[C2PA] Using certificates from: Resources/es256_certs.pem")

        let privateKey = try P256.Signing.PrivateKey(pemRepresentation: privateKeyPEM)
        let signature = try privateKey.signature(for: dataToSign)
        let base64Signature = signature.rawRepresentation.base64EncodedString()

        print("[C2PA] Signature created, size: \(signature.rawRepresentation.count) bytes")
        print("[C2PA Controller] Signature generated successfully")

        return C2PASigningResponse(
            signature: base64Signature
        )
    }
}
