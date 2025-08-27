import Crypto
import Foundation
import SwiftASN1
import Vapor
import X509

class CertificateSigningService {
    private let rootCA: Certificate
    private let rootCAPrivateKey: P256.Signing.PrivateKey
    private let intermediateCA: Certificate
    private let intermediateCAPrivateKey: P256.Signing.PrivateKey

    init() {
        do {
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
                notValidBefore: Date().addingTimeInterval(-60),
                notValidAfter: Date().addingTimeInterval(10 * 365 * 24 * 60 * 60),
                issuer: rootSubject,
                subject: rootSubject,
                signatureAlgorithm: .ecdsaWithSHA256,
                extensions: rootExtensions,
                issuerPrivateKey: Certificate.PrivateKey(rootCAPrivateKey)
            )

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
                notValidBefore: Date().addingTimeInterval(-60),
                notValidAfter: Date().addingTimeInterval(5 * 365 * 24 * 60 * 60),
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

    func signCSR(_ csrPEM: String) async throws -> SignedCertificateResponse {
        let csrData = try pemToData(csrPEM, type: "CERTIFICATE REQUEST")
        let csr = try X509.CertificateSigningRequest(derEncoded: Array(csrData))

        // Extract raw public key for SubjectKeyIdentifier (P256 = 65 bytes)
        var spkiSerializer = DER.Serializer()
        try csr.publicKey.serialize(into: &spkiSerializer)
        let spkiData = Data(spkiSerializer.serializedBytes)

        let publicKeyData: Data
        if spkiData.count >= 65 {
            let keyStart = spkiData.count - 65
            if spkiData[keyStart] == 0x04 {
                publicKeyData = spkiData[keyStart..<spkiData.count]
            } else {
                publicKeyData = spkiData
            }
        } else {
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
                keyIdentifier: ArraySlice(
                    SHA256.hash(data: intermediateCAPrivateKey.publicKey.rawRepresentation))
            )
        }

        let certificate = try Certificate(
            version: .v3,
            serialNumber: Certificate.SerialNumber(),
            publicKey: csr.publicKey,
            notValidBefore: Date().addingTimeInterval(-60),
            notValidAfter: Date().addingTimeInterval(365 * 24 * 60 * 60),
            issuer: intermediateCA.subject,
            subject: csr.subject,
            signatureAlgorithm: .ecdsaWithSHA256,
            extensions: extensions,
            issuerPrivateKey: Certificate.PrivateKey(intermediateCAPrivateKey)
        )

        let certificateChain = try [
            certificate.serializeAsPEM().pemString,
            intermediateCA.serializeAsPEM().pemString,
            rootCA.serializeAsPEM().pemString,
        ].joined(separator: "\n")

        return SignedCertificateResponse(
            certificateId: UUID().uuidString,
            certificateChain: certificateChain,
            expiresAt: certificate.notValidAfter,
            serialNumber: String(describing: certificate.serialNumber)
        )
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
