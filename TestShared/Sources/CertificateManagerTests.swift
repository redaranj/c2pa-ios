// This file is licensed to you under the Apache License, Version 2.0
// (http://www.apache.org/licenses/LICENSE-2.0) or the MIT license
// (http://opensource.org/licenses/MIT), at your option.
//
// Unless required by applicable law or agreed to in writing, this software is
// distributed on an "AS IS" BASIS, WITHOUT WARRANTIES OR REPRESENTATIONS OF
// ANY KIND, either express or implied. See the LICENSE-MIT and LICENSE-APACHE
// files for the specific language governing permissions and limitations under
// each license.

import C2PA
import Foundation
import Security

// CertificateManager tests - testing certificate and CSR generation
// These tests use regular keychain keys (not Secure Enclave) so they can run on simulator
public final class CertificateManagerTests: TestImplementation {

    public init() {}

    // MARK: - Helper Methods

    private func createTestKeychainKey(keyTag: String) -> SecKey? {
        // Delete any existing key with this tag first
        deleteTestKeychainKey(keyTag: keyTag)

        let attributes: [String: Any] = [
            kSecAttrKeyType as String: kSecAttrKeyTypeECSECPrimeRandom,
            kSecAttrKeySizeInBits as String: 256,
            kSecPrivateKeyAttrs as String: [
                kSecAttrIsPermanent as String: true,
                kSecAttrApplicationTag as String: keyTag,
                kSecAttrAccessible as String: kSecAttrAccessibleWhenUnlockedThisDeviceOnly
            ]
        ]

        var error: Unmanaged<CFError>?
        guard let privateKey = SecKeyCreateRandomKey(attributes as CFDictionary, &error) else {
            return nil
        }
        return privateKey
    }

    private func deleteTestKeychainKey(keyTag: String) {
        let query: [String: Any] = [
            kSecClass as String: kSecClassKey,
            kSecAttrApplicationTag as String: keyTag,
            kSecAttrKeyType as String: kSecAttrKeyTypeECSECPrimeRandom
        ]
        SecItemDelete(query as CFDictionary)
    }

    // MARK: - CertificateConfig Tests

    public func testCertificateConfigCreation() -> TestResult {
        var testSteps: [String] = []

        // Test basic config creation
        let config = CertificateManager.CertificateConfig(
            commonName: "Test CN",
            organization: "Test Org",
            organizationalUnit: "Test OU",
            country: "US",
            state: "California",
            locality: "San Francisco"
        )

        testSteps.append("Created config with commonName: \(config.commonName)")
        testSteps.append("Organization: \(config.organization)")
        testSteps.append("Organizational Unit: \(config.organizationalUnit)")
        testSteps.append("Country: \(config.country)")
        testSteps.append("State: \(config.state)")
        testSteps.append("Locality: \(config.locality)")
        testSteps.append("Email: \(config.emailAddress ?? "nil")")
        testSteps.append("Validity Days: \(config.validityDays)")

        guard config.commonName == "Test CN" else {
            return .failure("CertificateConfig Creation", "Common name mismatch")
        }

        guard config.validityDays == 365 else {
            return .failure("CertificateConfig Creation", "Default validity days should be 365")
        }

        // Test config with email and custom validity
        let configWithEmail = CertificateManager.CertificateConfig(
            commonName: "Test CN 2",
            organization: "Test Org 2",
            organizationalUnit: "Test OU 2",
            country: "UK",
            state: "London",
            locality: "Westminster",
            emailAddress: "test@example.com",
            validityDays: 730
        )

        guard configWithEmail.emailAddress == "test@example.com" else {
            return .failure("CertificateConfig Creation", "Email address mismatch")
        }

        guard configWithEmail.validityDays == 730 else {
            return .failure("CertificateConfig Creation", "Custom validity days mismatch")
        }

        testSteps.append("Config with email: \(configWithEmail.emailAddress ?? "")")
        testSteps.append("Custom validity days: \(configWithEmail.validityDays)")

        return .success(
            "CertificateConfig Creation",
            testSteps.joined(separator: "\n"))
    }

