import C2PA
import CoreLocation
import Crypto
import Foundation
import ImageIO
import OSLog
import Photos
import PhotosUI
import Security
import UIKit

@MainActor
final class C2PAManager: ObservableObject {
    static let shared = C2PAManager()

    @Published var isProcessing = false
    @Published var lastError: String?

    var defaultCertificateData: Data?
    var defaultPrivateKeyData: Data?

    private init() {
        loadDefaultCertificates()

        // Listen for signing mode changes
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(signingModeChanged),
            name: Notification.Name("SigningModeChanged"),
            object: nil
        )
    }

    @objc private func signingModeChanged() {
        os_log("Signing mode changed", log: Logger.general, type: .info)
    }

    private func loadDefaultCertificates() {
        if let certURL = Bundle.main.url(forResource: "default_certs", withExtension: "pem"),
            let keyURL = Bundle.main.url(forResource: "default_private", withExtension: "key")
        {
            do {
                defaultCertificateData = try Data(contentsOf: certURL)
                defaultPrivateKeyData = try Data(contentsOf: keyURL)
                os_log(
                    "Default certificates loaded successfully", log: Logger.certificate, type: .info
                )
            } catch {
                os_log(
                    "Error loading default certificates: %{public}@", log: Logger.error,
                    type: .error, error.localizedDescription)
            }
        }
    }

    // MARK: - Main Public Interface

    func signAndSaveImage(
        _ image: UIImage, saveToPhotos: Bool = false, location: CLLocation? = nil,
        completion: @escaping (Bool, String?, Data?) -> Void
    ) {
        isProcessing = true
        lastError = nil

        Task {
            do {
                guard
                    let imageData = image.jpegData(
                        compressionQuality: Constants.Image.jpegCompressionQuality)
                else {
                    await MainActor.run {
                        self.isProcessing = false
                        let error = C2PAManagerError.imageConversionFailed
                        self.lastError = error.localizedDescription
                        completion(false, self.lastError, nil)
                    }
                    return
                }

                os_log(
                    "Original image data size: %d bytes", log: Logger.general, type: .debug,
                    imageData.count)

                let signingModeString =
                    UserDefaults.standard.string(forKey: Constants.UserDefaultsKeys.signingMode)
                    ?? "Default"
                let signingMode = SigningMode(rawValue: signingModeString) ?? .defaultMode

                os_log(
                    "Using signing mode: %{public}@", log: Logger.signing, type: .info,
                    signingMode.rawValue)

                // Use the unified signing method
                let signedImageData = try await signImageData(
                    imageData,
                    signingMode: signingMode,
                    location: location
                )

                os_log(
                    "Signed image data size: %d bytes", log: Logger.signing, type: .debug,
                    signedImageData.count)
                os_log(
                    "Size difference: %d bytes", log: Logger.signing, type: .debug,
                    signedImageData.count - imageData.count)

                let savedURL = try PhotoStorageManager.shared.saveSignedPhoto(signedImageData)
                os_log(
                    "Saved signed photo with C2PA credentials to app storage: %{public}@",
                    log: Logger.storage, type: .info, savedURL.lastPathComponent)

                // Comprehensive C2PA verification
                os_log("Starting C2PA verification of saved file...", log: Logger.verification, type: .info)
                do {
                    // Read the file back and verify C2PA credentials
                    let manifestJSON = try C2PA.readFile(at: savedURL, dataDir: nil)

                    os_log("✅ C2PA VERIFICATION SUCCESS", log: Logger.verification, type: .info)
                    os_log("Manifest JSON loaded successfully", log: Logger.verification, type: .info)

                    // Log raw JSON length for debugging
                    os_log(
                        "Manifest JSON length: %d characters", log: Logger.verification, type: .debug,
                        manifestJSON.count)

                    // Parse the JSON to inspect the manifest
                    if let jsonData = manifestJSON.data(using: .utf8),
                        let manifestStore = try? JSONSerialization.jsonObject(with: jsonData) as? [String: Any]
                    {

                        // Check for active manifest
                        if let activeManifest = manifestStore["active_manifest"] as? [String: Any] {
                            os_log("Active manifest found", log: Logger.verification, type: .info)

                            // Log claim generator
                            if let claimGenerator = activeManifest["claim_generator"] as? String {
                                os_log(
                                    "Claim generator: %{public}@",
                                    log: Logger.verification, type: .info, claimGenerator)

                                // Check if this is using test mode
                                if claimGenerator.contains("Example") || claimGenerator.contains("Test") {
                                    os_log(
                                        "⚠️ WARNING: Using test/example claim generator - will not validate on public verifiers",
                                        log: Logger.verification, type: .error)
                                }
                            }

                            // Log title
                            if let title = activeManifest["title"] as? String {
                                os_log(
                                    "Title: %{public}@",
                                    log: Logger.verification, type: .info, title)
                            }

                            // Check signature info
                            if let signatureInfo = activeManifest["signature_info"] as? [String: Any] {
                                os_log("Signature info present", log: Logger.verification, type: .info)

                                if let alg = signatureInfo["alg"] as? String {
                                    os_log(
                                        "Algorithm: %{public}@",
                                        log: Logger.verification, type: .info, alg)
                                }

                                if let issuer = signatureInfo["issuer"] as? String {
                                    os_log(
                                        "Certificate issuer: %{public}@",
                                        log: Logger.verification, type: .info, issuer)
                                }

                                if let time = signatureInfo["time"] as? String {
                                    os_log(
                                        "Signature time: %{public}@",
                                        log: Logger.verification, type: .info, time)
                                }
                            } else {
                                os_log(
                                    "⚠️ No signature info found in manifest",
                                    log: Logger.verification, type: .error)
                            }

                            // Check assertions
                            if let assertions = activeManifest["assertions"] as? [[String: Any]] {
                                os_log(
                                    "Found %d assertions",
                                    log: Logger.verification, type: .info, assertions.count)

                                for assertion in assertions {
                                    if let label = assertion["label"] as? String {
                                        os_log(
                                            "  - Assertion: %{public}@",
                                            log: Logger.verification, type: .debug, label)
                                    }
                                }
                            }

                            // Check instance ID
                            if let instanceID = activeManifest["instance_id"] as? String {
                                os_log(
                                    "Instance ID: %{public}@",
                                    log: Logger.verification, type: .debug, instanceID)
                            }

                        } else {
                            os_log(
                                "⚠️ No active manifest found in manifest store",
                                log: Logger.verification, type: .error)
                        }

                        // Check manifests
                        if let manifests = manifestStore["manifests"] as? [String: Any] {
                            os_log(
                                "Total manifests in store: %d",
                                log: Logger.verification, type: .info, manifests.count)
                        }

                        // Check validation status if present
                        if let validationStatus = manifestStore["validation_status"] as? [[String: Any]] {
                            os_log(
                                "Validation status entries: %d",
                                log: Logger.verification, type: .info, validationStatus.count)

                            for status in validationStatus {
                                if let code = status["code"] as? String {
                                    if code.contains("error") || code.contains("failure") {
                                        os_log(
                                            "⚠️ Validation error: %{public}@",
                                            log: Logger.verification, type: .error, code)
                                    } else {
                                        os_log(
                                            "Validation status: %{public}@",
                                            log: Logger.verification, type: .info, code)
                                    }
                                }
                            }
                        }

                    } else {
                        // If we can't parse the JSON, just log it as raw
                        os_log(
                            "Raw manifest JSON (first 500 chars): %{public}@",
                            log: Logger.verification, type: .debug,
                            String(manifestJSON.prefix(500)))
                    }

                } catch {
                    os_log("❌ C2PA VERIFICATION FAILED", log: Logger.verification, type: .error)
                    os_log(
                        "Error: %{public}@", log: Logger.verification, type: .error,
                        error.localizedDescription)

                    // Try to provide more specific error information
                    if let c2paError = error as? C2PAError {
                        os_log(
                            "C2PA Error details: %{public}@",
                            log: Logger.verification, type: .error,
                            String(describing: c2paError))
                    }

                    // Still save the file even if verification fails
                    os_log(
                        "File saved but C2PA verification failed - credentials may be malformed",
                        log: Logger.verification, type: .error)
                }

                if saveToPhotos {
                    os_log(
                        "Saving to photo library (metadata may be stripped)", log: Logger.storage,
                        type: .info)
                    try await saveToPhotoLibrary(imageData: signedImageData)
                    os_log("Saved to photo library", log: Logger.storage, type: .info)
                }

                // Return the signed data and saved URL
                let fileName = savedURL.lastPathComponent
                let imageDataCopy = signedImageData

                await MainActor.run {
                    self.isProcessing = false
                    completion(true, fileName, imageDataCopy)
                }
            } catch {
                os_log(
                    "Error saving image: %{public}@", log: Logger.error, type: .error,
                    error.localizedDescription)
                await MainActor.run {
                    self.isProcessing = false
                    self.lastError = error.localizedDescription
                    completion(false, error.localizedDescription, nil)
                }
            }
        }
    }

    // MARK: - Unified Signing Implementation

    /// Sign image data using the configured signing mode
    func signImageData(
        _ imageData: Data,
        signingMode: SigningMode,
        location: CLLocation? = nil
    ) async throws -> Data {
        os_log(
            "Signing with mode: %{public}@", log: Logger.signing, type: .info,
            signingMode.rawValue)

        // Create manifest JSON
        let manifestJSON = try createManifestJSON(location: location)

        // Create temporary files for image processing
        let tempDir = FileManager.default.temporaryDirectory
        let inputURL = tempDir.appendingPathComponent("input_\(UUID().uuidString).jpg")
        let outputURL = tempDir.appendingPathComponent("output_\(UUID().uuidString).jpg")

        defer {
            try? FileManager.default.removeItem(at: inputURL)
            try? FileManager.default.removeItem(at: outputURL)
        }

        try imageData.write(to: inputURL)

        // Create the appropriate signer based on the mode
        let signer = try await createSigner(for: signingMode)

        // Sign the image using the Library's Builder
        os_log("Creating Builder with manifest", log: Logger.signing, type: .info)
        let builder = try Builder(manifestJSON: manifestJSON)

        os_log("Creating source and destination streams", log: Logger.signing, type: .info)
        let sourceStream = try Stream(fileURL: inputURL, truncate: false)
        let destStream = try Stream(fileURL: outputURL, truncate: true)

        os_log("Starting builder.sign operation", log: Logger.signing, type: .info)
        do {
            try builder.sign(
                format: "image/jpeg",
                source: sourceStream,
                destination: destStream,
                signer: signer
            )
            os_log("builder.sign completed successfully", log: Logger.signing, type: .info)
        } catch {
            os_log(
                "builder.sign failed with error: %{public}@", log: Logger.signing, type: .error,
                String(describing: error))
            throw error
        }

        // Read the signed image data
        let signedData = try Data(contentsOf: outputURL)

        os_log(
            "Successfully signed image. Original: %d bytes, Signed: %d bytes",
            log: Logger.signing, type: .info, imageData.count, signedData.count)

        return signedData
    }

    /// Create the appropriate Signer instance based on the signing mode
    private func createSigner(for mode: SigningMode) async throws -> Signer {
        switch mode {
        case .defaultMode:
            return try await createDefaultSigner()

        case .keychain:
            return try await createKeychainSigner()

        case .secureEnclave:
            return try await createSecureEnclaveSigner()

        case .custom:
            return try await createCustomSigner()

        case .remote:
            return try await createRemoteSigner()
        }
    }

    // MARK: - Default Mode Signer

    private func createDefaultSigner() async throws -> Signer {
        guard let certData = defaultCertificateData,
            let keyData = defaultPrivateKeyData,
            let certPEM = String(data: certData, encoding: .utf8),
            let keyPEM = String(data: keyData, encoding: .utf8)
        else {
            throw C2PAManagerError.certificatesNotAvailable
        }

        os_log("Creating default signer with included test certificates", log: Logger.signing, type: .info)

        return try Signer(
            certsPEM: certPEM,
            privateKeyPEM: keyPEM,
            algorithm: .es256,
            tsaURL: Constants.Signing.defaultTSAURL
        )
    }

    // MARK: - Keychain Signer

    private func createKeychainSigner() async throws -> Signer {
        let keyTag = Constants.Keychain.keychainPrivateKeyTag
        let certChainKey = keyTag + Constants.Keychain.certChainSuffix

        // Try to get existing certificate chain
        let certChainPEM = try await getOrCreateKeychainCertificate(keyTag: keyTag, certChainKey: certChainKey)

        os_log("Creating keychain signer with tag: %{public}@", log: Logger.signing, type: .info, keyTag)

        return try Signer(
            algorithm: .es256,
            certificateChainPEM: certChainPEM,
            tsaURL: Constants.Signing.defaultTSAURL,
            keychainKeyTag: keyTag
        )
    }

    private func getOrCreateKeychainCertificate(keyTag: String, certChainKey: String) async throws -> String {
        // Check if certificate chain already exists
        let certQuery: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrAccount as String: certChainKey,
            kSecReturnData as String: true
        ]

        var certItem: CFTypeRef?
        let certStatus = SecItemCopyMatching(certQuery as CFDictionary, &certItem)

        if certStatus == errSecSuccess,
            let certData = certItem as? Data,
            let certString = String(data: certData, encoding: .utf8)
        {
            os_log("Found existing certificate chain for keychain key", log: Logger.certificate, type: .info)
            return certString
        }

        // Certificate doesn't exist, create new one
        os_log("Creating new certificate chain for keychain key", log: Logger.certificate, type: .info)

        // First ensure the key exists or create it
        let privateKey = try ensureKeychainKey(tag: keyTag)

        guard let publicKey = SecKeyCopyPublicKey(privateKey) else {
            throw C2PAManagerError.privateKeyExportFailed
        }

        let config = CertificateManager.CertificateConfig(
            commonName: "C2PA Keychain User",
            organization: "C2PA Example",
            organizationalUnit: "Mobile",
            country: "US",
            state: "CA",
            locality: "San Francisco",
            emailAddress: "keychain@example.com"
        )

        let certChain = try CertificateManager.createSelfSignedCertificateChain(
            for: publicKey,
            config: config
        )

        // Save certificate chain for future use
        let certChainData = certChain.data(using: .utf8)!
        let saveQuery: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrAccount as String: certChainKey,
            kSecValueData as String: certChainData
        ]

        SecItemDelete(saveQuery as CFDictionary)
        let saveStatus = SecItemAdd(saveQuery as CFDictionary, nil)

        if saveStatus != errSecSuccess {
            os_log(
                "Warning: Could not cache certificate chain: %d", log: Logger.certificate,
                type: .error, saveStatus)
        }

        return certChain
    }

    private func ensureKeychainKey(tag: String) throws -> SecKey {
        // Try to get existing key
        let query: [String: Any] = [
            kSecClass as String: kSecClassKey,
            kSecAttrApplicationTag as String: tag.data(using: .utf8)!,
            kSecAttrKeyType as String: kSecAttrKeyTypeECSECPrimeRandom,
            kSecReturnRef as String: true
        ]

        var item: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &item)

        if status == errSecSuccess, let key = item as! SecKey? {
            os_log("Found existing keychain key", log: Logger.signing, type: .info)
            return key
        }

        // Create new key
        os_log("Creating new keychain key", log: Logger.signing, type: .info)

        let attributes: [String: Any] = [
            kSecAttrKeyType as String: kSecAttrKeyTypeECSECPrimeRandom,
            kSecAttrKeySizeInBits as String: 256,
            kSecPrivateKeyAttrs as String: [
                kSecAttrIsPermanent as String: true,
                kSecAttrApplicationTag as String: tag.data(using: .utf8)!
            ]
        ]

        var error: Unmanaged<CFError>?
        guard let privateKey = SecKeyCreateRandomKey(attributes as CFDictionary, &error) else {
            if let error = error?.takeRetainedValue() {
                throw C2PAManagerError.keychainKeyCreationFailed(error.localizedDescription)
            }
            throw C2PAManagerError.keychainKeyCreationFailed("Unknown error")
        }

        return privateKey
    }

    // MARK: - Secure Enclave Signer

    private func createSecureEnclaveSigner() async throws -> Signer {
        let keyTag = Constants.Keychain.secureEnclaveKeyTag
        let certChainKey = keyTag + Constants.Keychain.certChainSuffix

        // Get or create certificate chain for Secure Enclave key
        let certChainPEM = try await getOrCreateSecureEnclaveCertificate(keyTag: keyTag, certChainKey: certChainKey)

        os_log("Creating Secure Enclave signer", log: Logger.signing, type: .info)

        let config = SecureEnclaveSignerConfig(
            keyTag: keyTag,
            accessControl: [.privateKeyUsage]
        )

        return try Signer(
            algorithm: .es256,
            certificateChainPEM: certChainPEM,
            tsaURL: Constants.Signing.defaultTSAURL,
            secureEnclaveConfig: config
        )
    }

    private func getOrCreateSecureEnclaveCertificate(keyTag: String, certChainKey: String) async throws -> String {
        // Check if certificate chain already exists
        let certQuery: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrAccount as String: certChainKey,
            kSecReturnData as String: true
        ]

        var certItem: CFTypeRef?
        let certStatus = SecItemCopyMatching(certQuery as CFDictionary, &certItem)

        if certStatus == errSecSuccess,
            let certData = certItem as? Data,
            let certString = String(data: certData, encoding: .utf8)
        {
            os_log("Found existing certificate chain for Secure Enclave key", log: Logger.certificate, type: .info)
            return certString
        }

        // Certificate doesn't exist, create new one
        os_log("Creating new certificate chain for Secure Enclave key", log: Logger.certificate, type: .info)

        // Ensure Secure Enclave key exists (will be created by SecureEnclaveSigner if needed)
        let config = SecureEnclaveSignerConfig(
            keyTag: keyTag,
            accessControl: [.privateKeyUsage]
        )

        // Create the key if it doesn't exist
        _ = try Signer.createSecureEnclaveKey(config: config)

        // Generate CSR for Secure Enclave key
        let certConfig = CertificateManager.CertificateConfig(
            commonName: "C2PA Secure Enclave User",
            organization: "C2PA Example",
            organizationalUnit: "Mobile SE",
            country: "US",
            state: "CA",
            locality: "San Francisco",
            emailAddress: "se@example.com"
        )

        // Generate CSR using the key tag
        let csrPEM = try CertificateManager.createCSR(
            keyTag: keyTag,
            config: certConfig
        )

        // Submit CSR to signing server for enrollment
        let certChain = try await enrollCertificate(csrPEM: csrPEM)

        // Save certificate chain for future use
        let certChainData = certChain.data(using: .utf8)!
        let saveQuery: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrAccount as String: certChainKey,
            kSecValueData as String: certChainData
        ]

        SecItemDelete(saveQuery as CFDictionary)
        let saveStatus = SecItemAdd(saveQuery as CFDictionary, nil)

        if saveStatus != errSecSuccess {
            os_log(
                "Warning: Could not cache SE certificate chain: %d", log: Logger.certificate,
                type: .error, saveStatus)
        }

        return certChain
    }

    // MARK: - Custom Signer

    private func createCustomSigner() async throws -> Signer {
        let keyTag = Constants.Keychain.customPrivateKeyTag

        // First ensure the custom private key is imported into the keychain as a SecKey
        try await ensureCustomKeyInKeychain(keyTag: keyTag)

        // Get the certificate chain
        let certChainPEM = try await getCustomCertificateChain(keyTag: keyTag)

        os_log("Creating custom signer using keychain with tag: %{public}@", log: Logger.signing, type: .info, keyTag)

        // Use the KeychainSigner with the custom key tag
        return try Signer(
            algorithm: .es256,
            certificateChainPEM: certChainPEM,
            tsaURL: Constants.Signing.defaultTSAURL,
            keychainKeyTag: keyTag
        )
    }

    private func ensureCustomKeyInKeychain(keyTag: String) async throws {
        // Check if the key is already in keychain as a SecKey
        let keyQuery: [String: Any] = [
            kSecClass as String: kSecClassKey,
            kSecAttrApplicationTag as String: keyTag.data(using: .utf8)!,
            kSecAttrKeyType as String: kSecAttrKeyTypeECSECPrimeRandom,
            kSecReturnRef as String: true
        ]

        var item: CFTypeRef?
        let status = SecItemCopyMatching(keyQuery as CFDictionary, &item)

        if status == errSecSuccess, item != nil {
            os_log("Custom key already in keychain", log: Logger.signing, type: .info)
            return
        }

        // Key not found, need to import from the stored PEM
        let (_, keyData) = try getCustomCertificate()

        guard let keyPEM = String(data: keyData, encoding: .utf8) else {
            throw C2PAManagerError.invalidCertificateFormat
        }

        // Import the PEM private key into keychain
        try importPrivateKeyToKeychain(pemKey: keyPEM, keyTag: keyTag)
    }

    private func importPrivateKeyToKeychain(pemKey: String, keyTag: String) throws {
        // Remove PEM headers/footers and decode base64
        let lines = pemKey.components(separatedBy: .newlines)
        let base64Key =
            lines
            .filter { !$0.hasPrefix("-----") && !$0.isEmpty }
            .joined()

        guard let keyData = Data(base64Encoded: base64Key) else {
            throw C2PAManagerError.invalidCertificateFormat
        }

        // Import as EC private key
        let keyDict: [String: Any] = [
            kSecAttrKeyType as String: kSecAttrKeyTypeECSECPrimeRandom,
            kSecAttrKeyClass as String: kSecAttrKeyClassPrivate,
            kSecAttrKeySizeInBits as String: 256
        ]

        var error: Unmanaged<CFError>?
        guard let privateKey = SecKeyCreateWithData(keyData as CFData, keyDict as CFDictionary, &error) else {
            if let error = error?.takeRetainedValue() {
                throw C2PAManagerError.keychainKeyCreationFailed("Failed to import key: \(error)")
            }
            throw C2PAManagerError.keychainKeyCreationFailed("Failed to import private key")
        }

        // Store in keychain
        let addQuery: [String: Any] = [
            kSecClass as String: kSecClassKey,
            kSecAttrApplicationTag as String: keyTag.data(using: .utf8)!,
            kSecValueRef as String: privateKey,
            kSecAttrIsPermanent as String: true
        ]

        // Delete any existing key
        let deleteQuery: [String: Any] = [
            kSecClass as String: kSecClassKey,
            kSecAttrApplicationTag as String: keyTag.data(using: .utf8)!
        ]
        SecItemDelete(deleteQuery as CFDictionary)

        let addStatus = SecItemAdd(addQuery as CFDictionary, nil)
        if addStatus != errSecSuccess {
            throw C2PAManagerError.keychainKeyCreationFailed("Failed to store key in keychain: \(addStatus)")
        }

        os_log("Successfully imported custom private key to keychain", log: Logger.signing, type: .info)
    }

    private func getCustomCertificateChain(keyTag: String) async throws -> String {
        let certChainKey = keyTag + Constants.Keychain.certChainSuffix

        // Try to get the certificate chain from keychain
        let certQuery: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrAccount as String: certChainKey,
            kSecReturnData as String: true
        ]

        var certItem: CFTypeRef?
        let certStatus = SecItemCopyMatching(certQuery as CFDictionary, &certItem)

        if certStatus == errSecSuccess,
            let certData = certItem as? Data,
            let certString = String(data: certData, encoding: .utf8)
        {
            return certString
        }

        // If not found, get from the old storage location
        let (certData, _) = try getCustomCertificate()
        guard let certPEM = String(data: certData, encoding: .utf8) else {
            throw C2PAManagerError.invalidCertificateFormat
        }

        // Save for future use
        let saveQuery: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrAccount as String: certChainKey,
            kSecValueData as String: certData
        ]

        SecItemDelete(saveQuery as CFDictionary)
        _ = SecItemAdd(saveQuery as CFDictionary, nil)

        return certPEM
    }

    // MARK: - Certificate Enrollment

    private func enrollCertificate(csrPEM: String) async throws -> String {
        var serverURL = UserDefaults.standard.string(forKey: Constants.UserDefaultsKeys.remoteSigningURL) ?? ""
        var bearerToken = UserDefaults.standard.string(forKey: Constants.UserDefaultsKeys.remoteBearerToken) ?? ""

        guard !serverURL.isEmpty else {
            throw C2PAManagerError.remoteSigningNotConfigured
        }

        guard let url = URL(string: "\(serverURL)/api/v1/certificates/sign") else {
            throw C2PAManagerError.invalidURL
        }

        os_log("Enrolling certificate with server: %{public}@", log: Logger.certificate, type: .info, serverURL)

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("Bearer \(bearerToken)", forHTTPHeaderField: "Authorization")

        struct EnrollmentRequest: Codable {
            let csr: String
            let metadata: EnrollmentMetadata?
        }

        struct EnrollmentMetadata: Codable {
            let device_id: String?
            let app_version: String?
        }

        struct EnrollmentResponse: Codable {
            let cert_id: String
            let cert_chain: String
            let expires_at: Date
            let serial_number: String
        }

        let enrollmentRequest = EnrollmentRequest(
            csr: csrPEM,
            metadata: EnrollmentMetadata(
                device_id: UIDevice.current.identifierForVendor?.uuidString,
                app_version: Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String
            )
        )

        let encoder = JSONEncoder()
        request.httpBody = try encoder.encode(enrollmentRequest)

        let (data, response) = try await URLSession.shared.data(for: request)

        guard let httpResponse = response as? HTTPURLResponse else {
            throw C2PAManagerError.networkError("Invalid response")
        }

        guard httpResponse.statusCode == 200 else {
            let errorMessage = String(data: data, encoding: .utf8) ?? "Unknown error"
            throw C2PAManagerError.networkError("Enrollment failed: \(errorMessage)")
        }

        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let enrollmentResponse = try decoder.decode(EnrollmentResponse.self, from: data)

        os_log(
            "Certificate enrolled successfully. Certificate ID: %{public}@",
            log: Logger.certificate, type: .info, enrollmentResponse.cert_id)

        return enrollmentResponse.cert_chain
    }

    // MARK: - Remote Service Signer

    private func createRemoteSigner() async throws -> Signer {
        let remoteURL = UserDefaults.standard.string(forKey: Constants.UserDefaultsKeys.remoteSigningURL) ?? ""
        var bearerToken = UserDefaults.standard.string(forKey: Constants.UserDefaultsKeys.remoteBearerToken)

        guard !remoteURL.isEmpty else {
            throw C2PAManagerError.remoteSigningNotConfigured
        }

        // Construct the full configuration URL if not already a full path
        let configurationURL: String
        if remoteURL.contains("/api/v1/c2pa/configuration") {
            configurationURL = remoteURL
        } else {
            configurationURL = "\(remoteURL.trimmingCharacters(in: .init(charactersIn: "/")))/api/v1/c2pa/configuration"
        }

        os_log(
            "Creating remote service signer with configuration URL: %{public}@", log: Logger.signing, type: .info,
            configurationURL)

        // Use the new WebServiceSigner with configuration URL
        let webServiceSigner = WebServiceSigner(configurationURL: configurationURL, bearerToken: bearerToken)

        os_log("Fetching configuration and creating signer from remote service", log: Logger.signing, type: .info)

        do {
            let signer = try await webServiceSigner.createSigner()
            os_log("Successfully created remote service signer", log: Logger.signing, type: .info)
            return signer
        } catch {
            os_log(
                "Failed to create remote signer: %{public}@", log: Logger.signing, type: .error,
                error.localizedDescription)
            throw C2PAManagerError.remoteServiceError(error.localizedDescription)
        }
    }

    // MARK: - Manifest Creation

    private func createManifestJSON(location: CLLocation? = nil) throws -> String {
        var manifest: [String: Any] = [
            "claim_generator": "C2PA iOS Example/1.0.0",
            "title": "Image signed on iOS",
            "assertions": []
        ]

        // Add location assertion if available
        if let location = location {
            let locationAssertion: [String: Any] = [
                "label": "stds.exif",
                "data": [
                    "exif:GPSLatitude": location.coordinate.latitude,
                    "exif:GPSLongitude": location.coordinate.longitude,
                    "exif:GPSAltitude": location.altitude,
                    "exif:GPSTimeStamp": ISO8601DateFormatter().string(from: location.timestamp)
                ]
            ]

            var assertions = manifest["assertions"] as! [[String: Any]]
            assertions.append(locationAssertion)
            manifest["assertions"] = assertions
        }

        // Add creation time assertion
        let creationAssertion: [String: Any] = [
            "label": "c2pa.actions",
            "data": [
                "actions": [
                    [
                        "action": "c2pa.created",
                        "when": ISO8601DateFormatter().string(from: Date())
                    ]
                ]
            ]
        ]

        var assertions = manifest["assertions"] as! [[String: Any]]
        assertions.append(creationAssertion)
        manifest["assertions"] = assertions

        let jsonData = try JSONSerialization.data(withJSONObject: manifest)
        guard let jsonString = String(data: jsonData, encoding: .utf8) else {
            throw C2PAManagerError.manifestCreationFailed
        }

        return jsonString
    }

    // MARK: - Helper Methods

    func getCustomCertificate() throws -> (Data, Data) {
        let certQuery: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrAccount as String: Constants.Keychain.customCertificateKey,
            kSecReturnData as String: true
        ]

        let keyQuery: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrAccount as String: Constants.Keychain.customPrivateKeyKey,
            kSecReturnData as String: true
        ]

        var certItem: CFTypeRef?
        var keyItem: CFTypeRef?

        let certStatus = SecItemCopyMatching(certQuery as CFDictionary, &certItem)
        let keyStatus = SecItemCopyMatching(keyQuery as CFDictionary, &keyItem)

        guard certStatus == errSecSuccess,
            let certData = certItem as? Data,
            keyStatus == errSecSuccess,
            let keyData = keyItem as? Data
        else {
            throw C2PAManagerError.customCertificatesNotFound
        }

        return (certData, keyData)
    }

    private func saveToPhotoLibrary(imageData: Data) async throws {
        let status = PHPhotoLibrary.authorizationStatus(for: .addOnly)

        switch status {
        case .authorized:
            break
        case .notDetermined:
            let granted = await PHPhotoLibrary.requestAuthorization(for: .addOnly) == .authorized
            if !granted {
                throw C2PAManagerError.photoLibraryAccessDenied
            }
        default:
            throw C2PAManagerError.photoLibraryAccessDenied
        }

        return try await withCheckedThrowingContinuation { continuation in
            PHPhotoLibrary.shared().performChanges(
                {
                    let creationRequest = PHAssetCreationRequest.forAsset()
                    creationRequest.addResource(with: .photo, data: imageData, options: nil)
                },
                completionHandler: { success, error in
                    if success {
                        continuation.resume()
                    } else {
                        continuation.resume(
                            throwing: error ?? C2PAManagerError.savePhotoFailed
                        )
                    }
                })
        }
    }

    func loadImageFromPhotoLibrary(
        assetId: String, completion: @escaping (UIImage?) -> Void
    ) {
        let fetchResult = PHAsset.fetchAssets(
            withLocalIdentifiers: [assetId], options: nil)

        guard let asset = fetchResult.firstObject else {
            os_log(
                "Asset not found with ID: %{public}@", log: Logger.storage, type: .error,
                assetId)
            completion(nil)
            return
        }

        let options = PHImageRequestOptions()
        options.isSynchronous = false
        options.deliveryMode = .highQualityFormat

        PHImageManager.default().requestImage(
            for: asset,
            targetSize: PHImageManagerMaximumSize,
            contentMode: .aspectFit,
            options: options
        ) { image, _ in
            DispatchQueue.main.async {
                completion(image)
            }
        }
    }

    func fetchLastPhotoAsset(completion: @escaping (PHAsset?) -> Void) {
        let fetchOptions = PHFetchOptions()
        fetchOptions.sortDescriptors = [
            NSSortDescriptor(key: "creationDate", ascending: false)
        ]
        fetchOptions.fetchLimit = 1

        let fetchResult = PHAsset.fetchAssets(with: .image, options: fetchOptions)

        DispatchQueue.main.async {
            completion(fetchResult.firstObject)
        }
    }

    func loadUIImage(from asset: PHAsset, completion: @escaping (UIImage?) -> Void) {
        let options = PHImageRequestOptions()
        options.isSynchronous = false
        options.deliveryMode = .highQualityFormat

        PHImageManager.default().requestImage(
            for: asset,
            targetSize: PHImageManagerMaximumSize,
            contentMode: .aspectFit,
            options: options
        ) { image, _ in
            DispatchQueue.main.async {
                completion(image)
            }
        }
    }

    func loadImageData(
        from asset: PHAsset, completion: @escaping (Data?) -> Void
    ) {
        let options = PHImageRequestOptions()
        options.isSynchronous = false
        options.deliveryMode = .highQualityFormat
        options.isNetworkAccessAllowed = true

        PHImageManager.default().requestImageDataAndOrientation(
            for: asset, options: options
        ) { data, _, _, _ in
            DispatchQueue.main.async {
                completion(data)
            }
        }
    }

    func loadImageData(from assetId: String, completion: @escaping (Data?) -> Void) {
        let fetchResult = PHAsset.fetchAssets(
            withLocalIdentifiers: [assetId], options: nil)

        guard let asset = fetchResult.firstObject else {
            os_log(
                "Could not fetch saved asset with ID: %{public}@", log: Logger.storage,
                type: .error, assetId)
            completion(nil)
            return
        }

        let options = PHImageRequestOptions()
        options.isSynchronous = false
        options.deliveryMode = .highQualityFormat
        options.isNetworkAccessAllowed = true

        PHImageManager.default().requestImageDataAndOrientation(
            for: asset, options: options
        ) { data, _, _, _ in
            DispatchQueue.main.async {
                completion(data)
            }
        }
    }
}

