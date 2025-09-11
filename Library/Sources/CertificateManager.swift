//
//  CertificateManager.swift
//

import Crypto
import Foundation
import Security
import SwiftASN1
import X509

public class CertificateManager {

    public enum CertificateError: LocalizedError {
        case invalidKeyData
        case unsupportedAlgorithm
        case unsupportedKeyFormat
        case signingFailed(String)

        public var errorDescription: String? {
            switch self {
            case .invalidKeyData:
                return "Invalid key data"
            case .unsupportedAlgorithm:
                return "Unsupported algorithm"
            case .unsupportedKeyFormat:
                return "Unsupported key format"
            case .signingFailed(let details):
                return "Failed to sign: \(details)"
            }
        }
    }

    public struct CertificateConfig {
        public let commonName: String
        public let organization: String
        public let organizationalUnit: String
        public let country: String
        public let state: String
        public let locality: String
        public let emailAddress: String?
        public let validityDays: Int

        public init(
            commonName: String,
            organization: String,
            organizationalUnit: String,
            country: String,
            state: String,
            locality: String,
            emailAddress: String? = nil,
            validityDays: Int = 365
        ) {
            self.commonName = commonName
            self.organization = organization
            self.organizationalUnit = organizationalUnit
            self.country = country
            self.state = state
            self.locality = locality
            self.emailAddress = emailAddress
            self.validityDays = validityDays
        }
    }

    // MARK: - Public Methods

    // Creates a self-signed certificate chain suitable for C2PA signing
    public static func createSelfSignedCertificateChain(
        for publicKey: SecKey,
        config: CertificateConfig
    ) throws -> String {
        // For Secure Enclave keys, we need to create a certificate chain
        // using regular P256 keys for the CA certificates
        let rootKeyPair = P256.Signing.PrivateKey()
        let intermediateKeyPair = P256.Signing.PrivateKey()

        let rootConfig = CertificateConfig(
            commonName: "\(config.organization) Root CA",
            organization: config.organization,
            organizationalUnit: config.organizationalUnit,
            country: config.country,
            state: config.state,
            locality: config.locality,
            validityDays: config.validityDays * 10
        )

        let rootCert = try createRootCA(
            privateKey: rootKeyPair,
            config: rootConfig
        )

        let intermediateConfig = CertificateConfig(
            commonName: "\(config.organization) Intermediate CA",
            organization: config.organization,
            organizationalUnit: config.organizationalUnit,
            country: config.country,
            state: config.state,
            locality: config.locality,
            validityDays: config.validityDays * 5
        )

        let intermediateCert = try createIntermediateCA(
            privateKey: intermediateKeyPair,
            config: intermediateConfig,
            issuerCertificate: rootCert,
            issuerPrivateKey: rootKeyPair
        )

        let endEntityCert = try createEndEntityCertificate(
            publicKey: publicKey,
            config: config,
            issuerCertificate: intermediateCert,
            issuerPrivateKey: intermediateKeyPair
        )

        let endEntity = try endEntityCert.serializeAsPEM().pemString
        let intermediate = try intermediateCert.serializeAsPEM().pemString
        let root = try rootCert.serializeAsPEM().pemString

        return endEntity + "\n" + intermediate + "\n" + root
    }

    // Creates a Certificate Signing Request (CSR) for a secure enclave key
    public static func createCSR(
        for publicKey: SecKey,
        config: CertificateConfig
    ) throws -> String {
        // For Secure Enclave keys, we need to manually create the CSR
        // because we don't have access to the private key material

        // Find the corresponding private key reference (not the key material)
        guard let privateKey = try findPrivateKey(for: publicKey) else {
            throw CertificateError.invalidKeyData
        }

        guard let publicKeyData = SecKeyCopyExternalRepresentation(publicKey, nil) as Data? else {
            throw CertificateError.invalidKeyData
        }

        // Parse to get P256 public key for use with Certificate.PublicKey
        let p256PublicKey = try parseSecKeyPublicKey(publicKeyData)

        return try createCSRManually(
            publicKey: p256PublicKey,
            privateKey: privateKey,
            config: config
        )
    }

