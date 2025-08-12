import Vapor

struct CertificateController {
    
    // POST /api/v1/certificates/sign
    func signCSR(req: Request) async throws -> SignedCertificateResponse {
        let csrRequest = try req.content.decode(CertificateSigningRequest.self)
        
        // Validate CSR format
        guard csrRequest.csr.contains("BEGIN CERTIFICATE REQUEST") else {
            throw Abort(.badRequest, reason: "Invalid CSR format")
        }
        
        // Sign the CSR
        let response = try await req.application.certificateService.signCSR(
            csrRequest.csr,
            metadata: csrRequest.metadata
        )
        
        // Log the issuance
        req.logger.info("Issued certificate: \(response.certificateId)")
        
        return response
    }
}