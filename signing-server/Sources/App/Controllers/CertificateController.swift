import Vapor

struct CertificateController {
    
    // POST /api/v1/certificates/csr
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
    
    // GET /api/v1/certificates/ca
    func getCACertificate(req: Request) async throws -> CACertificateResponse {
        return req.application.certificateService.getCACertificates()
    }
    
    // GET /api/v1/certificates/:id
    func getCertificate(req: Request) async throws -> CertificateInfo {
        guard let certificateId = req.parameters.get("id") else {
            throw Abort(.badRequest, reason: "Certificate ID required")
        }
        
        guard let issuedCert = req.application.certificateService.getCertificate(id: certificateId) else {
            throw Abort(.notFound, reason: "Certificate not found")
        }
        
        // Convert to response format
        return CertificateInfo(
            certificateId: certificateId,
            subject: String(describing: issuedCert.certificate.subject),
            issuer: String(describing: issuedCert.certificate.issuer),
            serialNumber: String(describing: issuedCert.certificate.serialNumber),
            notBefore: issuedCert.certificate.notValidBefore,
            notAfter: issuedCert.certificate.notValidAfter,
            status: issuedCert.status
        )
    }
    
    // DELETE /api/v1/certificates/:id
    func revokeCertificate(req: Request) async throws -> HTTPStatus {
        guard let certificateId = req.parameters.get("id") else {
            throw Abort(.badRequest, reason: "Certificate ID required")
        }
        
        req.logger.info("Revoking certificate: \(certificateId)")
        
        guard req.application.certificateService.revokeCertificate(id: certificateId) else {
            throw Abort(.notFound, reason: "Certificate not found")
        }
        
        return .ok
    }
}