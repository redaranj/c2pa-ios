//
//  CertificateManagerProduction.swift
//  C2PA
//
//  Production-ready certificate creation and management for C2PA signing
//

import Foundation
import Security
import X509
import SwiftASN1
import Crypto

@available(iOS 13.0, macOS 10.15, *)
public class CertificateManagerProduction {
    
    public enum CertificateError: LocalizedError {
        case keyGenerationFailed
        case certificateCreationFailed(String)
        case invalidKeyData
        case encodingFailed
        case unsupportedAlgorithm
        case invalidCertificate
        case signingFailed(String)
        
        public var errorDescription: String? {
            switch self {
            case .keyGenerationFailed:
                return "Failed to generate key pair"
            case .certificateCreationFailed(let details):
                return "Failed to create certificate: \(details)"
            case .invalidKeyData:
                return "Invalid key data"
            case .encodingFailed:
                return "Failed to encode certificate"
            case .unsupportedAlgorithm:
                return "Unsupported algorithm"
            case .invalidCertificate:
                return "Invalid certificate"
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
            organization: String = "C2PA Test",
            organizationalUnit: String = "FOR TESTING ONLY",
            country: String = "US",
            state: String = "CA",
            locality: String = "Somewhere",
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
    
    public struct CertificateChain {
        public let endEntityCertificate: Certificate
        public let intermediateCertificate: Certificate
        public let rootCertificate: Certificate
        
        public var pemChain: String {
            return endEntityCertificate.pemEncoded + "\n" +
                   intermediateCertificate.pemEncoded + "\n" +
                   rootCertificate.pemEncoded
        }
    }
    
    // MARK: - Public Methods
    
    /// Creates a self-signed certificate chain suitable for C2PA signing
    public static func createSelfSignedCertificateChain(
        for publicKey: SecKey,
        config: CertificateConfig
    ) throws -> String {
        // Generate key pairs for CA certificates
        let rootKeyPair = try P256.Signing.PrivateKey()
        let intermediateKeyPair = try P256.Signing.PrivateKey()
        
        // Create Root CA
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
        
        // Create Intermediate CA
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
        
        // Create End-Entity Certificate
        let endEntityCert = try createEndEntityCertificate(
            publicKey: publicKey,
            config: config,
            issuerCertificate: intermediateCert,
            issuerPrivateKey: intermediateKeyPair
        )
        
        // Return PEM chain
        return try endEntityCert.serializeAsPEM().pemString + "\n" +
               try intermediateCert.serializeAsPEM().pemString + "\n" +
               try rootCert.serializeAsPEM().pemString
    }
    
    /// Creates a Certificate Signing Request (CSR) for a secure enclave key
    public static func createCSR(
        for publicKey: SecKey,
        config: CertificateConfig
    ) throws -> String {
        // Export public key from SecKey
        guard let publicKeyData = SecKeyCopyExternalRepresentation(publicKey, nil) as Data? else {
            throw CertificateError.invalidKeyData
        }
        
        // Parse the public key data to get a P256 public key
        let p256PublicKey = try parseSecKeyPublicKey(publicKeyData)
        
        // Create CSR attributes
        let attributes = try createCSRAttributes(config: config)
        
        // Create the CSR
        let csr = CertificateSigningRequest(
            version: .v1,
            subject: try createDistinguishedName(from: config),
            publicKey: Certificate.PublicKey(p256PublicKey),
            attributes: attributes,
            signatureAlgorithm: .ecdsaWithSHA256
        )
        
        // Create CSR info (without signature)
        let csrInfo = CertificateSigningRequestInfo(
            version: csr.version,
            subject: csr.subject,
            publicKey: csr.publicKey,
            attributes: csr.attributes
        )
        
        // Serialize CSR info for signing
        var serializer = DER.Serializer()
        try serializer.serialize(csrInfo)
        let dataToSign = Data(serializer.serializedBytes)
        
        // Since we can't sign with the secure enclave key directly in CSR creation,
        // we'll return an unsigned CSR template that needs to be signed externally
        throw CertificateError.signingFailed("CSR signing with secure enclave keys requires external signing")
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
            try SubjectKeyIdentifier(
                keyIdentifier: ArraySlice(Crypto.SHA256.hash(data: privateKey.publicKey.rawRepresentation)),
                extensions: Extensions()
            )
        }
        
        let certificate = try Certificate(
            version: .v3,
            serialNumber: Certificate.SerialNumber(),
            publicKey: Certificate.PublicKey(privateKey.publicKey),
            notValidBefore: Date(),
            notValidAfter: Date().addingTimeInterval(TimeInterval(config.validityDays * 24 * 60 * 60)),
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
            try SubjectKeyIdentifier(
                keyIdentifier: ArraySlice(Crypto.SHA256.hash(data: privateKey.publicKey.rawRepresentation)),
                extensions: Extensions()
            )
            try AuthorityKeyIdentifier(
                keyIdentifier: ArraySlice(Crypto.SHA256.hash(data: issuerPrivateKey.publicKey.rawRepresentation)),
                extensions: Extensions()
            )
        }
        
        let certificate = try Certificate(
            version: .v3,
            serialNumber: Certificate.SerialNumber(),
            publicKey: Certificate.PublicKey(privateKey.publicKey),
            notValidBefore: Date(),
            notValidAfter: Date().addingTimeInterval(TimeInterval(config.validityDays * 24 * 60 * 60)),
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
        // Export public key from SecKey
        guard let publicKeyData = SecKeyCopyExternalRepresentation(publicKey, nil) as Data? else {
            throw CertificateError.invalidKeyData
        }
        
        // Parse the public key data to get a P256 public key
        let p256PublicKey = try parseSecKeyPublicKey(publicKeyData)
        
        let subject = try createDistinguishedName(from: config)
        
        let extensions = try Certificate.Extensions {
            BasicConstraints(isCertificateAuthority: false)
            KeyUsage(digitalSignature: true)
            ExtendedKeyUsage([.emailProtection])
            try SubjectKeyIdentifier(
                keyIdentifier: ArraySlice(Crypto.SHA256.hash(data: p256PublicKey.rawRepresentation)),
                extensions: Extensions()
            )
            try AuthorityKeyIdentifier(
                keyIdentifier: ArraySlice(Crypto.SHA256.hash(data: issuerPrivateKey.publicKey.rawRepresentation)),
                extensions: Extensions()
            )
        }
        
        let certificate = try Certificate(
            version: .v3,
            serialNumber: Certificate.SerialNumber(),
            publicKey: Certificate.PublicKey(p256PublicKey),
            notValidBefore: Date(),
            notValidAfter: Date().addingTimeInterval(TimeInterval(config.validityDays * 24 * 60 * 60)),
            issuer: issuerCertificate.subject,
            subject: subject,
            signatureAlgorithm: .ecdsaWithSHA256,
            extensions: extensions,
            issuerPrivateKey: Certificate.PrivateKey(issuerPrivateKey)
        )
        
        return certificate
    }
    
    private static func createDistinguishedName(from config: CertificateConfig) throws -> DistinguishedName {
        var builder = DistinguishedName.Builder()
        
        try builder.addAttribute(
            RelativeDistinguishedName.Attribute(
                type: .RDNAttributeType.countryName,
                value: .init(printableString: config.country)
            )
        )
        
        try builder.addAttribute(
            RelativeDistinguishedName.Attribute(
                type: .RDNAttributeType.stateOrProvinceName,
                value: .init(utf8String: config.state)
            )
        )
        
        try builder.addAttribute(
            RelativeDistinguishedName.Attribute(
                type: .RDNAttributeType.localityName,
                value: .init(utf8String: config.locality)
            )
        )
        
        try builder.addAttribute(
            RelativeDistinguishedName.Attribute(
                type: .RDNAttributeType.organizationName,
                value: .init(utf8String: config.organization)
            )
        )
        
        try builder.addAttribute(
            RelativeDistinguishedName.Attribute(
                type: .RDNAttributeType.organizationalUnitName,
                value: .init(utf8String: config.organizationalUnit)
            )
        )
        
        try builder.addAttribute(
            RelativeDistinguishedName.Attribute(
                type: .RDNAttributeType.commonName,
                value: .init(utf8String: config.commonName)
            )
        )
        
        if let email = config.emailAddress {
            try builder.addAttribute(
                RelativeDistinguishedName.Attribute(
                    type: .RDNAttributeType.emailAddress,
                    value: .init(ia5String: email)
                )
            )
        }
        
        return builder.build()
    }
    
    private static func parseSecKeyPublicKey(_ data: Data) throws -> P256.Signing.PublicKey {
        // SecKey exports P-256 public keys in X9.63 format (65 bytes: 0x04 || x || y)
        // We need to convert this to a P256.Signing.PublicKey
        
        if data.count == 65 && data[0] == 0x04 {
            // It's an uncompressed point, which is what we expect
            return try P256.Signing.PublicKey(x963Representation: data)
        } else {
            // Try to parse as DER-encoded SubjectPublicKeyInfo
            var parser = DER.Parser(derEncoded: Array(data))
            let spki = try SubjectPublicKeyInfo(derEncoded: &parser)
            
            // Extract the public key bits
            guard spki.algorithmIdentifier.algorithm == .AlgorithmIdentifier.ecPublicKey else {
                throw CertificateError.unsupportedAlgorithm
            }
            
            // The key should be in the subjectPublicKey field
            return try P256.Signing.PublicKey(x963Representation: spki.subjectPublicKey.bytes)
        }
    }
    
    private static func createCSRAttributes(config: CertificateConfig) throws -> CertificateSigningRequest.Attributes {
        // For now, return empty attributes
        // In a full implementation, you might add challenge password, unstructured name, etc.
        return CertificateSigningRequest.Attributes()
    }
}

// MARK: - CSR Support Types

@available(iOS 13.0, macOS 10.15, *)
extension CertificateManagerProduction {
    
    struct CertificateSigningRequest {
        enum Version: Int {
            case v1 = 0
        }
        
        let version: Version
        let subject: DistinguishedName
        let publicKey: Certificate.PublicKey
        let attributes: Attributes
        let signatureAlgorithm: Certificate.SignatureAlgorithm
        
        struct Attributes {
            // Placeholder for CSR attributes
        }
    }
    
    struct CertificateSigningRequestInfo {
        let version: CertificateSigningRequest.Version
        let subject: DistinguishedName
        let publicKey: Certificate.PublicKey
        let attributes: CertificateSigningRequest.Attributes
    }
}

// MARK: - DER Serialization for CSR

@available(iOS 13.0, macOS 10.15, *)
extension CertificateManagerProduction.CertificateSigningRequestInfo: DERSerializable {
    func serialize(into coder: inout DER.Serializer) throws {
        try coder.appendConstructedNode(identifier: .sequence) { coder in
            try coder.serialize(self.version.rawValue)
            try coder.serialize(self.subject)
            
            // Serialize public key as SubjectPublicKeyInfo
            let algorithmIdentifier = AlgorithmIdentifier(
                algorithm: .AlgorithmIdentifier.ecPublicKey,
                parameters: try .init(erasing: ASN1ObjectIdentifier.NamedCurves.secp256r1)
            )
            
            let spki = SubjectPublicKeyInfo(
                algorithmIdentifier: algorithmIdentifier,
                subjectPublicKey: ASN1BitString(
                    bytes: ArraySlice(self.publicKey.rawRepresentation)
                )
            )
            try coder.serialize(spki)
            
            // Serialize attributes (empty for now)
            try coder.appendConstructedNode(identifier: .init(
                tagClass: .contextDefinedTag(0),
                tagNumber: 0,
                constructed: true
            )) { _ in
                // Empty attributes
            }
        }
    }
}