//
//  CertificateManager.swift
//  C2PA
//
//  Certificate creation and management for C2PA signing
//

import Foundation
import Security
import X509
import SwiftASN1
import Crypto
import class CertificateSigningRequest.CertificateSigningRequest

@available(iOS 13.0, macOS 10.15, *)
public class CertificateManager {
    
    public enum CertificateError: LocalizedError {
        case keyGenerationFailed
        case certificateCreationFailed(String)
        case invalidKeyData
        case encodingFailed
        case unsupportedAlgorithm
        case unsupportedKeyFormat
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
            case .unsupportedKeyFormat:
                return "Unsupported key format"
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
    
    public struct CertificateChain {
        public let endEntityCertificate: Certificate
        public let intermediateCertificate: Certificate
        public let rootCertificate: Certificate
        
        public func pemChain() throws -> String {
            let endEntity = try endEntityCertificate.serializeAsPEM().pemString
            let intermediate = try intermediateCertificate.serializeAsPEM().pemString
            let root = try rootCertificate.serializeAsPEM().pemString
            return endEntity + "\n" + intermediate + "\n" + root
        }
    }
    
    // MARK: - Public Methods
    
    /// Creates a self-signed certificate chain suitable for C2PA signing
    public static func createSelfSignedCertificateChain(
        for publicKey: SecKey,
        config: CertificateConfig
    ) throws -> String {
        // Generate key pairs for CA certificates
        let rootKeyPair = P256.Signing.PrivateKey()
        let intermediateKeyPair = P256.Signing.PrivateKey()
        
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
        let endEntity = try endEntityCert.serializeAsPEM().pemString
        let intermediate = try intermediateCert.serializeAsPEM().pemString  
        let root = try rootCert.serializeAsPEM().pemString
        return endEntity + "\n" + intermediate + "\n" + root
    }
    
    /// Creates a Certificate Signing Request (CSR) for a secure enclave key
    /// 
    /// Uses the CertificateSigningRequest library which supports SecKey and Secure Enclave
    public static func createCSR(
        for publicKey: SecKey,
        config: CertificateConfig
    ) throws -> String {
        // Find the corresponding private key
        guard let privateKey = try findPrivateKey(for: publicKey) else {
            throw CertificateError.invalidKeyData
        }
        
        // Get public key data for the CSR library
        guard let publicKeyData = SecKeyCopyExternalRepresentation(publicKey, nil) as Data? else {
            throw CertificateError.invalidKeyData
        }
        
        // Create the CSR using the CertificateSigningRequest library
        let csr = CertificateSigningRequest(
            commonName: config.commonName,
            organizationName: config.organization,
            organizationUnitName: config.organizationalUnit,
            countryName: config.country,
            stateOrProvinceName: config.state,
            localityName: config.locality,
            emailAddress: config.emailAddress,
            keyAlgorithm: .ec(signatureType: .sha256)
        )
        
        // Build the CSR with our keys
        // The library expects public key bits and private key
        guard let csrString = csr.buildCSRAndReturnString(publicKeyData, privateKey: privateKey) else {
            throw CertificateError.signingFailed("Failed to build CSR")
        }
        
        return csrString
    }
    
    /// Creates a CSR for a keychain key by tag
    public static func createCSR(
        keyTag: String,
        config: CertificateConfig
    ) throws -> String {
        // Retrieve the key from keychain
        let query: [String: Any] = [
            kSecClass as String: kSecClassKey,
            kSecAttrApplicationTag as String: keyTag,
            kSecAttrKeyType as String: kSecAttrKeyTypeECSECPrimeRandom,
            kSecReturnRef as String: true
        ]
        
        var item: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &item)
        
        guard status == errSecSuccess,
              let privateKey = item as! SecKey? else {
            throw CertificateError.invalidKeyData
        }
        
        // Get the public key
        guard let publicKey = SecKeyCopyPublicKey(privateKey) else {
            throw CertificateError.invalidKeyData
        }
        
        return try createCSR(for: publicKey, config: config)
    }
    
    /// Convenience method for web service CSR creation
    public static func createCSRForWebService(
        keyTag: String,
        organization: String,
        organizationalUnit: String,
        country: String,
        state: String,
        locality: String,
        emailAddress: String? = nil
    ) throws -> String {
        let config = CertificateConfig(
            commonName: "C2PA Content Signer",
            organization: organization,
            organizationalUnit: organizationalUnit,
            country: country,
            state: state,
            locality: locality,
            emailAddress: emailAddress
        )
        
        return try createCSR(keyTag: keyTag, config: config)
    }
    