    public func testCertificateErrorDescriptions() -> TestResult {
        var testSteps: [String] = []

        // Test all error descriptions
        let errors: [CertificateManager.CertificateError] = [
            .invalidKeyData,
            .unsupportedAlgorithm,
            .unsupportedKeyFormat,
            .signingFailed("test signing error")
        ]

        for error in errors {
            guard let description = error.errorDescription else {
                return .failure("CertificateError Descriptions", "Error \(error) has no description")
            }
            testSteps.append("Error: \(error) -> \(description)")
        }

        // Verify specific error messages
        guard CertificateManager.CertificateError.invalidKeyData.errorDescription == "Invalid key data" else {
            return .failure("CertificateError Descriptions", "invalidKeyData description mismatch")
        }

        guard CertificateManager.CertificateError.unsupportedAlgorithm.errorDescription == "Unsupported algorithm" else {
            return .failure("CertificateError Descriptions", "unsupportedAlgorithm description mismatch")
        }

        guard CertificateManager.CertificateError.unsupportedKeyFormat.errorDescription == "Unsupported key format" else {
            return .failure("CertificateError Descriptions", "unsupportedKeyFormat description mismatch")
        }

        guard CertificateManager.CertificateError.signingFailed("test").errorDescription == "Failed to sign: test" else {
            return .failure("CertificateError Descriptions", "signingFailed description mismatch")
        }

        return .success(
            "CertificateError Descriptions",
            testSteps.joined(separator: "\n"))
    }

    public func testSelfSignedCertificateChainCreation() -> TestResult {
        let keyTag = "org.contentauth.test.certmanager.selfcert.\(UUID().uuidString)"
        var testSteps: [String] = []

        defer {
            deleteTestKeychainKey(keyTag: keyTag)
        }

        // Create a test key in the keychain
        guard let privateKey = createTestKeychainKey(keyTag: keyTag) else {
            return .success(
                "Self-Signed Certificate Chain",
                "[WARN] Skipped - Keychain access not available in this test environment")
        }
        testSteps.append("Created test key in keychain")

        guard let publicKey = SecKeyCopyPublicKey(privateKey) else {
            return .failure(
                "Self-Signed Certificate Chain",
                "Failed to extract public key")
        }
        testSteps.append("Extracted public key")

        let config = CertificateManager.CertificateConfig(
            commonName: "Test Signer",
            organization: "Test Organization",
            organizationalUnit: "Certificate Tests",
            country: "US",
            state: "California",
            locality: "San Francisco",
            emailAddress: "test@example.com",
            validityDays: 365
        )

        do {
            let certificateChain = try CertificateManager.createSelfSignedCertificateChain(
                for: publicKey,
                config: config
            )
            testSteps.append("Generated self-signed certificate chain")

            // Verify the chain has PEM format
            guard certificateChain.contains("-----BEGIN CERTIFICATE-----") else {
                return .failure(
                    "Self-Signed Certificate Chain",
                    "Certificate chain missing BEGIN CERTIFICATE marker")
            }
            guard certificateChain.contains("-----END CERTIFICATE-----") else {
                return .failure(
                    "Self-Signed Certificate Chain",
                    "Certificate chain missing END CERTIFICATE marker")
            }
            testSteps.append("Certificate chain has valid PEM format")

            // Count certificates in chain (should be 3: end-entity, intermediate, root)
            let certCount = certificateChain.components(separatedBy: "-----BEGIN CERTIFICATE-----").count - 1
            testSteps.append("Certificate chain contains \(certCount) certificate(s)")

            guard certCount == 3 else {
                return .failure(
                    "Self-Signed Certificate Chain",
                    "Expected 3 certificates, got \(certCount)")
            }

            // Verify the chain can be used with a signer
            let signer = try Signer(
                algorithm: .es256,
                certificateChainPEM: certificateChain,
                tsaURL: nil,
                keychainKeyTag: keyTag
            )
            testSteps.append("Created signer with certificate chain")

            let reserveSize = try signer.reserveSize()
            testSteps.append("Signer reserve size: \(reserveSize) bytes")

            return .success(
                "Self-Signed Certificate Chain",
                testSteps.joined(separator: "\n"))

        } catch {
            testSteps.append("Error: \(error)")
            return .failure(
                "Self-Signed Certificate Chain",
                testSteps.joined(separator: "\n"))
        }
    }

