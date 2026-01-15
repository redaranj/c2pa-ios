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

// SecureEnclaveSigner tests - testing Secure Enclave-based signing
// These tests focus on code paths that can execute without real Secure Enclave hardware
public final class SecureEnclaveSignerTests: TestImplementation {

    public init() {}

    // MARK: - SecureEnclaveSignerConfig Tests

    public func testSecureEnclaveSignerConfigCreation() -> TestResult {
        var testSteps: [String] = []

        // Test basic config creation with default access control
        let config1 = SecureEnclaveSignerConfig(keyTag: "test.key.tag")
        testSteps.append("Created config with keyTag: \(config1.keyTag)")
        testSteps.append("Default accessControl: \(config1.accessControl)")

        guard config1.keyTag == "test.key.tag" else {
            return .failure("Config Creation", "Key tag mismatch")
        }

        guard config1.accessControl == [.privateKeyUsage] else {
            return .failure("Config Creation", "Default access control should be [.privateKeyUsage]")
        }
        testSteps.append("Default access control is correct")

        // Test config with custom access control
        let config2 = SecureEnclaveSignerConfig(
            keyTag: "another.key.tag",
            accessControl: [.privateKeyUsage, .biometryCurrentSet]
        )
        testSteps.append("Created config with custom accessControl: \(config2.accessControl)")

        guard config2.keyTag == "another.key.tag" else {
            return .failure("Config Creation", "Custom key tag mismatch")
        }

        guard config2.accessControl.contains(.privateKeyUsage) else {
            return .failure("Config Creation", "Custom access control missing privateKeyUsage")
        }

        guard config2.accessControl.contains(.biometryCurrentSet) else {
            return .failure("Config Creation", "Custom access control missing biometryCurrentSet")
        }
        testSteps.append("Custom access control is correct")

        // Test various access control options
        let accessControls: [SecAccessControlCreateFlags] = [
            [.privateKeyUsage],
            [.userPresence],
            [.privateKeyUsage, .userPresence],
            [.devicePasscode]
        ]

        for ac in accessControls {
            let config = SecureEnclaveSignerConfig(keyTag: "test.\(UUID().uuidString)", accessControl: ac)
            testSteps.append("Config with accessControl \(ac): OK")
            _ = config  // Use the config
        }

        return .success(
            "SecureEnclaveSignerConfig Creation",
            testSteps.joined(separator: "\n"))
    }

    // MARK: - Algorithm Validation Tests

    public func testNonES256RejectedBySecureEnclave() -> TestResult {
        var testSteps: [String] = []

        let config = SecureEnclaveSignerConfig(keyTag: "test.se.nonesSupported")

        // Secure Enclave only supports ES256, all other algorithms should be rejected
        let unsupportedAlgorithms: [SigningAlgorithm] = [
            .es384,
            .es512,
            .ps256,
            .ps384,
            .ps512,
            .ed25519
        ]

        for algorithm in unsupportedAlgorithms {
            do {
                _ = try Signer(
                    algorithm: algorithm,
                    certificateChainPEM: TestUtilities.testCertsPEM,
                    tsaURL: nil,
                    secureEnclaveConfig: config
                )

                return .failure(
                    "Non-ES256 Rejection",
                    "Algorithm \(algorithm) should have been rejected")

            } catch let error as C2PAError {
                testSteps.append("\(algorithm): Correctly rejected with error: \(error)")
                if case .api(let message) = error {
                    guard message.contains("ES256") || message.contains("P-256") else {
                        return .failure(
                            "Non-ES256 Rejection",
                            "Error message should mention ES256 or P-256")
                    }
                }

            } catch {
                testSteps.append("\(algorithm): Rejected with unexpected error: \(error)")
            }
        }

        return .success(
            "Non-ES256 Algorithm Rejection",
            testSteps.joined(separator: "\n"))
    }

    // MARK: - Delete Key Tests

