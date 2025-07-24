//
//  CertificateManager.swift
//  C2PA
//
//  Certificate creation and management for C2PA signing
//

import Foundation
import Security
import CommonCrypto

@available(iOS 13.0, macOS 10.15, *)
public class CertificateManager {
    
    public enum CertificateError: LocalizedError {
        case keyGenerationFailed
        case certificateCreationFailed(String)
        case invalidKeyData
        case encodingFailed
        case unsupportedAlgorithm
        
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
    
    public struct Certificate {
        public let certificatePEM: String
        public let privateKey: SecKey?
        
        init(certificatePEM: String, privateKey: SecKey? = nil) {
            self.certificatePEM = certificatePEM
            self.privateKey = privateKey
        }
    }
    
    // MARK: - Public Methods
    
    /// Creates a self-signed certificate chain suitable for C2PA signing
    /// Returns the full certificate chain in PEM format
    public static func createSelfSignedCertificateChain(
        for publicKey: SecKey,
        config: CertificateConfig
    ) throws -> String {
        // Create Root CA
        let rootConfig = CertificateConfig(
            commonName: "Root CA",
            organization: config.organization,
            organizationalUnit: config.organizationalUnit,
            country: config.country,
            state: config.state,
            locality: config.locality,
            validityDays: config.validityDays * 10 // Root CA valid for 10x longer
        )
        let rootCA = try createRootCA(config: rootConfig)
        
        // Create Intermediate CA
        let intermediateConfig = CertificateConfig(
            commonName: "Intermediate CA",
            organization: config.organization,
            organizationalUnit: config.organizationalUnit,
            country: config.country,
            state: config.state,
            locality: config.locality,
            validityDays: config.validityDays * 5 // Intermediate valid for 5x longer
        )
        let intermediateCA = try createIntermediateCA(
            config: intermediateConfig,
            signingCert: rootCA
        )
        
        // Create End-Entity Certificate
        let endEntityCert = try createEndEntityCertificate(
            publicKey: publicKey,
            config: config,
            signingCert: intermediateCA
        )
        
        // Combine certificates into chain (end-entity first, then intermediate, then root)
        return endEntityCert.certificatePEM + "\n" + 
               intermediateCA.certificatePEM + "\n" + 
               rootCA.certificatePEM
    }
    
    /// Creates a Certificate Signing Request (CSR) for a secure enclave key
    public static func createCSR(
        for publicKey: SecKey,
        config: CertificateConfig
    ) throws -> String {
        // Export public key
        guard let publicKeyData = SecKeyCopyExternalRepresentation(publicKey, nil) as Data? else {
            throw CertificateError.invalidKeyData
        }
        
        // Create subject name
        let subject = createX509Name(from: config)
        
        // Build CSR structure
        let csrData = try buildCSR(
            publicKeyData: publicKeyData,
            subject: subject,
            algorithm: .ecdsaWithSHA256
        )
        
        // Convert to PEM
        let pemCSR = csrData.pemEncoded(withLabel: "CERTIFICATE REQUEST")
        return pemCSR
    }
    
    // MARK: - Private Methods
    
    private static func createRootCA(config: CertificateConfig) throws -> Certificate {
        // Generate key pair for Root CA
        guard let keyPair = generateKeyPair() else {
            throw CertificateError.keyGenerationFailed
        }
        
        let certData = try createX509Certificate(
            publicKey: keyPair.publicKey,
            privateKey: keyPair.privateKey,
            subject: config,
            issuer: config, // Self-signed
            isCA: true,
            pathLenConstraint: 1,
            keyUsage: [.keyCertSign, .cRLSign],
            extendedKeyUsage: nil
        )
        
        let pemCert = certData.pemEncoded(withLabel: "CERTIFICATE")
        return Certificate(certificatePEM: pemCert, privateKey: keyPair.privateKey)
    }
    