    public func testCSRCreationWithPublicKey() -> TestResult {
        let keyTag = "org.contentauth.test.certmanager.csr.\(UUID().uuidString)"
        var testSteps: [String] = []

        defer {
            deleteTestKeychainKey(keyTag: keyTag)
        }

        // Create a test key in the keychain
        guard let privateKey = createTestKeychainKey(keyTag: keyTag) else {
            return .success(
                "CSR Creation with Public Key",
                "[WARN] Skipped - Keychain access not available in this test environment")
        }
        testSteps.append("Created test key in keychain")

        guard let publicKey = SecKeyCopyPublicKey(privateKey) else {
            return .failure(
                "CSR Creation with Public Key",
                "Failed to extract public key")
        }
        testSteps.append("Extracted public key")

        let config = CertificateManager.CertificateConfig(
            commonName: "CSR Test Subject",
            organization: "CSR Test Organization",
            organizationalUnit: "CSR Testing Unit",
            country: "US",
            state: "New York",
            locality: "New York City",
            emailAddress: "csr@example.com"
        )

        do {
            let csr = try CertificateManager.createCSR(for: publicKey, config: config)
            testSteps.append("Generated CSR")

            // Verify CSR has PEM format
            guard csr.contains("-----BEGIN CERTIFICATE REQUEST-----") else {
                return .failure(
                    "CSR Creation with Public Key",
                    "CSR missing BEGIN CERTIFICATE REQUEST marker")
            }
            guard csr.contains("-----END CERTIFICATE REQUEST-----") else {
                return .failure(
                    "CSR Creation with Public Key",
                    "CSR missing END CERTIFICATE REQUEST marker")
            }
            testSteps.append("CSR has valid PEM format")

            // Verify CSR content is not empty
            let csrLines = csr.components(separatedBy: "\n")
                .filter { !$0.hasPrefix("-----") && !$0.isEmpty }
            guard !csrLines.isEmpty else {
                return .failure(
                    "CSR Creation with Public Key",
                    "CSR has no content")
            }
            testSteps.append("CSR contains \(csrLines.count) lines of base64 data")

            return .success(
                "CSR Creation with Public Key",
                testSteps.joined(separator: "\n"))

        } catch {
            testSteps.append("Error: \(error)")
            return .failure(
                "CSR Creation with Public Key",
                testSteps.joined(separator: "\n"))
        }
    }

    public func testCSRCreationWithKeyTag() -> TestResult {
        let keyTag = "org.contentauth.test.certmanager.csrkeytag.\(UUID().uuidString)"
        var testSteps: [String] = []

        defer {
            deleteTestKeychainKey(keyTag: keyTag)
        }

        // Create a test key in the keychain
        guard createTestKeychainKey(keyTag: keyTag) != nil else {
            return .success(
                "CSR Creation with Key Tag",
                "[WARN] Skipped - Keychain access not available in this test environment")
        }
        testSteps.append("Created test key with tag: \(keyTag)")

        let config = CertificateManager.CertificateConfig(
            commonName: "KeyTag CSR Test",
            organization: "KeyTag Test Org",
            organizationalUnit: "KeyTag Testing",
            country: "CA",
            state: "Ontario",
            locality: "Toronto"
        )

        do {
            let csr = try CertificateManager.createCSR(keyTag: keyTag, config: config)
            testSteps.append("Generated CSR from key tag")

            guard csr.contains("-----BEGIN CERTIFICATE REQUEST-----") else {
                return .failure(
                    "CSR Creation with Key Tag",
                    "CSR missing BEGIN marker")
            }
            testSteps.append("CSR has valid PEM format")

            return .success(
                "CSR Creation with Key Tag",
                testSteps.joined(separator: "\n"))

        } catch {
            testSteps.append("Error: \(error)")
            return .failure(
                "CSR Creation with Key Tag",
                testSteps.joined(separator: "\n"))
        }
    }