    // Creates a CSR for a keychain key by tag
    public static func createCSR(
        keyTag: String,
        config: CertificateConfig
    ) throws -> String {
        let query: [String: Any] = [
            kSecClass as String: kSecClassKey,
            kSecAttrApplicationTag as String: keyTag,
            kSecAttrKeyType as String: kSecAttrKeyTypeECSECPrimeRandom,
            kSecReturnRef as String: true
        ]

        var item: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &item)

        guard status == errSecSuccess,
            let privateKey = item as! SecKey?
        else {
            throw CertificateError.invalidKeyData
        }

        guard let publicKey = SecKeyCopyPublicKey(privateKey) else {
            throw CertificateError.invalidKeyData
        }

        return try createCSR(for: publicKey, config: config)
    }

    // MARK: - Private Methods

    private static func createRootCA(
        privateKey: P256.Signing.PrivateKey,
        config: CertificateConfig
    ) throws -> Certificate {
        let subject = try createDistinguishedName(from: config)

        let extensions = try Certificate.Extensions {
            BasicConstraints.isCertificateAuthority(maxPathLength: 1)
            KeyUsage(keyCertSign: true, cRLSign: true)
            SubjectKeyIdentifier(hash: Certificate.PublicKey(privateKey.publicKey))
        }

        let certificate = try Certificate(
            version: .v3,
            serialNumber: Certificate.SerialNumber(),
            publicKey: Certificate.PublicKey(privateKey.publicKey),
            notValidBefore: Date().addingTimeInterval(-5 * 60),  // 5 minutes ago for clock skew
            notValidAfter: Date().addingTimeInterval(
                TimeInterval(config.validityDays * 24 * 60 * 60)),
            issuer: subject,
            subject: subject,
            signatureAlgorithm: .ecdsaWithSHA256,
            extensions: extensions,
            issuerPrivateKey: Certificate.PrivateKey(privateKey)
        )

        return certificate
    }

    private static func createIntermediateCA(
        privateKey: P256.Signing.PrivateKey,
        config: CertificateConfig,
        issuerCertificate: Certificate,
        issuerPrivateKey: P256.Signing.PrivateKey
    ) throws -> Certificate {
        let subject = try createDistinguishedName(from: config)

        let extensions = try Certificate.Extensions {
            BasicConstraints.isCertificateAuthority(maxPathLength: 0)
            KeyUsage(keyCertSign: true, cRLSign: true)
            SubjectKeyIdentifier(hash: Certificate.PublicKey(privateKey.publicKey))
            AuthorityKeyIdentifier(
                keyIdentifier: ArraySlice(
                    Insecure.SHA1.hash(data: issuerPrivateKey.publicKey.x963Representation))
            )
        }

        let certificate = try Certificate(
            version: .v3,
            serialNumber: Certificate.SerialNumber(),
            publicKey: Certificate.PublicKey(privateKey.publicKey),
            notValidBefore: Date().addingTimeInterval(-5 * 60),  // 5 minutes ago for clock skew
            notValidAfter: Date().addingTimeInterval(
                TimeInterval(config.validityDays * 24 * 60 * 60)),
            issuer: issuerCertificate.subject,
            subject: subject,
            signatureAlgorithm: .ecdsaWithSHA256,
            extensions: extensions,
            issuerPrivateKey: Certificate.PrivateKey(issuerPrivateKey)
        )

        return certificate
    }

    private static func createEndEntityCertificate(
        publicKey: SecKey,
        config: CertificateConfig,
        issuerCertificate: Certificate,
        issuerPrivateKey: P256.Signing.PrivateKey
    ) throws -> Certificate {
        guard let publicKeyData = SecKeyCopyExternalRepresentation(publicKey, nil) as Data? else {
            throw CertificateError.invalidKeyData
        }

        let p256PublicKey = try parseSecKeyPublicKey(publicKeyData)

        let subject = try createDistinguishedName(from: config)

        let extensions = try Certificate.Extensions {
            BasicConstraints.notCertificateAuthority
            KeyUsage(digitalSignature: true)
            try ExtendedKeyUsage([.emailProtection])
            SubjectKeyIdentifier(hash: Certificate.PublicKey(p256PublicKey))
            AuthorityKeyIdentifier(
                keyIdentifier: ArraySlice(
                    Insecure.SHA1.hash(data: issuerPrivateKey.publicKey.x963Representation))
            )
        }

        let certificate = try Certificate(
            version: .v3,
            serialNumber: Certificate.SerialNumber(),
            publicKey: Certificate.PublicKey(p256PublicKey),
            notValidBefore: Date().addingTimeInterval(-5 * 60),  // 5 minutes ago for clock skew
            notValidAfter: Date().addingTimeInterval(
                TimeInterval(config.validityDays * 24 * 60 * 60)),
            issuer: issuerCertificate.subject,
            subject: subject,
            signatureAlgorithm: .ecdsaWithSHA256,
            extensions: extensions,
            issuerPrivateKey: Certificate.PrivateKey(issuerPrivateKey)
        )

        return certificate
    }

    private static func createDistinguishedName(from config: CertificateConfig) throws
        -> DistinguishedName
    {
        try DistinguishedName {
            CommonName(config.commonName)
            OrganizationName(config.organization)
            OrganizationalUnitName(config.organizationalUnit)
            CountryName(config.country)
            StateOrProvinceName(config.state)
            LocalityName(config.locality)
            if let email = config.emailAddress {
                EmailAddress(email)
            }
        }
    }

    private static func parseSecKeyPublicKey(_ data: Data) throws -> P256.Signing.PublicKey {
        // SecKey exports P-256 public keys in X9.63 format (65 bytes: 0x04 || x || y)
        if data.count == 65 && data[0] == 0x04 {
            // It's an uncompressed point, which is what we expect
            return try P256.Signing.PublicKey(x963Representation: data)
        } else {
            throw CertificateError.unsupportedKeyFormat
        }
    }

    // Manually creates a CSR for Secure Enclave keys where we don't have private key access
    private static func createCSRManually(
        publicKey: P256.Signing.PublicKey,
        privateKey: SecKey,
        config: CertificateConfig
    ) throws -> String {
        // Try using the X509 CertificateSigningRequest directly
        // Since we can't access the private key material, we'll need to create it differently

        // First, create a temporary P256 key pair for testing
        let tempPrivateKey = P256.Signing.PrivateKey()

        // Create the CSR with the temp key but our public key's data
        let csr = try CertificateSigningRequest(
            version: .v1,
            subject: try createDistinguishedName(from: config),
            privateKey: Certificate.PrivateKey(tempPrivateKey),
            attributes: CertificateSigningRequest.Attributes(),
            signatureAlgorithm: .ecdsaWithSHA256
        )

        // Now we need to replace the public key in the CSR with our actual public key
        // and re-sign with our secure enclave key

        let subject = try createDistinguishedName(from: config)

        // Create the CertificationRequestInfo
        var infoSerializer = DER.Serializer()
        try infoSerializer.appendConstructedNode(identifier: .sequence) { coder in
            try coder.serialize(0)  // version
            try coder.serialize(subject)

            // SubjectPublicKeyInfo
            try coder.appendConstructedNode(identifier: .sequence) { spkiCoder in
                try spkiCoder.appendConstructedNode(identifier: .sequence) { algCoder in
                    try algCoder.serialize(
                        try ASN1ObjectIdentifier(
                            elements: [1, 2, 840, 10045, 2, 1]))  // ecPublicKey
                    try algCoder.serialize(
                        try ASN1ObjectIdentifier(
                            elements: [1, 2, 840, 10045, 3, 1, 7]))  // secp256r1
                }
                try spkiCoder.serialize(
                    ASN1BitString(bytes: ArraySlice(publicKey.x963Representation)))
            }

            // Attributes (empty context-specific tag [0])
            coder.appendConstructedNode(
                identifier: .init(tagWithNumber: 0, tagClass: .contextSpecific)
            ) { _ in }
        }

        let infoData = Data(infoSerializer.serializedBytes)

        // Sign the CertificationRequestInfo
        let signature = try signData(infoData, with: privateKey)

        // Build the complete CSR manually using raw bytes
        // Structure: SEQUENCE { certificationRequestInfo, signatureAlgorithm, signature }
        var finalDER = Data()

        // Prepare signature algorithm
        var algSerializer = DER.Serializer()
        try algSerializer.appendConstructedNode(identifier: .sequence) { algCoder in
            try algCoder.serialize(
                try ASN1ObjectIdentifier(elements: [1, 2, 840, 10045, 4, 3, 2]))  // ecdsaWithSHA256
        }
        let algData = Data(algSerializer.serializedBytes)

        // Prepare signature
        var sigSerializer = DER.Serializer()
        try sigSerializer.serialize(ASN1BitString(bytes: ArraySlice(signature)))
        let sigData = Data(sigSerializer.serializedBytes)

        // Calculate total length
        let totalLength = infoData.count + algData.count + sigData.count

        // Build outer SEQUENCE
        finalDER.append(0x30)  // SEQUENCE tag

        // Encode length
        if totalLength < 128 {
            finalDER.append(UInt8(totalLength))
        } else if totalLength < 256 {
            finalDER.append(0x81)
            finalDER.append(UInt8(totalLength))
        } else {
            finalDER.append(0x82)
            finalDER.append(UInt8((totalLength >> 8) & 0xFF))
            finalDER.append(UInt8(totalLength & 0xFF))
        }

        // Append the three components
        finalDER.append(infoData)
        finalDER.append(algData)
        finalDER.append(sigData)

        let pemDocument = PEMDocument(type: "CERTIFICATE REQUEST", derBytes: Array(finalDER))

        return pemDocument.pemString
    }

    // Signs data with a SecKey private key
    private static func signData(_ data: Data, with privateKey: SecKey) throws -> Data {
        let algorithm = SecKeyAlgorithm.ecdsaSignatureMessageX962SHA256

        guard SecKeyIsAlgorithmSupported(privateKey, .sign, algorithm) else {
            throw CertificateError.unsupportedAlgorithm
        }

        var error: Unmanaged<CFError>?
        guard
            let signature = SecKeyCreateSignature(
                privateKey,
                algorithm,
                data as CFData,
                &error
            ) as Data?
        else {
            if let error = error?.takeRetainedValue() {
                throw CertificateError.signingFailed(error.localizedDescription)
            }
            throw CertificateError.signingFailed("Unknown signing error")
        }

        return signature
    }

    // Finds the private key corresponding to a public key
    private static func findPrivateKey(for publicKey: SecKey) throws -> SecKey? {
        guard let publicKeyData = SecKeyCopyExternalRepresentation(publicKey, nil) as Data? else {
            throw CertificateError.invalidKeyData
        }

        let query: [String: Any] = [
            kSecClass as String: kSecClassKey,
            kSecAttrKeyType as String: kSecAttrKeyTypeECSECPrimeRandom,
            kSecReturnRef as String: true,
            kSecMatchLimit as String: kSecMatchLimitAll
        ]

        var items: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &items)

        guard status == errSecSuccess,
            let keys = items as? [SecKey]
        else {
            return nil
        }

        for privateKey in keys {
            if let candidatePublicKey = SecKeyCopyPublicKey(privateKey),
                let candidatePublicKeyData = SecKeyCopyExternalRepresentation(
                    candidatePublicKey, nil) as Data?,
                candidatePublicKeyData == publicKeyData
            {
                return privateKey
            }
        }

        return nil
    }
}
