import Foundation
import Vapor
import X509
import SwiftASN1
import Crypto

class CertificateSigningService {
    private let rootCA: Certificate
    private let rootCAPrivateKey: P256.Signing.PrivateKey
    private let intermediateCA: Certificate
    private let intermediateCAPrivateKey: P256.Signing.PrivateKey
    
    // In-memory certificate store (in production, use a database)
    private var issuedCertificates: [String: IssuedCertificate] = [:]
    
    struct IssuedCertificate {
        let certificate: Certificate
        let certificateChain: String
        let metadata: CSRMetadata?
        let issuedAt: Date
        var status: CertificateStatus
    }
    
    init() {
        // Initialize CA certificates
        do {
            // Generate Root CA
            rootCAPrivateKey = P256.Signing.PrivateKey()
            let rootSubject = try DistinguishedName {
                CommonName("C2PA Test Root CA")
                OrganizationName("C2PA Signing Server")
                OrganizationalUnitName("Certificate Authority")
                CountryName("US")
                StateOrProvinceName("California")
                LocalityName("San Francisco")
            }
            
            let rootPublicKeyData = rootCAPrivateKey.publicKey.rawRepresentation
            let rootExtensions = try Certificate.Extensions {
                BasicConstraints.isCertificateAuthority(maxPathLength: 2)
                KeyUsage(keyCertSign: true, cRLSign: true)
                SubjectKeyIdentifier(
                    keyIdentifier: ArraySlice(SHA256.hash(data: rootPublicKeyData))
                )
            }
            
            rootCA = try Certificate(
                version: .v3,
                serialNumber: Certificate.SerialNumber(),
                publicKey: Certificate.PublicKey(rootCAPrivateKey.publicKey),
                notValidBefore: Date().addingTimeInterval(-60), // 1 minute ago
                notValidAfter: Date().addingTimeInterval(10 * 365 * 24 * 60 * 60), // 10 years
                issuer: rootSubject,
                subject: rootSubject,
                signatureAlgorithm: .ecdsaWithSHA256,
                extensions: rootExtensions,
                issuerPrivateKey: Certificate.PrivateKey(rootCAPrivateKey)
            )
            
            // Generate Intermediate CA
            intermediateCAPrivateKey = P256.Signing.PrivateKey()
            let intermediateSubject = try DistinguishedName {
                CommonName("C2PA Test Intermediate CA")
                OrganizationName("C2PA Signing Server")
                OrganizationalUnitName("Certificate Authority")
                CountryName("US")
                StateOrProvinceName("California")
                LocalityName("San Francisco")
            }
            
            let intermediatePublicKeyData = intermediateCAPrivateKey.publicKey.rawRepresentation
            let rootKeyIdentifier = ArraySlice(SHA256.hash(data: rootPublicKeyData))
            let intermediateExtensions = try Certificate.Extensions {
                BasicConstraints.isCertificateAuthority(maxPathLength: 0)
                KeyUsage(keyCertSign: true, cRLSign: true)
                SubjectKeyIdentifier(
                    keyIdentifier: ArraySlice(SHA256.hash(data: intermediatePublicKeyData))
                )
                AuthorityKeyIdentifier(
                    keyIdentifier: rootKeyIdentifier
                )
            }
            
            intermediateCA = try Certificate(
                version: .v3,
                serialNumber: Certificate.SerialNumber(),
                publicKey: Certificate.PublicKey(intermediateCAPrivateKey.publicKey),
                notValidBefore: Date().addingTimeInterval(-60), // 1 minute ago
                notValidAfter: Date().addingTimeInterval(5 * 365 * 24 * 60 * 60), // 5 years
                issuer: rootCA.subject,
                subject: intermediateSubject,
                signatureAlgorithm: .ecdsaWithSHA256,
                extensions: intermediateExtensions,
                issuerPrivateKey: Certificate.PrivateKey(rootCAPrivateKey)
            )
        } catch {
            fatalError("Failed to initialize CA certificates: \(error)")
        }
    }
    