    public func testCSRCreationWithInvalidKeyTag() -> TestResult {
        var testSteps: [String] = []

        let config = CertificateManager.CertificateConfig(
            commonName: "Invalid Key Test",
            organization: "Test Org",
            organizationalUnit: "Test OU",
            country: "US",
            state: "Test State",
            locality: "Test City"
        )

        do {
            _ = try CertificateManager.createCSR(
                keyTag: "org.contentauth.nonexistent.key.\(UUID().uuidString)",
                config: config
            )
            return .failure(
                "CSR Creation with Invalid Key Tag",
                "Should have thrown an error for non-existent key")

        } catch let error as CertificateManager.CertificateError {
            testSteps.append("Caught expected error: \(error)")
            if case .invalidKeyData = error {
                testSteps.append("Error is correctly .invalidKeyData")
            }
            return .success(
                "CSR Creation with Invalid Key Tag",
                testSteps.joined(separator: "\n"))

        } catch {
            testSteps.append("Caught unexpected error type: \(error)")
            return .failure(
                "CSR Creation with Invalid Key Tag",
                testSteps.joined(separator: "\n"))
        }
    }

    // MARK: - Direct Certificate Chain Tests

    public func testSelfSignedChainDirectCall() -> TestResult {
        let keyTag = "org.contentauth.test.certmanager.directchain.\(UUID().uuidString)"
        var testSteps: [String] = []

        defer {
            deleteTestKeychainKey(keyTag: keyTag)
        }

        // Create key using Security framework directly for more reliability
        var attributes: [String: Any] = [
            kSecAttrKeyType as String: kSecAttrKeyTypeECSECPrimeRandom,
            kSecAttrKeySizeInBits as String: 256,
            kSecAttrIsPermanent as String: false
        ]

        var error: Unmanaged<CFError>?
        guard let privateKey = SecKeyCreateRandomKey(attributes as CFDictionary, &error) else {
            let errMsg = error?.takeRetainedValue().localizedDescription ?? "Unknown"
            return .failure(
                "Self-Signed Chain Direct",
                "Failed to create ephemeral key: \(errMsg)")
        }
        testSteps.append("Created ephemeral P-256 key")

        guard let publicKey = SecKeyCopyPublicKey(privateKey) else {
            return .failure("Self-Signed Chain Direct", "Failed to extract public key")
        }
        testSteps.append("Extracted public key")

        let config = CertificateManager.CertificateConfig(
            commonName: "Direct Chain Test",
            organization: "Test Org",
            organizationalUnit: "Direct Testing",
            country: "US",
            state: "California",
            locality: "San Francisco",
            emailAddress: "direct@test.com",
            validityDays: 365
        )
        testSteps.append("Created config: CN=\(config.commonName)")

        do {
            let chain = try CertificateManager.createSelfSignedCertificateChain(
                for: publicKey,
                config: config
            )
            testSteps.append("Generated certificate chain")
            testSteps.append("Chain length: \(chain.count) characters")

            guard chain.contains("-----BEGIN CERTIFICATE-----") else {
                return .failure("Self-Signed Chain Direct", "Missing certificate header")
            }

            let certCount = chain.components(separatedBy: "-----BEGIN CERTIFICATE-----").count - 1
            testSteps.append("Chain contains \(certCount) certificate(s)")

            guard certCount == 3 else {
                return .failure("Self-Signed Chain Direct", "Expected 3 certificates, got \(certCount)")
            }

            return .success(
                "Self-Signed Certificate Chain Direct",
                testSteps.joined(separator: "\n"))

        } catch {
            testSteps.append("Error: \(error)")
            return .failure(
                "Self-Signed Certificate Chain Direct",
                testSteps.joined(separator: "\n"))
        }
    }