    /// Creates a CSR using a regular P256 private key (the simple way, like in your example)
    /// This is for when you have a standard P256 key, not a Secure Enclave key
    public static func createCSRSimple(
        privateKey: P256.Signing.PrivateKey,
        config: CertificateConfig,
        subjectAlternativeNames: [String] = []
    ) throws -> String {
        // Create the subject distinguished name
        let subject = try createDistinguishedName(from: config)
        
        // Create the private key wrapper
        let privateKeyCertificate = Certificate.PrivateKey(privateKey)
        
        // Create attributes
        var attributes = X509.CertificateSigningRequest.Attributes()
        
        // Add Subject Alternative Names if provided
        if !subjectAlternativeNames.isEmpty {
            let extensions = try Certificate.Extensions {
                SubjectAlternativeNames(subjectAlternativeNames.map { .dnsName($0) })
            }
            let extensionRequest = ExtensionRequest(extensions: extensions)
            attributes = try X509.CertificateSigningRequest.Attributes([.init(extensionRequest)])
        }
        
        // Create the CSR - this is the simple way!
        let csr = try X509.CertificateSigningRequest(
            version: .v1,
            subject: subject,
            privateKey: privateKeyCertificate,
            attributes: attributes,
            signatureAlgorithm: .ecdsaWithSHA256
        )
        
        // Verify the signature
        if !csr.publicKey.isValidSignature(csr.signature, for: csr) {
            throw CertificateError.signingFailed("CSR signature verification failed")
        }
        
        // Serialize to PEM
        return try csr.serializeAsPEM().pemString
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
            SubjectKeyIdentifier(
                keyIdentifier: ArraySlice(Crypto.SHA256.hash(data: privateKey.publicKey.rawRepresentation))
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
            SubjectKeyIdentifier(
                keyIdentifier: ArraySlice(Crypto.SHA256.hash(data: privateKey.publicKey.rawRepresentation))
            )
            AuthorityKeyIdentifier(
                keyIdentifier: ArraySlice(Crypto.SHA256.hash(data: issuerPrivateKey.publicKey.rawRepresentation))
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
            BasicConstraints.notCertificateAuthority
            KeyUsage(digitalSignature: true)
            try ExtendedKeyUsage([.emailProtection])
            SubjectKeyIdentifier(
                keyIdentifier: ArraySlice(Crypto.SHA256.hash(data: p256PublicKey.rawRepresentation))
            )
            AuthorityKeyIdentifier(
                keyIdentifier: ArraySlice(Crypto.SHA256.hash(data: issuerPrivateKey.publicKey.rawRepresentation))
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
        return try DistinguishedName {
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
        // We need to convert this to a P256.Signing.PublicKey
        
        if data.count == 65 && data[0] == 0x04 {
            // It's an uncompressed point, which is what we expect
            return try P256.Signing.PublicKey(x963Representation: data)
        } else {
            throw CertificateError.unsupportedKeyFormat
        }
    }
    
    
    private static func createCSRAttributes(config: CertificateConfig) throws -> X509.CertificateSigningRequest.Attributes {
        // For now, return empty attributes
        // In a full implementation, you might add challenge password, unstructured name, etc.
        return X509.CertificateSigningRequest.Attributes()
    }
    
    /// Signs CSR data with the private key corresponding to the public key
    private static func signCSRData(_ data: Data, with publicKey: SecKey) throws -> Data {
        // Find the corresponding private key in the keychain
        // This assumes the private key is stored with the same tag as the public key
        guard let privateKey = try findPrivateKey(for: publicKey) else {
            throw CertificateError.invalidKeyData
        }
        
        // Sign the data
        let algorithm = SecKeyAlgorithm.ecdsaSignatureMessageX962SHA256
        
        guard SecKeyIsAlgorithmSupported(privateKey, .sign, algorithm) else {
            throw CertificateError.unsupportedAlgorithm
        }
        
        var error: Unmanaged<CFError>?
        guard let signature = SecKeyCreateSignature(
            privateKey,
            algorithm,
            data as CFData,
            &error
        ) as Data? else {
            if let error = error?.takeRetainedValue() {
                throw CertificateError.signingFailed(error.localizedDescription)
            }
            throw CertificateError.signingFailed("Unknown signing error")
        }
        
        return signature
    }
    
    /// Finds the private key corresponding to a public key
    private static func findPrivateKey(for publicKey: SecKey) throws -> SecKey? {
        // Export the public key to get its data for comparison
        guard let publicKeyData = SecKeyCopyExternalRepresentation(publicKey, nil) as Data? else {
            throw CertificateError.invalidKeyData
        }
        
        // Query all private keys and find the matching one
        let query: [String: Any] = [
            kSecClass as String: kSecClassKey,
            kSecAttrKeyType as String: kSecAttrKeyTypeECSECPrimeRandom,
            kSecReturnRef as String: true,
            kSecMatchLimit as String: kSecMatchLimitAll
        ]
        
        var items: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &items)
        
        guard status == errSecSuccess,
              let keys = items as? [SecKey] else {
            return nil
        }
        
        // Find the private key whose public key matches
        for privateKey in keys {
            if let candidatePublicKey = SecKeyCopyPublicKey(privateKey),
               let candidatePublicKeyData = SecKeyCopyExternalRepresentation(candidatePublicKey, nil) as Data?,
               candidatePublicKeyData == publicKeyData {
                return privateKey
            }
        }
        
        return nil
    }
    
    // CSR helper methods removed - would need proper ASN.1 implementation
}


