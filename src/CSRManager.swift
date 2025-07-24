//
//  CSRManager.swift
//  C2PA
//
//  Certificate Signing Request (CSR) generation for secure enclave keys
//

import Foundation
import Security
import CommonCrypto

@available(iOS 13.0, macOS 10.15, *)
public class CSRManager {
    
    public enum CSRError: LocalizedError {
        case invalidKeyData
        case encodingFailed
        case signingFailed(String)
        case invalidAlgorithm
        
        public var errorDescription: String? {
            switch self {
            case .invalidKeyData:
                return "Invalid key data"
            case .encodingFailed:
                return "Failed to encode CSR"
            case .signingFailed(let details):
                return "Failed to sign CSR: \(details)"
            case .invalidAlgorithm:
                return "Invalid or unsupported algorithm"
            }
        }
    }
    
    /// Configuration for CSR generation
    public struct CSRConfig {
        public let commonName: String
        public let organization: String?
        public let organizationalUnit: String?
        public let country: String?
        public let state: String?
        public let locality: String?
        public let emailAddress: String?
        
        public init(
            commonName: String,
            organization: String? = nil,
            organizationalUnit: String? = nil,
            country: String? = nil,
            state: String? = nil,
            locality: String? = nil,
            emailAddress: String? = nil
        ) {
            self.commonName = commonName
            self.organization = organization
            self.organizationalUnit = organizationalUnit
            self.country = country
            self.state = state
            self.locality = locality
            self.emailAddress = emailAddress
        }
    }
    
    /// Creates a Certificate Signing Request for a secure enclave key
    /// - Parameters:
    ///   - keyTag: The tag of the secure enclave key to use
    ///   - config: Configuration for the CSR
    /// - Returns: CSR in PEM format
    public static func createCSR(
        keyTag: String,
        config: CSRConfig
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
            throw CSRError.invalidKeyData
        }
        
        // Get the public key
        guard let publicKey = SecKeyCopyPublicKey(privateKey) else {
            throw CSRError.invalidKeyData
        }
        