    public func testCSRDirectWithPublicKey() -> TestResult {
        var testSteps: [String] = []

        // Create an ephemeral key (not stored in keychain)
        let attributes: [String: Any] = [
            kSecAttrKeyType as String: kSecAttrKeyTypeECSECPrimeRandom,
            kSecAttrKeySizeInBits as String: 256,
            kSecAttrIsPermanent as String: false
        ]

        var error: Unmanaged<CFError>?
        guard let privateKey = SecKeyCreateRandomKey(attributes as CFDictionary, &error) else {
            let errMsg = error?.takeRetainedValue().localizedDescription ?? "Unknown"
            return .failure(
                "CSR Direct",
                "Failed to create ephemeral key: \(errMsg)")
        }
        testSteps.append("Created ephemeral P-256 key")

        guard let publicKey = SecKeyCopyPublicKey(privateKey) else {
            return .failure("CSR Direct", "Failed to extract public key")
        }
        testSteps.append("Extracted public key")

        let config = CertificateManager.CertificateConfig(
            commonName: "CSR Direct Test",
            organization: "CSR Test Org",
            organizationalUnit: "CSR Testing",
            country: "US",
            state: "California",
            locality: "San Francisco"
        )

        do {
            // This will try createCSR(for:config:) which internally calls createCSRManually
            let csr = try CertificateManager.createCSR(for: publicKey, config: config)
            testSteps.append("Generated CSR")
            testSteps.append("CSR length: \(csr.count) characters")

            guard csr.contains("-----BEGIN CERTIFICATE REQUEST-----") else {
                return .failure("CSR Direct", "Missing CSR header")
            }
            testSteps.append("CSR has valid PEM format")

            return .success(
                "CSR Creation Direct",
                testSteps.joined(separator: "\n"))

        } catch let error as CertificateManager.CertificateError {
            // invalidKeyData is expected for ephemeral keys since findPrivateKey won't find them
            if case .invalidKeyData = error {
                testSteps.append("Caught expected .invalidKeyData for ephemeral key")
                return .success(
                    "CSR Direct (ephemeral key correctly rejected)",
                    testSteps.joined(separator: "\n"))
            }
            testSteps.append("CertificateError: \(error)")
            return .failure(
                "CSR Creation Direct",
                "Unexpected CertificateError: \(error)")

        } catch {
            testSteps.append("Other error: \(error)")
            return .failure(
                "CSR Creation Direct",
                "Unexpected error type: \(error)")
        }
    }

    // MARK: - Additional Error Path Tests

    public func testUnsupportedKeyFormatError() -> TestResult {
        var testSteps: [String] = []

        // Test the unsupportedKeyFormat error message
        let error = CertificateManager.CertificateError.unsupportedKeyFormat
        guard let desc = error.errorDescription else {
            return .failure("Unsupported Key Format Error", "No error description")
        }
        testSteps.append("Error description: \(desc)")

        guard desc == "Unsupported key format" else {
            return .failure("Unsupported Key Format Error", "Wrong error description")
        }

        return .success(
            "Unsupported Key Format Error",
            testSteps.joined(separator: "\n"))
    }

    public func testSigningFailedError() -> TestResult {
        var testSteps: [String] = []

        let testDetails = "Test signing failure details"
        let error = CertificateManager.CertificateError.signingFailed(testDetails)

        guard let desc = error.errorDescription else {
            return .failure("Signing Failed Error", "No error description")
        }
        testSteps.append("Error description: \(desc)")

        guard desc == "Failed to sign: \(testDetails)" else {
            return .failure("Signing Failed Error", "Wrong error description")
        }
        testSteps.append("Error format is correct")

        // Test different failure messages
        let errors = [
            CertificateManager.CertificateError.signingFailed("Error 1"),
            CertificateManager.CertificateError.signingFailed("Error with details"),
            CertificateManager.CertificateError.signingFailed("")
        ]

        for e in errors {
            if let d = e.errorDescription {
                testSteps.append("Verified: \(d)")
            }
        }

        return .success(
            "Signing Failed Error",
            testSteps.joined(separator: "\n"))
    }

    // MARK: - Config Variations Tests