    func signCSR(_ csrPEM: String, metadata: CSRMetadata?) async throws -> SignedCertificateResponse {
        // Parse the CSR
        let _ = try pemToData(csrPEM, type: "CERTIFICATE REQUEST")
        
        // In production, properly parse and validate the CSR
        // For now, we'll create a test certificate
        let endEntityPrivateKey = P256.Signing.PrivateKey()
        
        // Extract subject from CSR (simplified - in production, parse the actual CSR)
        let subject = try DistinguishedName {
            CommonName("C2PA Content Signer")
            OrganizationName("Test Organization")
            OrganizationalUnitName("Content Authentication")
            CountryName("US")
            StateOrProvinceName("California")
            LocalityName("San Francisco")
            EmailAddress("signer@example.com")
        }
        
        let extensions = try Certificate.Extensions {
            BasicConstraints.notCertificateAuthority
            KeyUsage(digitalSignature: true)
            try ExtendedKeyUsage([.emailProtection])
            SubjectKeyIdentifier(
                keyIdentifier: ArraySlice(SHA256.hash(data: endEntityPrivateKey.publicKey.rawRepresentation))
            )
            AuthorityKeyIdentifier(
                keyIdentifier: ArraySlice(SHA256.hash(data: intermediateCAPrivateKey.publicKey.rawRepresentation))
            )
        }
        
        let certificate = try Certificate(
            version: .v3,
            serialNumber: Certificate.SerialNumber(),
            publicKey: Certificate.PublicKey(endEntityPrivateKey.publicKey),
            notValidBefore: Date().addingTimeInterval(-60), // 1 minute ago
            notValidAfter: Date().addingTimeInterval(365 * 24 * 60 * 60), // 1 year
            issuer: intermediateCA.subject,
            subject: subject,
            signatureAlgorithm: .ecdsaWithSHA256,
            extensions: extensions,
            issuerPrivateKey: Certificate.PrivateKey(intermediateCAPrivateKey)
        )
        
        // Generate certificate chain
        let certificateChain = try [
            certificate.serializeAsPEM().pemString,
            intermediateCA.serializeAsPEM().pemString,
            rootCA.serializeAsPEM().pemString
        ].joined(separator: "\n")
        
        // Store the certificate
        let certificateId = UUID().uuidString
        issuedCertificates[certificateId] = IssuedCertificate(
            certificate: certificate,
            certificateChain: certificateChain,
            metadata: metadata,
            issuedAt: Date(),
            status: .active
        )
        
        return SignedCertificateResponse(
            certificateId: certificateId,
            certificateChain: certificateChain,
            expiresAt: certificate.notValidAfter,
            serialNumber: String(describing: certificate.serialNumber)
        )
    }
    
    func getCACertificates() -> CACertificateResponse {
        do {
            return CACertificateResponse(
                rootCertificate: try rootCA.serializeAsPEM().pemString,
                intermediateCertificate: try intermediateCA.serializeAsPEM().pemString
            )
        } catch {
            // This shouldn't happen with properly initialized CAs
            return CACertificateResponse(rootCertificate: "", intermediateCertificate: "")
        }
    }
    
    func getCertificate(id: String) -> IssuedCertificate? {
        return issuedCertificates[id]
    }
    
    func revokeCertificate(id: String) -> Bool {
        guard var cert = issuedCertificates[id] else { return false }
        cert.status = .revoked
        issuedCertificates[id] = cert
        return true
    }
    
    func generateTemporaryCertificate() throws -> (certificateChain: String, privateKey: P256.Signing.PrivateKey) {
        let privateKey = P256.Signing.PrivateKey()
        
        let subject = try DistinguishedName {
            CommonName("Temporary C2PA Signer")
            OrganizationName("Temporary Certificate")
            OrganizationalUnitName("FOR TESTING ONLY")
            CountryName("US")
        }
        
        let extensions = try Certificate.Extensions {
            BasicConstraints.notCertificateAuthority
            KeyUsage(digitalSignature: true)
            try ExtendedKeyUsage([.emailProtection])
            SubjectKeyIdentifier(
                keyIdentifier: ArraySlice(SHA256.hash(data: privateKey.publicKey.rawRepresentation))
            )
            AuthorityKeyIdentifier(
                keyIdentifier: ArraySlice(SHA256.hash(data: intermediateCAPrivateKey.publicKey.rawRepresentation))
            )
        }
        
        let certificate = try Certificate(
            version: .v3,
            serialNumber: Certificate.SerialNumber(),
            publicKey: Certificate.PublicKey(privateKey.publicKey),
            notValidBefore: Date().addingTimeInterval(-60), // 1 minute ago
            notValidAfter: Date().addingTimeInterval(24 * 60 * 60), // 1 day
            issuer: intermediateCA.subject,
            subject: subject,
            signatureAlgorithm: .ecdsaWithSHA256,
            extensions: extensions,
            issuerPrivateKey: Certificate.PrivateKey(intermediateCAPrivateKey)
        )
        
        let certificateChain = try [
            certificate.serializeAsPEM().pemString,
            intermediateCA.serializeAsPEM().pemString,
            rootCA.serializeAsPEM().pemString
        ].joined(separator: "\n")
        
        return (certificateChain, privateKey)
    }
    
    // MARK: - Helper Methods
    
    private func pemToData(_ pem: String, type: String) throws -> Data {
        let lines = pem.components(separatedBy: .newlines)
        let beginMarker = "-----BEGIN \(type)-----"
        let endMarker = "-----END \(type)-----"
        
        var base64String = ""
        var inCert = false
        
        for line in lines {
            if line == beginMarker {
                inCert = true
                continue
            } else if line == endMarker {
                break
            } else if inCert {
                base64String += line
            }
        }
        
        guard let data = Data(base64Encoded: base64String) else {
            throw Abort(.badRequest, reason: "Invalid PEM encoding")
        }
        
        return data
    }
}