        // Create the CSR
        return try createCSR(
            privateKey: privateKey,
            publicKey: publicKey,
            config: config
        )
    }
    
    /// Creates a Certificate Signing Request using existing key references
    /// - Parameters:
    ///   - privateKey: The private key (for signing)
    ///   - publicKey: The public key (to include in CSR)
    ///   - config: Configuration for the CSR
    /// - Returns: CSR in PEM format
    public static func createCSR(
        privateKey: SecKey,
        publicKey: SecKey,
        config: CSRConfig
    ) throws -> String {
        // Build the CSR structure
        let csrData = try buildCSR(
            publicKey: publicKey,
            config: config
        )
        
        // Sign the CSR
        let signedCSR = try signCSR(
            csrData: csrData,
            privateKey: privateKey
        )
        
        // Convert to PEM format
        let pemCSR = signedCSR.base64EncodedString(options: [.lineLength64Characters, .endLineWithLineFeed])
        return "-----BEGIN CERTIFICATE REQUEST-----\n\(pemCSR)\n-----END CERTIFICATE REQUEST-----"
    }
    
    // MARK: - Private Methods
    
    private static func buildCSR(
        publicKey: SecKey,
        config: CSRConfig
    ) throws -> Data {
        // Export public key
        guard let publicKeyData = SecKeyCopyExternalRepresentation(publicKey, nil) as Data? else {
            throw CSRError.invalidKeyData
        }
        
        // Build the CSR info structure (simplified ASN.1)
        var csrInfo = Data()
        
        // Version (0)
        csrInfo.append(Data([0xA0, 0x03, 0x02, 0x01, 0x00]))
        
        // Subject DN
        let subject = try encodeDistinguishedName(config: config)
        csrInfo.append(subject)
        
        // SubjectPublicKeyInfo
        let spki = try encodeSubjectPublicKeyInfo(publicKeyData: publicKeyData)
        csrInfo.append(spki)
        
        // Attributes (empty for now)
        csrInfo.append(Data([0xA0, 0x00]))
        
        // Wrap in SEQUENCE
        return wrapInSequence(csrInfo)
    }
    
    private static func encodeDistinguishedName(config: CSRConfig) throws -> Data {
        var attributes = [Data]()
        
        // Add attributes in order
        if let country = config.country {
            attributes.append(encodeAttribute(oid: [0x55, 0x04, 0x06], value: country, isString: true))
        }
        
        if let state = config.state {
            attributes.append(encodeAttribute(oid: [0x55, 0x04, 0x08], value: state, isString: true))
        }
        
        if let locality = config.locality {
            attributes.append(encodeAttribute(oid: [0x55, 0x04, 0x07], value: locality, isString: true))
        }
        
        if let organization = config.organization {
            attributes.append(encodeAttribute(oid: [0x55, 0x04, 0x0A], value: organization, isString: true))
        }
        
        if let organizationalUnit = config.organizationalUnit {
            attributes.append(encodeAttribute(oid: [0x55, 0x04, 0x0B], value: organizationalUnit, isString: true))
        }
        
        // Common Name (required)
        attributes.append(encodeAttribute(oid: [0x55, 0x04, 0x03], value: config.commonName, isString: true))
        
        if let emailAddress = config.emailAddress {
            // Email address OID: 1.2.840.113549.1.9.1
            attributes.append(encodeAttribute(
                oid: [0x2A, 0x86, 0x48, 0x86, 0xF7, 0x0D, 0x01, 0x09, 0x01],
                value: emailAddress,
                isString: true
            ))
        }
        
        // Combine all attributes
        var dn = Data()
        for attribute in attributes {
            dn.append(attribute)
        }
        
        return wrapInSequence(dn)
    }
    
    private static func encodeAttribute(oid: [UInt8], value: String, isString: Bool) -> Data {
        var set = Data()
        
        // OID
        var oidData = Data([0x06, UInt8(oid.count)])
        oidData.append(contentsOf: oid)
        
        // Value
        let valueData = value.data(using: .utf8)!
        var valueEncoded = Data()
        
        if isString {
            // UTF8String tag
            valueEncoded.append(0x0C)
            valueEncoded.append(UInt8(valueData.count))
            valueEncoded.append(valueData)
        }
        
        // Combine OID and value in SEQUENCE
        var sequence = Data()
        sequence.append(oidData)
        sequence.append(valueEncoded)
        
        let sequenceWrapped = wrapInSequence(sequence)
        
        // Wrap in SET
        set.append(0x31)
        set.append(UInt8(sequenceWrapped.count))
        set.append(sequenceWrapped)
        
        return set
    }
    
    private static func encodeSubjectPublicKeyInfo(publicKeyData: Data) throws -> Data {
        // Algorithm identifier for P-256
        let algorithmIdentifier = Data([
            0x30, 0x13,  // SEQUENCE
            0x06, 0x07, 0x2A, 0x86, 0x48, 0xCE, 0x3D, 0x02, 0x01,  // OID: 1.2.840.10045.2.1 (ecPublicKey)
            0x06, 0x08, 0x2A, 0x86, 0x48, 0xCE, 0x3D, 0x03, 0x01, 0x07  // OID: 1.2.840.10045.3.1.7 (P-256)
        ])
        
        // Public key as BIT STRING
        var publicKeyBitString = Data()
        publicKeyBitString.append(0x03)  // BIT STRING tag
        publicKeyBitString.append(UInt8(publicKeyData.count + 1))
        publicKeyBitString.append(0x00)  // No unused bits
        publicKeyBitString.append(publicKeyData)
        
        // Combine into SEQUENCE
        var spki = Data()
        spki.append(algorithmIdentifier)
        spki.append(publicKeyBitString)
        
        return wrapInSequence(spki)
    }
    
    private static func wrapInSequence(_ data: Data) -> Data {
        var sequence = Data()
        sequence.append(0x30)  // SEQUENCE tag
        
        // Encode length
        if data.count < 128 {
            sequence.append(UInt8(data.count))
        } else if data.count < 256 {
            sequence.append(0x81)
            sequence.append(UInt8(data.count))
        } else {
            sequence.append(0x82)
            sequence.append(UInt8((data.count >> 8) & 0xFF))
            sequence.append(UInt8(data.count & 0xFF))
        }
        
        sequence.append(data)
        return sequence
    }
    
    private static func signCSR(
        csrData: Data,
        privateKey: SecKey
    ) throws -> Data {
        // Create signature
        let algorithm = SecKeyAlgorithm.ecdsaSignatureMessageX962SHA256
        
        guard SecKeyIsAlgorithmSupported(privateKey, .sign, algorithm) else {
            throw CSRError.invalidAlgorithm
        }
        
        var error: Unmanaged<CFError>?
        guard let signature = SecKeyCreateSignature(
            privateKey,
            algorithm,
            csrData as CFData,
            &error
        ) as Data? else {
            if let error = error?.takeRetainedValue() {
                throw CSRError.signingFailed(error.localizedDescription)
            }
            throw CSRError.signingFailed("Unknown error")
        }
        
        // Build complete CSR
        var csr = Data()
        
        // CSR Info
        csr.append(csrData)
        
        // Signature Algorithm (ecdsaWithSHA256)
        let signatureAlgorithm = Data([
            0x30, 0x0A,  // SEQUENCE
            0x06, 0x08, 0x2A, 0x86, 0x48, 0xCE, 0x3D, 0x04, 0x03, 0x02  // OID: 1.2.840.10045.4.3.2
        ])
        csr.append(signatureAlgorithm)
        
        // Signature as BIT STRING
        var signatureBitString = Data()
        signatureBitString.append(0x03)  // BIT STRING tag
        signatureBitString.append(UInt8(signature.count + 1))
        signatureBitString.append(0x00)  // No unused bits
        signatureBitString.append(signature)
        csr.append(signatureBitString)
        
        return wrapInSequence(csr)
    }
}