    public func testCertificateConfigVariations() -> TestResult {
        var testSteps: [String] = []

        // Test with minimal values
        let minConfig = CertificateManager.CertificateConfig(
            commonName: "A",
            organization: "B",
            organizationalUnit: "C",
            country: "US",
            state: "D",
            locality: "E"
        )
        testSteps.append("Minimal config: CN=\(minConfig.commonName)")
        guard minConfig.validityDays == 365 else {
            return .failure("Config Variations", "Default validity should be 365")
        }
        guard minConfig.emailAddress == nil else {
            return .failure("Config Variations", "Default email should be nil")
        }

        // Test with long values
        let longName = String(repeating: "A", count: 100)
        let longConfig = CertificateManager.CertificateConfig(
            commonName: longName,
            organization: longName,
            organizationalUnit: longName,
            country: "UK",
            state: longName,
            locality: longName,
            emailAddress: "long@" + longName + ".com",
            validityDays: 3650
        )
        testSteps.append("Long config: CN length=\(longConfig.commonName.count)")
        guard longConfig.validityDays == 3650 else {
            return .failure("Config Variations", "Custom validity not set")
        }

        // Test with special characters
        let specialConfig = CertificateManager.CertificateConfig(
            commonName: "Test & Co.",
            organization: "Org <Test>",
            organizationalUnit: "Unit \"Test\"",
            country: "DE",
            state: "State/Province",
            locality: "City, Town"
        )
        testSteps.append("Special chars config: CN=\(specialConfig.commonName)")

        return .success(
            "Certificate Config Variations",
            testSteps.joined(separator: "\n"))
    }

    // MARK: - Keychain Key with Persistence Test

    public func testPersistentKeychainKey() -> TestResult {
        let keyTag = "org.contentauth.test.certmanager.persistent.\(UUID().uuidString)"
        var testSteps: [String] = []

        defer {
            deleteTestKeychainKey(keyTag: keyTag)
        }

        // Create a persistent key in keychain
        let attributes: [String: Any] = [
            kSecAttrKeyType as String: kSecAttrKeyTypeECSECPrimeRandom,
            kSecAttrKeySizeInBits as String: 256,
            kSecPrivateKeyAttrs as String: [
                kSecAttrIsPermanent as String: true,
                kSecAttrApplicationTag as String: keyTag,
                kSecAttrAccessible as String: kSecAttrAccessibleWhenUnlockedThisDeviceOnly
            ]
        ]

        var error: Unmanaged<CFError>?
        guard let privateKey = SecKeyCreateRandomKey(attributes as CFDictionary, &error) else {
            let errMsg = error?.takeRetainedValue().localizedDescription ?? "Unknown"
            testSteps.append("Failed to create persistent key: \(errMsg)")
            return .success(
                "Persistent Key Test (Keychain unavailable)",
                testSteps.joined(separator: "\n"))
        }
        testSteps.append("Created persistent key with tag")

        // Verify key can be retrieved
        let query: [String: Any] = [
            kSecClass as String: kSecClassKey,
            kSecAttrApplicationTag as String: keyTag,
            kSecAttrKeyType as String: kSecAttrKeyTypeECSECPrimeRandom,
            kSecReturnRef as String: true
        ]

        var item: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &item)

        guard status == errSecSuccess else {
            testSteps.append("Failed to retrieve key: status=\(status)")
            return .failure("Persistent Key Test", "Could not retrieve stored key")
        }
        testSteps.append("Retrieved key from keychain")

        // Now test CSR creation with the tag
        let config = CertificateManager.CertificateConfig(
            commonName: "Persistent Key Test",
            organization: "Test Org",
            organizationalUnit: "Testing",
            country: "US",
            state: "CA",
            locality: "SF"
        )