    private static func createIntermediateCA(
        config: CertificateConfig,
        signingCert: Certificate
    ) throws -> Certificate {
        // Generate key pair for Intermediate CA
        guard let keyPair = generateKeyPair() else {
            throw CertificateError.keyGenerationFailed
        }
        
        guard let signingKey = signingCert.privateKey else {
            throw CertificateError.invalidKeyData
        }
        
        // Parse issuer certificate to get issuer name
        let issuerConfig = CertificateConfig(
            commonName: "Root CA",
            organization: config.organization,
            organizationalUnit: config.organizationalUnit,
            country: config.country,
            state: config.state,
            locality: config.locality
        )
        
        let certData = try createX509Certificate(
            publicKey: keyPair.publicKey,
            privateKey: signingKey, // Signed by root
            subject: config,
            issuer: issuerConfig,
            isCA: true,
            pathLenConstraint: 0,
            keyUsage: [.keyCertSign, .cRLSign],
            extendedKeyUsage: nil
        )
        
        let pemCert = certData.pemEncoded(withLabel: "CERTIFICATE")
        return Certificate(certificatePEM: pemCert, privateKey: keyPair.privateKey)
    }
    
    private static func createEndEntityCertificate(
        publicKey: SecKey,
        config: CertificateConfig,
        signingCert: Certificate
    ) throws -> Certificate {
        guard let signingKey = signingCert.privateKey else {
            throw CertificateError.invalidKeyData
        }
        
        // Parse issuer certificate to get issuer name
        let issuerConfig = CertificateConfig(
            commonName: "Intermediate CA",
            organization: config.organization,
            organizationalUnit: config.organizationalUnit,
            country: config.country,
            state: config.state,
            locality: config.locality
        )
        
        let certData = try createX509Certificate(
            publicKey: publicKey,
            privateKey: signingKey, // Signed by intermediate
            subject: config,
            issuer: issuerConfig,
            isCA: false,
            pathLenConstraint: nil,
            keyUsage: [.digitalSignature],
            extendedKeyUsage: [.emailProtection]
        )
        
        let pemCert = certData.pemEncoded(withLabel: "CERTIFICATE")
        return Certificate(certificatePEM: pemCert, privateKey: nil)
    }
    
    // MARK: - Key Generation
    
    private static func generateKeyPair() -> (publicKey: SecKey, privateKey: SecKey)? {
        let attributes: [String: Any] = [
            kSecAttrKeyType as String: kSecAttrKeyTypeECSECPrimeRandom,
            kSecAttrKeySizeInBits as String: 256,
            kSecPrivateKeyAttrs as String: [
                kSecAttrIsPermanent as String: false,
                kSecAttrApplicationTag as String: UUID().uuidString
            ]
        ]
        
        var error: Unmanaged<CFError>?
        guard let privateKey = SecKeyCreateRandomKey(attributes as CFDictionary, &error),
              let publicKey = SecKeyCopyPublicKey(privateKey) else {
            return nil
        }
        
        return (publicKey, privateKey)
    }
    
    // MARK: - X.509 Certificate Creation
    
    private enum KeyUsage {
        case digitalSignature
        case keyCertSign
        case cRLSign
    }
    
    private enum ExtendedKeyUsage {
        case emailProtection
    }
    
