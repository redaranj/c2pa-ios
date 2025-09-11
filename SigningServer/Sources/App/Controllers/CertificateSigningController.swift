import Vapor

struct CertificateSigningController {
    func signCSR(req: Request) async throws -> SignedCertificateResponse {
        let csrRequest = try req.content.decode(CertificateSigningRequest.self)

        guard csrRequest.csr.contains("BEGIN CERTIFICATE REQUEST") else {
            throw Abort(.badRequest, reason: "Invalid CSR format")
        }

        let response = try await req.application.certificateService.signCSR(csrRequest.csr)
        req.logger.info("Issued certificate: \(response.cert_id)")

        return response
    }
}
