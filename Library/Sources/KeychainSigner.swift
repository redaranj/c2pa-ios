//
//  KeychainSigner.swift
//

import C2PAC
import Foundation
import Security

extension Signer {
    public convenience init(
        algorithm: SigningAlgorithm,
        certificateChainPEM: String,
        tsaURL: String? = nil,
        keychainKeyTag: String
    ) throws {
        let secAlgorithm: SecKeyAlgorithm
        switch algorithm {
        case .es256:
            secAlgorithm = .ecdsaSignatureMessageX962SHA256
        case .es384:
            secAlgorithm = .ecdsaSignatureMessageX962SHA384
        case .es512:
            secAlgorithm = .ecdsaSignatureMessageX962SHA512
        case .ps256:
            secAlgorithm = .rsaSignatureMessagePSSSHA256
        case .ps384:
            secAlgorithm = .rsaSignatureMessagePSSSHA384
        case .ps512:
            secAlgorithm = .rsaSignatureMessagePSSSHA512
        case .ed25519:
            throw C2PAError.api("Ed25519 not supported by iOS Keychain")
        }

        try self.init(
            algorithm: algorithm,
            certificateChainPEM: certificateChainPEM,
            tsaURL: tsaURL
        ) { data in
            let query: [String: Any] = [
                kSecClass as String: kSecClassKey,
                kSecAttrApplicationTag as String: keychainKeyTag,
                kSecAttrKeyType as String: kSecAttrKeyTypeECSECPrimeRandom,
                kSecReturnRef as String: true
            ]

            var item: CFTypeRef?
            let status = SecItemCopyMatching(query as CFDictionary, &item)

            guard status == errSecSuccess,
                let privateKey = item as! SecKey?
            else {
                throw C2PAError.api("Failed to find key '\(keychainKeyTag)' in keychain: \(status)")
            }

            guard SecKeyIsAlgorithmSupported(privateKey, .sign, secAlgorithm) else {
                throw C2PAError.api("Key doesn't support algorithm \(algorithm)")
            }

            var error: Unmanaged<CFError>?
            guard
                let signature = SecKeyCreateSignature(
                    privateKey,
                    secAlgorithm,
                    data as CFData,
                    &error)
            else {
                if let error = error?.takeRetainedValue() {
                    throw C2PAError.api("Signing failed: \(error)")
                }
                throw C2PAError.api("Signing failed")
            }

            return signature as Data
        }
    }
}