    private static func createX509Certificate(
        publicKey: SecKey,
        privateKey: SecKey,
        subject: CertificateConfig,
        issuer: CertificateConfig,
        isCA: Bool,
        pathLenConstraint: Int?,
        keyUsage: [KeyUsage],
        extendedKeyUsage: [ExtendedKeyUsage]?
    ) throws -> Data {
        // This is a simplified implementation that creates a basic certificate structure
        // In a production implementation, you would use a proper ASN.1 library
        
        // For now, we'll create a basic self-signed certificate
        // Note: This is a placeholder implementation that needs proper ASN.1 encoding
        
        // Export public key
        guard let publicKeyData = SecKeyCopyExternalRepresentation(publicKey, nil) as Data? else {
            throw CertificateError.invalidKeyData
        }
        
        // Create certificate data (simplified)
        var certData = Data()
        
        // Add certificate version (v3)
        certData.append(contentsOf: [0x02, 0x01, 0x02]) // version 3
        
        // Add serial number
        let serialNumber = Data((0..<20).map { _ in UInt8.random(in: 0...255) })
        certData.append(contentsOf: [0x02, 0x14]) // INTEGER, length 20
        certData.append(serialNumber)
        
        // Add signature algorithm (ecdsaWithSHA256)
        certData.append(contentsOf: [0x30, 0x0a, 0x06, 0x08, 0x2a, 0x86, 0x48, 0xce, 0x3d, 0x04, 0x03, 0x02])
        
        // Add issuer name
        let issuerName = createX509Name(from: issuer)
        certData.append(issuerName)
        
        // Add validity period
        let validity = createValidityPeriod(days: subject.validityDays)
        certData.append(validity)
        
        // Add subject name
        let subjectName = createX509Name(from: subject)
        certData.append(subjectName)
        
        // Add public key info
        certData.append(publicKeyData)
        
        // Add extensions (basic constraints, key usage, etc.)
        let extensions = createExtensions(
            isCA: isCA,
            pathLenConstraint: pathLenConstraint,
            keyUsage: keyUsage,
            extendedKeyUsage: extendedKeyUsage
        )
        certData.append(extensions)
        
        // Sign the certificate
        let signature = try signData(certData, with: privateKey)
        certData.append(signature)
        
        return certData
    }
    
    private static func createX509Name(from config: CertificateConfig) -> Data {
        // Create X.509 Distinguished Name
        // This is a simplified version - proper implementation would use ASN.1 encoding
        var name = Data()
        
        // Add country
        name.append(contentsOf: [0x31, 0x0b, 0x30, 0x09, 0x06, 0x03, 0x55, 0x04, 0x06, 0x13, 0x02])
        name.append(config.country.data(using: .utf8)!)
        
        // Add state
        name.append(contentsOf: [0x31, 0x0b, 0x30, 0x09, 0x06, 0x03, 0x55, 0x04, 0x08, 0x13, 0x02])
        name.append(config.state.data(using: .utf8)!)
        
        // Add locality
        name.append(contentsOf: [0x31, 0x12, 0x30, 0x10, 0x06, 0x03, 0x55, 0x04, 0x07, 0x13, 0x09])
        name.append(config.locality.data(using: .utf8)!)
        
        // Add organization
        name.append(contentsOf: [0x31, 0x1a, 0x30, 0x18, 0x06, 0x03, 0x55, 0x04, 0x0a, 0x13, 0x11])
        name.append(config.organization.data(using: .utf8)!)
        
        // Add organizational unit
        name.append(contentsOf: [0x31, 0x19, 0x30, 0x17, 0x06, 0x03, 0x55, 0x04, 0x0b, 0x13, 0x10])
        name.append(config.organizationalUnit.data(using: .utf8)!)
        
        // Add common name
        name.append(contentsOf: [0x31, 0x14, 0x30, 0x12, 0x06, 0x03, 0x55, 0x04, 0x03, 0x13, 0x0b])
        name.append(config.commonName.data(using: .utf8)!)
        
        // Add email if present
        if let email = config.emailAddress {
            name.append(contentsOf: [0x31, 0x1e, 0x30, 0x1c, 0x06, 0x09, 0x2a, 0x86, 0x48, 0x86, 0xf7, 0x0d, 0x01, 0x09, 0x01, 0x13, 0x0f])
            name.append(email.data(using: .utf8)!)
        }
        
        return name
    }
    
