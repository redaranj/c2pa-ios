import Foundation
import C2PA
import TestShared

class TestRunner {
    private let signingHelper = SigningHelper()
    
    func runAllTests() async -> [TestResult] {
        var results: [TestResult] = []
        
        // Basic C2PA initialization test
        results.append(await runTest("C2PA Version Check") {
            // C2PA is an enum with static methods, we just check the version
            let version = C2PAVersion
            return !version.isEmpty
        })
        
        // Test version retrieval
        results.append(await runTest("Get Version") {
            let version = C2PAVersion
            print("C2PA Version: \(version)")
            return !version.isEmpty
        })
        
        // Test manifest builder creation
        results.append(await runTest("Create Manifest Builder") {
            let manifest = C2PAManifest(
                claim: C2PAClaim(
                    generator: "TestApp",
                    title: "Test Manifest",
                    format: "image/jpeg"
                ),
                assertions: []
            )
            // Just test we can create a manifest
            return manifest.claim.generator == "TestApp"
        })
        
        // Test signing helper from TestShared
        results.append(await runTest("Signing Helper") {
            // Test that we can generate test data using SigningHelper
            if let testData = signingHelper.generateTestImageData() {
                return !testData.isEmpty
            }
            return false
        })
        
        // Test hardware signing availability
        if #available(iOS 13.0, macOS 10.15, *) {
            results.append(await runTest("Hardware Signing Config") {
                let config = SecureEnclaveSignerConfig(
                    keyTag: "com.example.c2pa.test.secure.key"
                )
                
                // Just test if we can create the configuration
                // Actual key creation will fail in simulator
                return config.keyTag == "com.example.c2pa.test.secure.key"
            })
        }
        
        // Test certificate generation (from TestShared)
        results.append(await runTest("Generate Test Certificate") {
            do {
                let cert = try signingHelper.generateTestCertificate(
                    commonName: "Test App",
                    organizationName: "Test Organization"
                )
                return !cert.isEmpty
            } catch {
                print("Certificate generation error: \(error)")
                return false
            }
        })
        
        // Test CSR creation
        results.append(await runTest("Create CSR") {
            do {
                let csr = try signingHelper.createTestCSR(
                    commonName: "Test User",
                    organizationName: "Test Org"
                )
                return !csr.isEmpty
            } catch {
                print("CSR creation error: \(error)")
                return false
            }
        })
        
        return results
    }
    
    private func runTest(_ name: String, test: () async throws -> Bool) async -> TestResult {
        do {
            let passed = try await test()
            return TestResult(name: name, passed: passed, error: nil)
        } catch {
            return TestResult(name: name, passed: false, error: error.localizedDescription)
        }
    }
}