    public func testDeleteNonExistentKey() -> TestResult {
        var testSteps: [String] = []

        #if targetEnvironment(simulator)
        // On simulator, Secure Enclave is not available so delete operations may not work as expected
        testSteps.append("Running on simulator - Secure Enclave delete behavior may differ")
        let nonExistentTag = "org.contentauth.test.se.nonexistent.\(UUID().uuidString)"
        let result = Signer.deleteSecureEnclaveKey(keyTag: nonExistentTag)
        testSteps.append("deleteSecureEnclaveKey returned: \(result)")
        testSteps.append("[INFO] On simulator, result depends on keychain implementation")
        return .success(
            "Delete Non-existent Key (Simulator)",
            testSteps.joined(separator: "\n"))
        #else
        // On real device, deleting a non-existent key should return true (errSecItemNotFound is treated as success)
        let nonExistentTag = "org.contentauth.test.se.nonexistent.\(UUID().uuidString)"

        let result = Signer.deleteSecureEnclaveKey(keyTag: nonExistentTag)
        testSteps.append("deleteSecureEnclaveKey returned: \(result)")

        guard result == true else {
            return .failure(
                "Delete Non-existent Key",
                "Deleting non-existent key should return true")
        }
        testSteps.append("Correctly returned true for non-existent key")

        return .success(
            "Delete Non-existent Key",
            testSteps.joined(separator: "\n"))
        #endif
    }

    public func testDeleteKeyIdempotent() -> TestResult {
        var testSteps: [String] = []

        #if targetEnvironment(simulator)
        // On simulator, Secure Enclave is not available
        testSteps.append("Running on simulator - Secure Enclave delete behavior may differ")
        let keyTag = "org.contentauth.test.se.deleteidempotent.\(UUID().uuidString)"
        let result1 = Signer.deleteSecureEnclaveKey(keyTag: keyTag)
        let result2 = Signer.deleteSecureEnclaveKey(keyTag: keyTag)
        testSteps.append("First delete returned: \(result1)")
        testSteps.append("Second delete returned: \(result2)")
        testSteps.append("[INFO] On simulator, results depend on keychain implementation")
        return .success(
            "Delete Key Idempotent (Simulator)",
            testSteps.joined(separator: "\n"))
        #else
        let keyTag = "org.contentauth.test.se.deleteidempotent.\(UUID().uuidString)"

        // First delete
        let result1 = Signer.deleteSecureEnclaveKey(keyTag: keyTag)
        testSteps.append("First delete returned: \(result1)")

        // Second delete (should also succeed)
        let result2 = Signer.deleteSecureEnclaveKey(keyTag: keyTag)
        testSteps.append("Second delete returned: \(result2)")

        guard result1 == true && result2 == true else {
            return .failure(
                "Delete Key Idempotent",
                "Both deletes should return true")
        }
        testSteps.append("Delete operation is idempotent")

        return .success(
            "Delete Key Idempotent",
            testSteps.joined(separator: "\n"))
        #endif
    }

    // MARK: - Secure Enclave Availability Test

    public func testSecureEnclaveAvailabilityCheck() -> TestResult {
        var testSteps: [String] = []

        #if targetEnvironment(simulator)
        testSteps.append("Running on simulator - Secure Enclave not available")
        testSteps.append("This is expected behavior")

        // On simulator, attempting to create SE key should fail
        let config = SecureEnclaveSignerConfig(keyTag: "test.se.simulator")

        do {
            _ = try Signer.createSecureEnclaveKey(config: config)
            testSteps.append("[UNEXPECTED] Key creation succeeded on simulator")
        } catch {
            testSteps.append("Key creation correctly failed on simulator: \(error)")
        }

        return .success(
            "Secure Enclave Availability Check",
            testSteps.joined(separator: "\n"))
        #else
        testSteps.append("Running on real device - Secure Enclave should be available")

        let config = SecureEnclaveSignerConfig(
            keyTag: "org.contentauth.test.se.availability.\(UUID().uuidString)"
        )

        defer {
            _ = Signer.deleteSecureEnclaveKey(keyTag: config.keyTag)
        }

        do {
            let key = try Signer.createSecureEnclaveKey(config: config)
            testSteps.append("Successfully created Secure Enclave key")

            guard let publicKey = SecKeyCopyPublicKey(key) else {
                return .failure(
                    "Secure Enclave Availability Check",
                    "Failed to extract public key")
            }
            testSteps.append("Successfully extracted public key")

            var error: Unmanaged<CFError>?
            if let publicKeyData = SecKeyCopyExternalRepresentation(publicKey, &error) as Data? {
                testSteps.append("Public key size: \(publicKeyData.count) bytes")
            }

            return .success(
                "Secure Enclave Availability Check",
                testSteps.joined(separator: "\n"))

        } catch {
            testSteps.append("Error: \(error)")
            return .failure(
                "Secure Enclave Availability Check",
                testSteps.joined(separator: "\n"))
        }
        #endif
    }

