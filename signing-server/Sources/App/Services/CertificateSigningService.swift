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
                BasicConstraints.isCertificateAuthority(maxPathLength: 1)
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
        let csrData = try pemToData(csrPEM, type: "CERTIFICATE REQUEST")
        
        // Parse the CSR from DER data
        let csr = try parseCertificateSigningRequest(from: csrData)
        
        // Extract the public key and subject from the CSR
        let publicKey = csr.publicKey
        let subject = csr.subject
        
        // Create extensions for the end-entity certificate
        // For SubjectKeyIdentifier, we need to match the calculation in CertificateManager
        // which uses the raw key representation (65 bytes for P256)
        // Since Certificate.PublicKey doesn't expose the raw key directly,
        // we'll extract it from the serialized SubjectPublicKeyInfo
        
        // First, serialize the public key to get the SubjectPublicKeyInfo
        var spkiSerializer = DER.Serializer()
        try publicKey.serialize(into: &spkiSerializer)
        let spkiData = Data(spkiSerializer.serializedBytes)
        
        // For P256 keys in X.509, the public key is the last 65 bytes (0x04 + 32 bytes X + 32 bytes Y)
        // This is a bit hacky but matches what CertificateManager does
        let publicKeyData: Data
        if spkiData.count >= 65 {
            // Extract the last 65 bytes which should be the raw public key
            let keyStart = spkiData.count - 65
            if spkiData[keyStart] == 0x04 { // Uncompressed point indicator
                publicKeyData = spkiData[keyStart..<spkiData.count]
            } else {
                // Fallback to full SPKI hash
                publicKeyData = spkiData
            }
        } else {
            // Fallback to full SPKI hash
            publicKeyData = spkiData
        }
        
        let extensions = try Certificate.Extensions {
            BasicConstraints.notCertificateAuthority
            KeyUsage(digitalSignature: true)
            try ExtendedKeyUsage([.emailProtection])
            SubjectKeyIdentifier(
                keyIdentifier: ArraySlice(SHA256.hash(data: publicKeyData))
            )
            AuthorityKeyIdentifier(
                keyIdentifier: ArraySlice(SHA256.hash(data: intermediateCAPrivateKey.publicKey.rawRepresentation))
            )
        }
        
        let certificate = try Certificate(
            version: .v3,
            serialNumber: Certificate.SerialNumber(),
            publicKey: publicKey,
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
        
        // Generate certificate ID
        let certificateId = UUID().uuidString
        
        return SignedCertificateResponse(
            certificateId: certificateId,
            certificateChain: certificateChain,
            expiresAt: certificate.notValidAfter,
            serialNumber: String(describing: certificate.serialNumber)
        )
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
    
    private func parseCertificateSigningRequest(from data: Data) throws -> X509.CertificateSigningRequest {
        let parsed = try X509.CertificateSigningRequest(derEncoded: Array(data))
        return parsed
    }
    
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