// MARK: - Example Usage

@available(iOS 13.0, macOS 10.15, *)
extension CSRManager {
    
    /// Example of creating a CSR for web service certificate signing
    /// - Parameter keyTag: The tag of the secure enclave key
    /// - Returns: CSR ready to send to a certificate authority
    public static func createCSRForWebService(keyTag: String) throws -> String {
        let config = CSRConfig(
            commonName: "C2PA Content Signer",
            organization: "Your Organization",
            organizationalUnit: "Content Authentication",
            country: "US",
            state: "CA",
            locality: "San Francisco",
            emailAddress: "signer@example.com"
        )
        
        return try createCSR(keyTag: keyTag, config: config)
    }
}

// MARK: - Web Service Integration

@available(iOS 13.0, macOS 10.15, *)
public struct CertificateWebService {
    
    public struct SignedCertificateResponse {
        public let certificateChain: String
        public let certificateId: String
        public let expirationDate: Date
    }
    
    /// Submits a CSR to a web service for signing
    /// - Parameters:
    ///   - csr: The CSR in PEM format
    ///   - serviceURL: The URL of the certificate signing service
    ///   - apiKey: API key for authentication
    /// - Returns: Signed certificate chain
    public static func submitCSR(
        _ csr: String,
        to serviceURL: URL,
        apiKey: String
    ) async throws -> SignedCertificateResponse {
        // This is a placeholder for web service integration
        // In production, this would:
        // 1. Create an HTTP request with the CSR
        // 2. Add authentication headers
        // 3. Submit to the certificate authority
        // 4. Parse the response containing the signed certificate chain
        
        throw CSRError.signingFailed("Web service integration not yet implemented")
    }
}