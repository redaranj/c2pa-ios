import Vapor

struct CertificateSigningController {
    func signCSR(req: Request) async throws -> SignedCertificateResponse {
        req.logger.info("=== Certificate Signing Request Headers ===")
        for (name, value) in req.headers {
            req.logger.info("Header: \(name) = \(value)")
        }
        req.logger.info("=== End Headers ===")

        let csrRequest = try req.content.decode(CertificateSigningRequest.self)

        guard csrRequest.csr.contains("BEGIN CERTIFICATE REQUEST") else {
            throw Abort(.badRequest, reason: "Invalid CSR format")
        }

        let response = try await req.application.certificateService.signCSR(csrRequest.csr)
        req.logger.info("Issued certificate: \(response.certificate_id)")

        return response
    }
}