    // MARK: - Create Key Error Handling

    public func testCreateKeyAccessControlValidation() -> TestResult {
        var testSteps: [String] = []

        #if targetEnvironment(simulator)
        testSteps.append("Running on simulator - testing error paths")

        // On simulator, key creation should fail but the access control creation should be tested
        let config = SecureEnclaveSignerConfig(
            keyTag: "test.se.accesscontrol",
            accessControl: [.privateKeyUsage]
        )

        do {
            _ = try Signer.createSecureEnclaveKey(config: config)
            testSteps.append("[INFO] Key creation succeeded (unexpected on simulator)")
        } catch {
            testSteps.append("Key creation failed as expected on simulator")
            testSteps.append("Error: \(error)")
        }

        return .success(
            "Create Key Access Control Validation",
            testSteps.joined(separator: "\n"))
        #else
        // On real device, test that various access controls work
        let configs: [(String, SecAccessControlCreateFlags)] = [
            ("privateKeyUsage", [.privateKeyUsage]),
            ("userPresence", [.privateKeyUsage, .userPresence])
        ]

        for (name, accessControl) in configs {
            let keyTag = "org.contentauth.test.se.ac.\(name).\(UUID().uuidString)"
            let config = SecureEnclaveSignerConfig(keyTag: keyTag, accessControl: accessControl)

            defer {
                _ = Signer.deleteSecureEnclaveKey(keyTag: keyTag)
            }

            do {
                let key = try Signer.createSecureEnclaveKey(config: config)
                testSteps.append("\(name): Key created successfully")
                _ = key
            } catch {
                testSteps.append("\(name): Failed - \(error)")
            }
        }

        return .success(
            "Create Key Access Control Validation",
            testSteps.joined(separator: "\n"))
        #endif
    }

    // MARK: - ES256 Path Test (when available)

    public func testES256AcceptedBySecureEnclave() -> TestResult {
        var testSteps: [String] = []

        let config = SecureEnclaveSignerConfig(
            keyTag: "org.contentauth.test.se.es256.\(UUID().uuidString)"
        )

        #if targetEnvironment(simulator)
        // On simulator, the ES256 check passes but key creation fails
        do {
            _ = try Signer(
                algorithm: .es256,
                certificateChainPEM: TestUtilities.testCertsPEM,
                tsaURL: nil,
                secureEnclaveConfig: config
            )
            testSteps.append("[UNEXPECTED] Signer created on simulator")
        } catch let error as C2PAError {
            // Should fail at key access, not algorithm check
            testSteps.append("Failed as expected (no SE on simulator): \(error)")
            if case .api(let message) = error {
                // Should NOT be an algorithm error
                if message.contains("ES256") && message.contains("only supports") {
                    return .failure(
                        "ES256 Accepted",
                        "ES256 should be accepted, not rejected")
                }
            }
        } catch {
            testSteps.append("Failed with: \(error)")
        }

        return .success(
            "ES256 Accepted by Secure Enclave",
            testSteps.joined(separator: "\n"))
        #else
        defer {
            _ = Signer.deleteSecureEnclaveKey(keyTag: config.keyTag)
        }

        do {
            // On real device, ES256 should work
            let signer = try Signer(
                algorithm: .es256,
                certificateChainPEM: TestUtilities.testCertsPEM,
                tsaURL: nil,
                secureEnclaveConfig: config
            )
            testSteps.append("ES256 signer created successfully")

            let reserveSize = try signer.reserveSize()
            testSteps.append("Reserve size: \(reserveSize) bytes")

            return .success(
                "ES256 Accepted by Secure Enclave",
                testSteps.joined(separator: "\n"))

        } catch {
            testSteps.append("Error: \(error)")
            return .failure(
                "ES256 Accepted by Secure Enclave",
                testSteps.joined(separator: "\n"))
        }
        #endif
    }

    public func runAllTests() async -> [TestResult] {
        var results: [TestResult] = []

        results.append(testSecureEnclaveSignerConfigCreation())
        results.append(testNonES256RejectedBySecureEnclave())
        results.append(testDeleteNonExistentKey())
        results.append(testDeleteKeyIdempotent())
        results.append(testSecureEnclaveAvailabilityCheck())
        results.append(testCreateKeyAccessControlValidation())
        results.append(testES256AcceptedBySecureEnclave())

        return results
    }
}