// MARK: - Error Definition

enum C2PAManagerError: LocalizedError {
    case imageConversionFailed
    case certificatesNotAvailable
    case invalidCertificateFormat
    case photoLibraryAccessDenied
    case savePhotoFailed
    case keychainKeyNotFound(String)
    case invalidCertificateChain
    case privateKeyExportFailed
    case secureEnclaveNotSupported
    case customCertificatesNotFound
    case remoteSigningNotConfigured
    case invalidRemoteURL
    case remoteCertificateFetchFailed
    case remoteServiceError(String)
    case manifestCreationFailed
    case keychainKeyCreationFailed(String)
    case secureEnclaveKeyNotFound
    case customError(String)
    case invalidURL
    case networkError(String)

    var errorDescription: String? {
        switch self {
        case .imageConversionFailed:
            return "Failed to convert image to JPEG"
        case .certificatesNotAvailable:
            return "Default certificates not available"
        case .invalidCertificateFormat:
            return "Invalid certificate or key format"
        case .photoLibraryAccessDenied:
            return "Photo library access denied"
        case .savePhotoFailed:
            return "Failed to save photo"
        case .keychainKeyNotFound(let tag):
            return "Key not found in keychain for tag: \(tag)"
        case .invalidCertificateChain:
            return "Invalid certificate chain format"
        case .privateKeyExportFailed:
            return "Could not export private key"
        case .secureEnclaveNotSupported:
            return "Secure Enclave is not supported on this device"
        case .customCertificatesNotFound:
            return "Custom certificates not found in keychain. Please upload certificates in Settings."
        case .remoteSigningNotConfigured:
            return "Remote signing URL and bearer token not configured. Please configure in Settings."
        case .invalidRemoteURL:
            return "Invalid remote signing URL"
        case .remoteCertificateFetchFailed:
            return "Failed to get certificate from remote service"
        case .remoteServiceError(let error):
            return "Remote service error: \(error)"
        case .manifestCreationFailed:
            return "Failed to create C2PA manifest"
        case .keychainKeyCreationFailed(let reason):
            return "Failed to create keychain key: \(reason)"
        case .secureEnclaveKeyNotFound:
            return "Secure Enclave key not found"
        case .customError(let message):
            return message
        case .invalidURL:
            return "Invalid URL"
        case .networkError(let message):
            return "Network error: \(message)"
        }
    }
}

// MARK: - Constants Extension

extension Constants {
    enum Signing {
        static let defaultTSAURL = "http://timestamp.digicert.com"
    }
}