    private static func createValidityPeriod(days: Int) -> Data {
        var validity = Data()
        
        let now = Date()
        let notBefore = now
        let notAfter = now.addingTimeInterval(TimeInterval(days * 24 * 60 * 60))
        
        // Add notBefore (simplified - should be proper ASN.1 time encoding)
        let formatter = DateFormatter()
        formatter.dateFormat = "yyMMddHHmmss'Z'"
        formatter.timeZone = TimeZone(identifier: "UTC")
        
        let notBeforeString = formatter.string(from: notBefore)
        validity.append(contentsOf: [0x17, 0x0d]) // UTCTime
        validity.append(notBeforeString.data(using: .ascii)!)
        
        let notAfterString = formatter.string(from: notAfter)
        validity.append(contentsOf: [0x17, 0x0d]) // UTCTime
        validity.append(notAfterString.data(using: .ascii)!)
        
        return validity
    }
    
    private static func createExtensions(
        isCA: Bool,
        pathLenConstraint: Int?,
        keyUsage: [KeyUsage],
        extendedKeyUsage: [ExtendedKeyUsage]?
    ) -> Data {
        var extensions = Data()
        
        // Basic Constraints
        if isCA {
            // Add basic constraints extension for CA
            extensions.append(contentsOf: [0x30, 0x0f, 0x06, 0x03, 0x55, 0x1d, 0x13, 0x01, 0x01, 0xff, 0x04, 0x05, 0x30, 0x03, 0x01, 0x01, 0xff])
        } else {
            // Add basic constraints extension for end-entity
            extensions.append(contentsOf: [0x30, 0x0c, 0x06, 0x03, 0x55, 0x1d, 0x13, 0x01, 0x01, 0xff, 0x04, 0x02, 0x30, 0x00])
        }
        
        // Key Usage
        var keyUsageBits: UInt8 = 0
        for usage in keyUsage {
            switch usage {
            case .digitalSignature:
                keyUsageBits |= 0x80
            case .keyCertSign:
                keyUsageBits |= 0x04
            case .cRLSign:
                keyUsageBits |= 0x02
            }
        }
        extensions.append(contentsOf: [0x30, 0x0e, 0x06, 0x03, 0x55, 0x1d, 0x0f, 0x01, 0x01, 0xff, 0x04, 0x04, 0x03, 0x02, keyUsageBits])
        
        // Extended Key Usage
        if let extKeyUsage = extendedKeyUsage {
            // Add extended key usage for email protection
            extensions.append(contentsOf: [0x30, 0x16, 0x06, 0x03, 0x55, 0x1d, 0x25, 0x01, 0x01, 0xff, 0x04, 0x0c, 0x30, 0x0a, 0x06, 0x08, 0x2b, 0x06, 0x01, 0x05, 0x05, 0x07, 0x03, 0x04])
        }
        
        return extensions
    }
    
    private static func signData(_ data: Data, with privateKey: SecKey) throws -> Data {
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
                throw CertificateError.certificateCreationFailed(error.localizedDescription)
            }
            throw CertificateError.certificateCreationFailed("Unknown error")
        }
        
        return signature
    }
    
    private static func buildCSR(
        publicKeyData: Data,
        subject: Data,
        algorithm: SignatureAlgorithm
    ) throws -> Data {
        // This is a simplified CSR structure
        // In production, use proper ASN.1 encoding
        var csr = Data()
        
        // Add version
        csr.append(contentsOf: [0x02, 0x01, 0x00]) // version 0
        
        // Add subject
        csr.append(subject)
        
        // Add public key
        csr.append(publicKeyData)
        
        // Add attributes (empty for now)
        csr.append(contentsOf: [0xa0, 0x00])
        
        return csr
    }
    
    private enum SignatureAlgorithm {
        case ecdsaWithSHA256
    }
}

// MARK: - Data Extension for PEM Encoding

extension Data {
    func pemEncoded(withLabel label: String) -> String {
        let base64 = self.base64EncodedString(options: [.lineLength64Characters, .endLineWithLineFeed])
        return "-----BEGIN \(label)-----\n\(base64)\n-----END \(label)-----"
    }
}