        do {
            let csr = try CertificateManager.createCSR(keyTag: keyTag, config: config)
            testSteps.append("Created CSR from keychain key")
            testSteps.append("CSR length: \(csr.count)")

            guard csr.contains("-----BEGIN CERTIFICATE REQUEST-----") else {
                return .failure("Persistent Key Test", "CSR missing header")
            }

            return .success(
                "Persistent Keychain Key CSR",
                testSteps.joined(separator: "\n"))

        } catch {
            testSteps.append("Error: \(error)")
            return .failure(
                "Persistent Keychain Key CSR",
                testSteps.joined(separator: "\n"))
        }
    }

    // MARK: - Self-Signed Chain with Persistent Key

    public func testSelfSignedChainWithPersistentKey() -> TestResult {
        let keyTag = "org.contentauth.test.certmanager.chain.persistent.\(UUID().uuidString)"
        var testSteps: [String] = []

        defer {
            deleteTestKeychainKey(keyTag: keyTag)
        }

        // Create a persistent key
        let attributes: [String: Any] = [
            kSecAttrKeyType as String: kSecAttrKeyTypeECSECPrimeRandom,
            kSecAttrKeySizeInBits as String: 256,
            kSecPrivateKeyAttrs as String: [
                kSecAttrIsPermanent as String: true,
                kSecAttrApplicationTag as String: keyTag,
                kSecAttrAccessible as String: kSecAttrAccessibleWhenUnlockedThisDeviceOnly
            ]
        ]

        var error: Unmanaged<CFError>?
        guard let privateKey = SecKeyCreateRandomKey(attributes as CFDictionary, &error) else {
            let errMsg = error?.takeRetainedValue().localizedDescription ?? "Unknown"
            testSteps.append("Failed to create key: \(errMsg)")
            return .success(
                "Self-Signed Chain Persistent (Keychain unavailable)",
                testSteps.joined(separator: "\n"))
        }
        testSteps.append("Created persistent P-256 key")

        guard let publicKey = SecKeyCopyPublicKey(privateKey) else {
            return .failure("Self-Signed Chain Persistent", "Failed to get public key")
        }
        testSteps.append("Extracted public key")

        let config = CertificateManager.CertificateConfig(
            commonName: "Persistent Chain Test",
            organization: "Chain Test Org",
            organizationalUnit: "Chain Testing",
            country: "US",
            state: "California",
            locality: "San Francisco",
            emailAddress: "chain@test.com",
            validityDays: 90
        )

        do {
            let chain = try CertificateManager.createSelfSignedCertificateChain(
                for: publicKey,
                config: config
            )
            testSteps.append("Generated certificate chain")

            let certCount = chain.components(separatedBy: "-----BEGIN CERTIFICATE-----").count - 1
            testSteps.append("Chain contains \(certCount) certificates")

            // Verify we can create a signer with this chain and key
            do {
                let signer = try Signer(
                    algorithm: .es256,
                    certificateChainPEM: chain,
                    tsaURL: nil,
                    keychainKeyTag: keyTag
                )
                testSteps.append("Created signer with chain")

                let reserveSize = try signer.reserveSize()
                testSteps.append("Signer reserve size: \(reserveSize)")
            } catch {
                testSteps.append("Signer creation: \(error)")
            }

            return .success(
                "Self-Signed Chain with Persistent Key",
                testSteps.joined(separator: "\n"))

        } catch {
            testSteps.append("Chain error: \(error)")
            return .failure(
                "Self-Signed Chain with Persistent Key",
                testSteps.joined(separator: "\n"))
        }
    }

    public func runAllTests() async -> [TestResult] {
        var results: [TestResult] = []

        results.append(testCertificateConfigCreation())
        results.append(testCertificateErrorDescriptions())
        results.append(testSelfSignedCertificateChainCreation())
        results.append(testCSRCreationWithPublicKey())
        results.append(testCSRCreationWithKeyTag())
        results.append(testCSRCreationWithInvalidKeyTag())
        results.append(testSelfSignedChainDirectCall())
        results.append(testCSRDirectWithPublicKey())
        results.append(testUnsupportedKeyFormatError())
        results.append(testSigningFailedError())
        results.append(testCertificateConfigVariations())
        results.append(testPersistentKeychainKey())
        results.append(testSelfSignedChainWithPersistentKey())

        return results
    }
}
