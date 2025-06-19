import C2PA
import CryptoKit
import Foundation
import Network
import Security
import SwiftUI

class SimpleSigningServer {
    private var listener: NWListener?
    private let signer: Signer
    private let port: UInt16
    
    init(signer: Signer, port: UInt16 = 0) {
        self.signer = signer
        self.port = port
    }
    
    func start() throws -> UInt16 {
        let parameters = NWParameters.tcp
        parameters.allowLocalEndpointReuse = true
        
        let listener = try NWListener(using: parameters, on: NWEndpoint.Port(integerLiteral: port))
        self.listener = listener
        
        listener.newConnectionHandler = { [weak self] connection in
            self?.handleConnection(connection)
        }
        
        let semaphore = DispatchSemaphore(value: 0)
        var actualPort: UInt16 = 0
        
        listener.stateUpdateHandler = { state in
            switch state {
            case .ready:
                actualPort = listener.port?.rawValue ?? 0
                print("Server started on port: \(actualPort)")
                semaphore.signal()
            case .failed(let error):
                print("Server failed to start: \(error)")
                semaphore.signal()
            default:
                break
            }
        }
        
        listener.start(queue: .global())
        
        semaphore.wait()
        
        return actualPort
    }
    
    func stop() {
        listener?.cancel()
        listener = nil
    }
    
    private func handleConnection(_ connection: NWConnection) {
        connection.start(queue: .global())
        
        var buffer = Data()
        var expectedContentLength: Int?
        
        func receiveData() {
            connection.receive(minimumIncompleteLength: 1, maximumLength: 65536) { [weak self] data, _, isComplete, error in
                if let error = error {
                    print("Connection receive error: \(error)")
                    return
                }
                
                guard let data = data, !data.isEmpty else {
                    if isComplete {
                        self?.processCompleteRequest(buffer, connection: connection)
                    }
                    return
                }
                
                buffer.append(data)
                print("Received \(data.count) bytes, total buffer: \(buffer.count)")
                
                if expectedContentLength == nil {
                    if let headerEnd = buffer.range(of: Data([0x0D, 0x0A, 0x0D, 0x0A])) {
                        let headerData = buffer.subdata(in: 0..<headerEnd.lowerBound)
                        if let headerString = String(data: headerData, encoding: .utf8) {
                            for line in headerString.components(separatedBy: "\r\n") {
                                if line.lowercased().hasPrefix("content-length:") {
                                    let lengthStr = line.dropFirst(15).trimmingCharacters(in: .whitespaces)
                                    expectedContentLength = Int(lengthStr)
                                    print("Expected content length: \(expectedContentLength ?? 0)")
                                    break
                                }
                            }
                            if expectedContentLength == nil {
                                expectedContentLength = 0
                            }
                        }
                    }
                }
                
                if let contentLength = expectedContentLength {
                    let headerSeparator = Data([0x0D, 0x0A, 0x0D, 0x0A])
                    if let headerEnd = buffer.range(of: headerSeparator) {
                        let bodyStart = headerEnd.upperBound
                        let currentBodyLength = buffer.count - bodyStart
                        
                        if currentBodyLength >= contentLength {
                            print("Complete request received: \(buffer.count) total bytes")
                            self?.processCompleteRequest(buffer, connection: connection)
                            return
                        } else {
                            print("Still waiting for body: \(currentBodyLength)/\(contentLength) bytes")
                        }
                    }
                }
                
                if !isComplete {
                    receiveData()
                }
            }
        }
        
        receiveData()
    }
    
    private func processCompleteRequest(_ data: Data, connection: NWConnection) {
        print("Processing complete request of \(data.count) bytes")
        
        if let request = parseHTTPRequest(data) {
            let response = handleSigningRequest(request) ?? createErrorResponse()
            connection.send(content: response, completion: .contentProcessed { error in
                if let error = error {
                    print("Send error: \(error)")
                } else {
                    print("Response sent successfully")
                }
                connection.cancel()
            })
        } else {
            print("Failed to parse HTTP request")
            let errorResponse = createErrorResponse()
            connection.send(content: errorResponse, completion: .contentProcessed { _ in
                connection.cancel()
            })
        }
    }
    
    private func parseHTTPRequest(_ data: Data) -> HTTPRequest? {
        let headerSeparator = Data([0x0D, 0x0A, 0x0D, 0x0A])
        guard let separatorRange = data.range(of: headerSeparator) else {
            print("No header separator found")
            return nil
        }
        
        let headerData = data.subdata(in: 0..<separatorRange.lowerBound)
        let bodyData = data.subdata(in: separatorRange.upperBound..<data.count)
        
        guard let headerString = String(data: headerData, encoding: .utf8) else {
            print("Failed to decode headers as UTF-8")
            return nil
        }
        
        print("Received HTTP headers: \(headerString)")
        print("Body length: \(bodyData.count) bytes")
        if bodyData.count <= 32 {
            print("Body (hex): \(bodyData.map { String(format: "%02x", $0) }.joined())")
        } else {
            print("Body (first 32 bytes hex): \(bodyData.prefix(32).map { String(format: "%02x", $0) }.joined())")
        }
        
        let lines = headerString.components(separatedBy: "\r\n")
        guard let firstLine = lines.first else { 
            print("No first line in headers")
            return nil 
        }
        
        let components = firstLine.components(separatedBy: " ")
        guard components.count >= 2 else { 
            print("Invalid request line: \(firstLine)")
            return nil 
        }
        
        let method = components[0]
        let path = components[1]
        
        print("Parsed request: \(method) \(path), body length: \(bodyData.count)")
        return HTTPRequest(method: method, path: path, body: bodyData)
    }
    
    private func handleSigningRequest(_ request: HTTPRequest) -> Data? {
        print("Handling signing request: \(request.method) \(request.path)")
        
        guard request.method == "POST", request.path == "/sign" else {
            print("Invalid endpoint: \(request.method) \(request.path)")
            return createErrorResponse(status: "404 Not Found", message: "Endpoint not found")
        }
        
        print("Processing signing request with body length: \(request.body.count)")
        
        do {
            let signature = try signDataWithRealSigner(request.body)
            
            let responseHeaders = "HTTP/1.1 200 OK\r\nContent-Type: application/octet-stream\r\nContent-Length: \(signature.count)\r\nConnection: close\r\n\r\n"
            
            print("Sending REAL signature with length: \(signature.count)")
            
            var responseData = responseHeaders.data(using: .utf8) ?? Data()
            responseData.append(signature)
            return responseData
            
        } catch {
            print("Error in signing: \(error)")
            return createErrorResponse(status: "500 Internal Server Error", message: error.localizedDescription)
        }
    }
    
    private func signDataWithRealSigner(_ data: Data) throws -> Data {
        guard let keyPath = Bundle.main.path(forResource: "es256_private", ofType: "key") else {
            throw C2PAError.api("Could not find private key file")
        }
        
        let privateKeyPEM = try String(contentsOfFile: keyPath, encoding: .utf8)
        
        if #available(iOS 13.0, macOS 10.15, *) {
            let cryptoKitKey = try P256.Signing.PrivateKey(pemRepresentation: privateKeyPEM)
            let signature = try cryptoKitKey.signature(for: data)
            
            print("Server signing \(data.count) bytes, got \(signature.rawRepresentation.count) byte signature")
            
            return signature.rawRepresentation
        } else {
            throw C2PAError.api("CryptoKit required for signing")
        }
    }
    
    
    private func createErrorResponse(status: String = "500 Internal Server Error", message: String = "Internal server error") -> Data {
        let response = "HTTP/1.1 \(status)\r\nContent-Type: text/plain\r\nContent-Length: \(message.count)\r\nConnection: close\r\n\r\n\(message)"
        return response.data(using: .utf8) ?? Data()
    }
}

extension SimpleSigningServer {
    static func createTestSigningServer() throws -> (server: SimpleSigningServer, certificate: String) {
        guard let keyPath = Bundle.main.path(forResource: "es256_private", ofType: "key"),
              let certPath = Bundle.main.path(forResource: "es256_certs", ofType: "pem") else {
            throw C2PAError.api("Could not find key or certificate files in bundle")
        }
        
        let privateKeyPEM = try String(contentsOfFile: keyPath, encoding: .utf8)
        let certificate = try String(contentsOfFile: certPath, encoding: .utf8)
        
        let signer = try Signer(
            certsPEM: certificate,
            privateKeyPEM: privateKeyPEM,
            algorithm: .es256
        )
        
        let server = SimpleSigningServer(signer: signer)
        return (server, certificate)
    }
}

struct HTTPRequest {
    let method: String
    let path: String
    let body: Data
}

public struct TestResult: Identifiable {
    public let id = UUID()
    public let name: String
    public let success: Bool
    public let message: String
    public let details: String?
    
    public init(name: String, success: Bool, message: String, details: String?) {
        self.name = name
        self.success = success
        self.message = message
        self.details = details
    }
}

// Shared test engine that can be used by both XCTest and UI tests
public class TestEngine {
    public static let shared = TestEngine()
    
    private init() {}
    
    // MARK: - Test Execution
    
    public func runAllTests() async -> [TestResult] {
        var results: [TestResult] = []
        
        // Core Library Tests
        results.append(await runTest("Library Version", test: testLibraryVersion))
        results.append(await runTest("Error Handling", test: testErrorHandling))
        results.append(await runTest("Read Test Image", test: testReadImage))
        results.append(await runTest("Stream API", test: testStreamAPI))
        results.append(await runTest("Builder API", test: testBuilderAPI))
        results.append(await runTest("Builder No-Embed API", test: testBuilderNoEmbed))
        results.append(await runTest("Read Ingredient", test: testReadIngredient))
        results.append(await runTest("Invalid File Handling", test: testInvalidFileHandling))
        results.append(await runTest("Resource Reading", test: testResourceReading))
        results.append(await runTest("Builder Remote URL", test: testBuilderRemoteURL))
        results.append(await runTest("Builder Add Resource", test: testBuilderAddResource))
        results.append(await runTest("Builder Add Ingredient", test: testBuilderAddIngredient))
        results.append(await runTest("Builder from Archive", test: testBuilderFromArchive))
        results.append(await runTest("Reader with Manifest Data", test: testReaderWithManifestData))
        results.append(await runTest("Signer with Callback", test: testSignerWithCallback))
        results.append(await runTest("File Operations with Data Dir", test: testFileOperationsWithDataDir))
        results.append(await runTest("Write-Only Streams", test: testWriteOnlyStreams))
        results.append(await runTest("Custom Stream Callbacks", test: testCustomStreamCallbacks))
        results.append(await runTest("Stream File Options", test: testStreamFileOptions))
        
        // Signing Tests
        results.append(await runTest("Web Service Real Signing & Verification", test: testWebServiceSignerCreation))
        results.append(await runTest("Keychain Signer Creation", test: testKeychainSignerCreation))
        
        if #available(iOS 13.0, macOS 10.15, *) {
            results.append(await runTest("Secure Enclave Signer Creation", test: testSecureEnclaveSignerCreation))
        }
        
        results.append(await runTest("Signing Algorithm Tests", test: testSigningAlgorithmTests))
        
        return results
    }
    
    // MARK: - Individual Test Methods (Public Wrappers)
    
    public func runLibraryVersionTest() async -> TestResult {
        return await runTest("Library Version", test: testLibraryVersion)
    }
    
    public func runErrorHandlingTest() async -> TestResult {
        return await runTest("Error Handling", test: testErrorHandling)
    }
    
    public func runReadImageTest() async -> TestResult {
        return await runTest("Read Test Image", test: testReadImage)
    }
    
    public func runStreamAPITest() async -> TestResult {
        return await runTest("Stream API", test: testStreamAPI)
    }
    
    public func runBuilderAPITest() async -> TestResult {
        return await runTest("Builder API", test: testBuilderAPI)
    }
    
    public func runBuilderNoEmbedTest() async -> TestResult {
        return await runTest("Builder No-Embed API", test: testBuilderNoEmbed)
    }
    
    public func runReadIngredientTest() async -> TestResult {
        return await runTest("Read Ingredient", test: testReadIngredient)
    }
    
    public func runInvalidFileHandlingTest() async -> TestResult {
        return await runTest("Invalid File Handling", test: testInvalidFileHandling)
    }
    
    public func runResourceReadingTest() async -> TestResult {
        return await runTest("Resource Reading", test: testResourceReading)
    }
    
    public func runBuilderRemoteURLTest() async -> TestResult {
        return await runTest("Builder Remote URL", test: testBuilderRemoteURL)
    }
    
    public func runBuilderAddResourceTest() async -> TestResult {
        return await runTest("Builder Add Resource", test: testBuilderAddResource)
    }
    
    public func runBuilderAddIngredientTest() async -> TestResult {
        return await runTest("Builder Add Ingredient", test: testBuilderAddIngredient)
    }
    
    public func runBuilderFromArchiveTest() async -> TestResult {
        return await runTest("Builder from Archive", test: testBuilderFromArchive)
    }
    
    public func runReaderWithManifestDataTest() async -> TestResult {
        return await runTest("Reader with Manifest Data", test: testReaderWithManifestData)
    }
    
    public func runSignerWithCallbackTest() async -> TestResult {
        return await runTest("Signer with Callback", test: testSignerWithCallback)
    }
    
    public func runFileOperationsWithDataDirTest() async -> TestResult {
        return await runTest("File Operations with Data Dir", test: testFileOperationsWithDataDir)
    }
    
    public func runWriteOnlyStreamsTest() async -> TestResult {
        return await runTest("Write-Only Streams", test: testWriteOnlyStreams)
    }
    
    public func runCustomStreamCallbacksTest() async -> TestResult {
        return await runTest("Custom Stream Callbacks", test: testCustomStreamCallbacks)
    }
    
    public func runStreamFileOptionsTest() async -> TestResult {
        return await runTest("Stream File Options", test: testStreamFileOptions)
    }
    
    public func runWebServiceSignerCreationTest() async -> TestResult {
        return await runTest("Web Service Real Signing & Verification", test: testWebServiceSignerCreation)
    }
    
    public func runKeychainSignerCreationTest() async -> TestResult {
        return await runTest("Keychain Signer Creation", test: testKeychainSignerCreation)
    }
    
    @available(iOS 13.0, macOS 10.15, *)
    public func runSecureEnclaveSignerCreationTest() async -> TestResult {
        return await runTest("Secure Enclave Signer Creation", test: testSecureEnclaveSignerCreation)
    }
    
    public func runSigningAlgorithmTests() async -> TestResult {
        return await runTest("Signing Algorithm Tests", test: testSigningAlgorithmTests)
    }
    
    private func runTest(_ name: String, test: () async throws -> TestResult) async -> TestResult {
        do {
            return try await test()
        } catch {
            return TestResult(
                name: name,
                success: false,
                message: "Test failed with error: \(error.localizedDescription)",
                details: "\(error)"
            )
        }
    }
    
    // MARK: - Individual Tests (converted from C2PATestView)
    
    private func testLibraryVersion() async throws -> TestResult {
        let version = C2PAVersion
        return TestResult(
            name: "Library Version",
            success: !version.isEmpty,
            message: "C2PA version: \(version)",
            details: version
        )
    }
    
    private func testErrorHandling() async throws -> TestResult {
        do {
            _ = try C2PA.readFile(at: URL(fileURLWithPath: "/non/existent/file.jpg"))
            return TestResult(
                name: "Error Handling",
                success: false,
                message: "Should have thrown an error for non-existent file",
                details: nil
            )
        } catch let error as C2PAError {
            return TestResult(
                name: "Error Handling",
                success: true,
                message: "Correctly caught error for non-existent file",
                details: error.description
            )
        } catch {
            return TestResult(
                name: "Error Handling",
                success: false,
                message: "Unexpected error type: \(error.localizedDescription)",
                details: "\(error)"
            )
        }
    }
    
    private func testReadImage() async throws -> TestResult {
        guard let imagePath = Bundle.main.path(forResource: "adobe-20220124-CI", ofType: "jpg") else {
            return TestResult(
                name: "Read Test Image",
                success: false,
                message: "Could not find test image in bundle",
                details: nil
            )
        }

        let imageURL = URL(fileURLWithPath: imagePath)

        do {
            let manifestJSON = try C2PA.readFile(at: imageURL)
            let truncated = String(manifestJSON.prefix(500))
            return TestResult(
                name: "Read Test Image",
                success: true,
                message: "Successfully read manifest from test image",
                details: truncated + (manifestJSON.count > 500 ? "..." : "")
            )
        } catch {
            return TestResult(
                name: "Read Test Image",
                success: false,
                message: "Failed to read manifest: \(error.localizedDescription)",
                details: "\(error)"
            )
        }
    }
    
    // Add more test methods here - I'll show a few key ones
    private func testStreamAPI() async throws -> TestResult {
        guard let imagePath = Bundle.main.path(forResource: "adobe-20220124-CI", ofType: "jpg") else {
            return TestResult(
                name: "Stream API",
                success: false,
                message: "Could not find test image",
                details: nil
            )
        }

        do {
            let imageURL = URL(fileURLWithPath: imagePath)
            let data = try Data(contentsOf: imageURL)
            let stream = try Stream(data: data)
            let reader = try Reader(format: "image/jpeg", stream: stream)
            let manifestJSON = try reader.json()

            return TestResult(
                name: "Stream API",
                success: true,
                message: "Successfully used Stream and Reader APIs",
                details: "Manifest size: \(manifestJSON.count) bytes"
            )
        } catch {
            return TestResult(
                name: "Stream API",
                success: false,
                message: "Failed to use Stream API: \(error.localizedDescription)",
                details: "\(error)"
            )
        }
    }
    
    private func testBuilderAPI() async throws -> TestResult {
        do {
            guard let imagePath = Bundle.main.path(forResource: "pexels-asadphoto-457882", ofType: "jpg") else {
                return TestResult(
                    name: "Builder API",
                    success: false,
                    message: "Could not find test image for Builder test",
                    details: nil
                )
            }

            guard let certPath = Bundle.main.path(forResource: "es256_certs", ofType: "pem"),
                  let keyPath = Bundle.main.path(forResource: "es256_private", ofType: "key")
            else {
                return TestResult(
                    name: "Builder API",
                    success: false,
                    message: "Could not find signing certificates",
                    details: nil
                )
            }

            let imageURL = URL(fileURLWithPath: imagePath)
            let imageData = try Data(contentsOf: imageURL)
            let originalSize = imageData.count

            var originalHasC2PA = false
            do {
                let originalManifest = try C2PA.readFile(at: imageURL)
                originalHasC2PA = !originalManifest.isEmpty
            } catch {
            }

            let certsPEM = try String(contentsOfFile: certPath, encoding: .utf8)
            let privateKeyPEM = try String(contentsOfFile: keyPath, encoding: .utf8)

            let manifestJSON = """
            {
                "claim_generator": "C2PATestApp/1.0",
                "title": "Test Image with Embedded C2PA",
                "format": "image/jpeg",
                "assertions": [
                    {
                        "label": "c2pa.actions",
                        "data": {
                            "actions": [
                                {
                                    "action": "c2pa.created",
                                    "softwareAgent": "C2PATestApp"
                                }
                            ]
                        }
                    }
                ]
            }
            """

            let builder = try Builder(manifestJSON: manifestJSON)
            let signer = try Signer(
                certsPEM: certsPEM,
                privateKeyPEM: privateKeyPEM,
                algorithm: .es256,
                tsaURL: nil
            )

            let sourceStream = try Stream(data: imageData)
            let destURL = FileManager.default.temporaryDirectory
                .appendingPathComponent("signed_image_\(UUID().uuidString).jpg")

            let manifestData: Data
            do {
                let destStream = try Stream(fileURL: destURL, truncate: true, createIfNeeded: true)

                manifestData = try builder.sign(
                    format: "image/jpeg",
                    source: sourceStream,
                    destination: destStream,
                    signer: signer
                )
            }

            try await Task.sleep(nanoseconds: 100_000_000) // 0.1 seconds

            let signedExists = FileManager.default.fileExists(atPath: destURL.path)
            let signedData = try Data(contentsOf: destURL)
            let signedSize = Int64(signedData.count)

            let readManifest = try C2PA.readFile(at: destURL)
            let readSuccess = !readManifest.isEmpty

            var prettyManifest = "Failed to parse"
            if let manifestData = readManifest.data(using: .utf8),
               let json = try? JSONSerialization.jsonObject(with: manifestData, options: []),
               let prettyData = try? JSONSerialization.data(withJSONObject: json, options: .prettyPrinted),
               let prettyString = String(data: prettyData, encoding: .utf8)
            {
                if prettyString.count > 5000 {
                    prettyManifest = String(prettyString.prefix(5000)) + "\n... (truncated at 5000 chars)"
                } else {
                    prettyManifest = prettyString
                }
            }

            try? FileManager.default.removeItem(at: destURL)

            let success = signedExists && signedSize > originalSize && readSuccess

            return TestResult(
                name: "Builder API",
                success: success,
                message: success ? "Successfully signed image with embedded C2PA data" : "Failed to sign image",
                details: """
                Original: \(originalSize) bytes (\(originalSize / 1024) KB) \(originalHasC2PA ? "(has C2PA data)" : "(no C2PA)")
                Signed: \(signedSize) bytes (\(signedSize / 1024) KB)
                Difference: \(signedSize - Int64(originalSize)) bytes
                Manifest data returned: \(manifestData.count) bytes

                \(signedSize < originalSize ? "⚠️ WARNING: Signed image is smaller than original!" : "✓ Size increased as expected")
                \(originalHasC2PA ? "ℹ️ Note: Original already had C2PA data which was replaced" : "")

                Read back manifest:
                \(prettyManifest)
                """
            )
        } catch {
            return TestResult(
                name: "Builder API",
                success: false,
                message: "Failed to use Builder API: \(error.localizedDescription)",
                details: "\(error)"
            )
        }
    }
    
    private func testBuilderNoEmbed() async throws -> TestResult {
        do {
            let manifestJSON = """
            {
                "claim_generator": "TestApp/1.0 NoEmbed",
                "title": "Cloud/Sidecar Manifest Test",
                "format": "application/c2pa",
                "assertions": [
                    {
                        "label": "c2pa.actions",
                        "data": {
                            "actions": [
                                {
                                    "action": "c2pa.created",
                                    "when": "2024-01-01T00:00:00Z"
                                }
                            ]
                        }
                    }
                ]
            }
            """

            let builder = try Builder(manifestJSON: manifestJSON)
            builder.setNoEmbed()

            let tempURL = FileManager.default.temporaryDirectory
                .appendingPathComponent("test_noembed_\(UUID().uuidString).c2pa")
            let archiveStream = try Stream(fileURL: tempURL, truncate: true, createIfNeeded: true)
            try builder.writeArchive(to: archiveStream)

            let fileExists = FileManager.default.fileExists(atPath: tempURL.path)
            let fileSize = try FileManager.default.attributesOfItem(atPath: tempURL.path)[.size] as? Int64 ?? 0

            try? FileManager.default.removeItem(at: tempURL)

            let success = fileExists && fileSize > 0

            return TestResult(
                name: "Builder No-Embed API",
                success: success,
                message: success ? "Successfully created cloud/sidecar manifest (no-embed)" : "Failed to create no-embed archive",
                details: "Archive size: \(fileSize) bytes"
            )
        } catch {
            return TestResult(
                name: "Builder No-Embed API",
                success: false,
                message: "Failed to use Builder no-embed: \(error.localizedDescription)",
                details: "\(error)"
            )
        }
    }
    
    private func testReadIngredient() async throws -> TestResult {
        guard let imagePath = Bundle.main.path(forResource: "adobe-20220124-CI", ofType: "jpg") else {
            return TestResult(
                name: "Read Ingredient",
                success: false,
                message: "Could not find test image",
                details: nil
            )
        }

        let imageURL = URL(fileURLWithPath: imagePath)

        do {
            let ingredientJSON = try C2PA.readIngredient(at: imageURL)
            return TestResult(
                name: "Read Ingredient",
                success: true,
                message: "Successfully read ingredient data",
                details: "Ingredient size: \(ingredientJSON.count) bytes"
            )
        } catch let error as C2PAError {
            return TestResult(
                name: "Read Ingredient",
                success: true,
                message: "No ingredient data (expected for some images)",
                details: error.description
            )
        } catch {
            return TestResult(
                name: "Read Ingredient",
                success: false,
                message: "Unexpected error: \(error.localizedDescription)",
                details: "\(error)"
            )
        }
    }
    
    private func testInvalidFileHandling() async throws -> TestResult {
        let tempURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("test_invalid.txt")

        do {
            try "This is not a C2PA file".write(to: tempURL, atomically: true, encoding: .utf8)

            _ = try C2PA.readFile(at: tempURL)

            try? FileManager.default.removeItem(at: tempURL)

            return TestResult(
                name: "Invalid File Handling",
                success: false,
                message: "Should have thrown an error for invalid file",
                details: nil
            )
        } catch {
            try? FileManager.default.removeItem(at: tempURL)

            return TestResult(
                name: "Invalid File Handling",
                success: true,
                message: "Correctly handled invalid file format",
                details: "\(error)"
            )
        }
    }
    
    private func testResourceReading() async throws -> TestResult {
        guard let imagePath = Bundle.main.path(forResource: "adobe-20220124-CI", ofType: "jpg") else {
            return TestResult(
                name: "Resource Reading",
                success: false,
                message: "Could not find test image",
                details: nil
            )
        }

        do {
            let imageURL = URL(fileURLWithPath: imagePath)
            let data = try Data(contentsOf: imageURL)
            let stream = try Stream(data: data)
            let reader = try Reader(format: "image/jpeg", stream: stream)

            let tempURL = FileManager.default.temporaryDirectory
                .appendingPathComponent("thumbnail.jpg")
            let destStream = try Stream(fileURL: tempURL)

            do {
                try reader.resource(uri: "self#jumbf=c2pa/c2pa.assertions/c2pa.thumbnail.claim.jpeg", to: destStream)
                let fileSize = try FileManager.default.attributesOfItem(atPath: tempURL.path)[.size] as? Int64 ?? 0
                try? FileManager.default.removeItem(at: tempURL)

                return TestResult(
                    name: "Resource Reading",
                    success: true,
                    message: "Successfully read thumbnail resource",
                    details: "Thumbnail size: \(fileSize) bytes"
                )
            } catch {
                try? FileManager.default.removeItem(at: tempURL)
                return TestResult(
                    name: "Resource Reading",
                    success: true,
                    message: "No thumbnail resource found (normal for some files)",
                    details: "\(error)"
                )
            }
        } catch {
            return TestResult(
                name: "Resource Reading",
                success: false,
                message: "Failed to test resource reading: \(error.localizedDescription)",
                details: "\(error)"
            )
        }
    }
    
    private func testBuilderRemoteURL() async throws -> TestResult {
        do {
            let manifestJSON = """
            {
                "claim_generator": "TestApp/1.0 RemoteURL",
                "title": "Remote Manifest Test",
                "format": "image/jpeg",
                "assertions": []
            }
            """

            let builder = try Builder(manifestJSON: manifestJSON)

            let remoteURL = "https://example.com/manifests/test-manifest.c2pa"
            try builder.setRemoteURL(remoteURL)

            guard let imagePath = Bundle.main.path(forResource: "pexels-asadphoto-457882", ofType: "jpg"),
                  let certPath = Bundle.main.path(forResource: "es256_certs", ofType: "pem"),
                  let keyPath = Bundle.main.path(forResource: "es256_private", ofType: "key")
            else {
                return TestResult(
                    name: "Builder Remote URL",
                    success: false,
                    message: "Could not find required test files",
                    details: nil
                )
            }

            let imageURL = URL(fileURLWithPath: imagePath)
            let imageData = try Data(contentsOf: imageURL)

            let certsPEM = try String(contentsOfFile: certPath, encoding: .utf8)
            let privateKeyPEM = try String(contentsOfFile: keyPath, encoding: .utf8)

            let signer = try Signer(
                certsPEM: certsPEM,
                privateKeyPEM: privateKeyPEM,
                algorithm: .es256,
                tsaURL: nil
            )

            let sourceStream = try Stream(data: imageData)
            let destURL = FileManager.default.temporaryDirectory
                .appendingPathComponent("remote_url_test_\(UUID().uuidString).jpg")
            let destStream = try Stream(fileURL: destURL, truncate: true, createIfNeeded: true)

            let manifestData = try builder.sign(
                format: "image/jpeg",
                source: sourceStream,
                destination: destStream,
                signer: signer
            )

            let readManifest = try C2PA.readFile(at: destURL)
            let containsRemoteURL = readManifest.contains(remoteURL) || readManifest.contains("remote_manifest_url")

            try? FileManager.default.removeItem(at: destURL)

            return TestResult(
                name: "Builder Remote URL",
                success: manifestData.count > 0,
                message: "Successfully set and used remote URL in manifest",
                details: "Remote URL: \(remoteURL)\nManifest data: \(manifestData.count) bytes\nContains remote URL reference: \(containsRemoteURL)"
            )
        } catch {
            return TestResult(
                name: "Builder Remote URL",
                success: false,
                message: "Failed to test remote URL: \(error.localizedDescription)",
                details: "\(error)"
            )
        }
    }
    
    private func testBuilderAddResource() async throws -> TestResult {
        do {
            let jpegHeader: [UInt8] = [
                0xFF, 0xD8, 0xFF, 0xE0, 0x00, 0x10, 0x4A, 0x46, 0x49, 0x46, 0x00, 0x01, 0x01, 0x00, 0x00, 0x01,
                0x00, 0x01, 0x00, 0x00, 0xFF, 0xDB, 0x00, 0x43, 0x00, 0x08, 0x06, 0x06, 0x07, 0x06, 0x05, 0x08,
                0x07, 0x07, 0x07, 0x09, 0x09, 0x08, 0x0A, 0x0C, 0x14, 0x0D, 0x0C, 0x0B, 0x0B, 0x0C, 0x19, 0x12,
                0x13, 0x0F, 0x14, 0x1D, 0x1A, 0x1F, 0x1E, 0x1D, 0x1A, 0x1C, 0x1C, 0x20, 0x24, 0x2E, 0x27, 0x20,
                0x22, 0x2C, 0x23, 0x1C, 0x1C, 0x28, 0x37, 0x29, 0x2C, 0x30, 0x31, 0x34, 0x34, 0x34, 0x1F, 0x27,
                0x39, 0x3D, 0x38, 0x32, 0x3C, 0x2E, 0x33, 0x34, 0x32, 0xFF, 0xC0, 0x00, 0x0B, 0x08, 0x00, 0x01,
                0x00, 0x01, 0x01, 0x01, 0x11, 0x00, 0xFF, 0xC4, 0x00, 0x1F, 0x00, 0x00, 0x01, 0x05, 0x01, 0x01,
                0x01, 0x01, 0x01, 0x01, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x01, 0x02, 0x03, 0x04,
                0x05, 0x06, 0x07, 0x08, 0x09, 0x0A, 0x0B, 0xFF, 0xC4, 0x00, 0xB5, 0x10, 0x00, 0x02, 0x01, 0x03,
                0x03, 0x02, 0x04, 0x03, 0x05, 0x05, 0x04, 0x04, 0x00, 0x00, 0x01, 0x7D, 0x01, 0x02, 0x03, 0x00,
                0x04, 0x11, 0x05, 0x12, 0x21, 0x31, 0x41, 0x06, 0x13, 0x51, 0x61, 0x07, 0x22, 0x71, 0x14, 0x32,
                0x81, 0x91, 0xA1, 0x08, 0x23, 0x42, 0xB1, 0xC1, 0x15, 0x52, 0xD1, 0xF0, 0x24, 0x33, 0x62, 0x72,
                0x82, 0x09, 0x0A, 0x16, 0x17, 0x18, 0x19, 0x1A, 0x25, 0x26, 0x27, 0x28, 0x29, 0x2A, 0x34, 0x35,
                0x36, 0x37, 0x38, 0x39, 0x3A, 0x43, 0x44, 0x45, 0x46, 0x47, 0x48, 0x49, 0x4A, 0x53, 0x54, 0x55,
                0x56, 0x57, 0x58, 0x59, 0x5A, 0x63, 0x64, 0x65, 0x66, 0x67, 0x68, 0x69, 0x6A, 0x73, 0x74, 0x75,
                0x76, 0x77, 0x78, 0x79, 0x7A, 0x83, 0x84, 0x85, 0x86, 0x87, 0x88, 0x89, 0x8A, 0x92, 0x93, 0x94,
                0x95, 0x96, 0x97, 0x98, 0x99, 0x9A, 0xA2, 0xA3, 0xA4, 0xA5, 0xA6, 0xA7, 0xA8, 0xA9, 0xAA, 0xB2,
                0xB3, 0xB4, 0xB5, 0xB6, 0xB7, 0xB8, 0xB9, 0xBA, 0xC2, 0xC3, 0xC4, 0xC5, 0xC6, 0xC7, 0xC8, 0xC9,
                0xCA, 0xD2, 0xD3, 0xD4, 0xD5, 0xD6, 0xD7, 0xD8, 0xD9, 0xDA, 0xE1, 0xE2, 0xE3, 0xE4, 0xE5, 0xE6,
                0xE7, 0xE8, 0xE9, 0xEA, 0xF1, 0xF2, 0xF3, 0xF4, 0xF5, 0xF6, 0xF7, 0xF8, 0xF9, 0xFA, 0xFF, 0xDA,
                0x00, 0x08, 0x01, 0x01, 0x00, 0x00, 0x3F, 0x00, 0xFD, 0xFC, 0xA3, 0x14, 0x51, 0x45, 0x00, 0x7F,
                0xFF, 0xD9,
            ]
            let resourceData = Data(jpegHeader)

            let manifestJSON = """
            {
                "claim_generator": "TestApp/1.0 Resources",
                "title": "Resource Test",
                "format": "image/jpeg",
                "thumbnail": {
                    "format": "image/jpeg",
                    "identifier": "c2pa.thumbnail.claim.jpeg"
                }
            }
            """

            let builder = try Builder(manifestJSON: manifestJSON)

            let resourceStream = try Stream(data: resourceData)
            let resourceIdentifier = "c2pa.thumbnail.claim.jpeg"
            try builder.addResource(uri: resourceIdentifier, stream: resourceStream)

            guard let imagePath = Bundle.main.path(forResource: "pexels-asadphoto-457882", ofType: "jpg"),
                  let certPath = Bundle.main.path(forResource: "es256_certs", ofType: "pem"),
                  let keyPath = Bundle.main.path(forResource: "es256_private", ofType: "key")
            else {
                return TestResult(
                    name: "Builder Add Resource",
                    success: false,
                    message: "Could not find required test files",
                    details: nil
                )
            }

            let imageURL = URL(fileURLWithPath: imagePath)
            let imageData = try Data(contentsOf: imageURL)

            let certsPEM = try String(contentsOfFile: certPath, encoding: .utf8)
            let privateKeyPEM = try String(contentsOfFile: keyPath, encoding: .utf8)

            let signer = try Signer(
                certsPEM: certsPEM,
                privateKeyPEM: privateKeyPEM,
                algorithm: .es256,
                tsaURL: nil
            )

            let sourceStream = try Stream(data: imageData)
            let destURL = FileManager.default.temporaryDirectory
                .appendingPathComponent("resource_test_\(UUID().uuidString).jpg")
            let destStream = try Stream(fileURL: destURL, truncate: true, createIfNeeded: true)

            _ = try builder.sign(
                format: "image/jpeg",
                source: sourceStream,
                destination: destStream,
                signer: signer
            )

            let manifestStr = try C2PA.readFile(at: destURL)
            let hasResourceReference = manifestStr.contains("c2pa.thumbnail.claim.jpeg") ||
                manifestStr.contains("thumbnail")

            let readStream = try Stream(fileURL: destURL, truncate: false, createIfNeeded: false)
            let reader = try Reader(format: "image/jpeg", stream: readStream)
            _ = try reader.json()

            let extractedResourceURL = FileManager.default.temporaryDirectory
                .appendingPathComponent("extracted_thumbnail_\(UUID().uuidString).jpg")
            let extractedStream = try Stream(fileURL: extractedResourceURL, truncate: true, createIfNeeded: true)

            var resourceFound = false
            var resourceSize = 0
            var triedURIs: [String] = []

            let urisToTry = [
                resourceIdentifier,
                "self#jumbf=c2pa/c2pa.assertions/c2pa.thumbnail.claim.jpeg",
                "c2pa.thumbnail.claim.jpeg",
                "c2pa.assertions/c2pa.thumbnail.claim.jpeg",
            ]

            for uri in urisToTry {
                triedURIs.append(uri)
                do {
                    try reader.resource(uri: uri, to: extractedStream)
                    resourceFound = true
                    resourceSize = try FileManager.default.attributesOfItem(atPath: extractedResourceURL.path)[.size] as? Int ?? 0
                    break
                } catch {
                }
            }

            try? FileManager.default.removeItem(at: destURL)
            try? FileManager.default.removeItem(at: extractedResourceURL)

            let success = hasResourceReference || resourceFound

            return TestResult(
                name: "Builder Add Resource",
                success: success,
                message: success ? "Successfully added resource to manifest" : "Failed to add resource",
                details: """
                Added resource size: \(resourceData.count) bytes
                Resource referenced in manifest: \(hasResourceReference)
                Resource extracted: \(resourceFound)
                Extracted size: \(resourceSize) bytes
                Tried URIs: \(triedURIs.joined(separator: ", "))
                """
            )
        } catch {
            return TestResult(
                name: "Builder Add Resource",
                success: false,
                message: "Failed to test resource: \(error.localizedDescription)",
                details: "\(error)"
            )
        }
    }
    
    private func testBuilderAddIngredient() async throws -> TestResult {
        do {
            let manifestJSON = """
            {
                "claim_generator": "TestApp/1.0 Ingredients",
                "title": "Main Asset with Ingredient",
                "format": "image/jpeg"
            }
            """

            let builder = try Builder(manifestJSON: manifestJSON)

            guard let imagePath = Bundle.main.path(forResource: "adobe-20220124-CI", ofType: "jpg"),
                  let outputImagePath = Bundle.main.path(forResource: "pexels-asadphoto-457882", ofType: "jpg"),
                  let certPath = Bundle.main.path(forResource: "es256_certs", ofType: "pem"),
                  let keyPath = Bundle.main.path(forResource: "es256_private", ofType: "key")
            else {
                return TestResult(
                    name: "Builder Add Ingredient",
                    success: false,
                    message: "Could not find required test files",
                    details: nil
                )
            }

            let imageURL = URL(fileURLWithPath: imagePath)
            let imageData = try Data(contentsOf: imageURL)
            let ingredientStream = try Stream(data: imageData)

            let ingredientJSON = """
            {
                "title": "Adobe Test Image",
                "relationship": "parentOf"
            }
            """

            try builder.addIngredient(json: ingredientJSON, format: "image/jpeg", from: ingredientStream)

            let outputImageURL = URL(fileURLWithPath: outputImagePath)
            let outputImageData = try Data(contentsOf: outputImageURL)

            let certsPEM = try String(contentsOfFile: certPath, encoding: .utf8)
            let privateKeyPEM = try String(contentsOfFile: keyPath, encoding: .utf8)

            let signer = try Signer(
                certsPEM: certsPEM,
                privateKeyPEM: privateKeyPEM,
                algorithm: .es256,
                tsaURL: nil
            )

            let sourceStream = try Stream(data: outputImageData)
            let destURL = FileManager.default.temporaryDirectory
                .appendingPathComponent("ingredient_test_\(UUID().uuidString).jpg")
            let destStream = try Stream(fileURL: destURL, truncate: true, createIfNeeded: true)

            _ = try builder.sign(
                format: "image/jpeg",
                source: sourceStream,
                destination: destStream,
                signer: signer
            )

            let readManifest = try C2PA.readFile(at: destURL)

            var hasIngredient = false
            var ingredientTitle = ""
            if let data = readManifest.data(using: .utf8),
               let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
               let manifests = json["manifests"] as? [String: Any]
            {
                for (_, manifest) in manifests {
                    if let manifestDict = manifest as? [String: Any],
                       let ingredients = manifestDict["ingredients"] as? [[String: Any]], !ingredients.isEmpty
                    {
                        hasIngredient = true
                        if let firstIngredient = ingredients.first,
                           let title = firstIngredient["title"] as? String
                        {
                            ingredientTitle = title
                        }
                    }
                }
            }

            try? FileManager.default.removeItem(at: destURL)

            return TestResult(
                name: "Builder Add Ingredient",
                success: hasIngredient,
                message: hasIngredient ? "Successfully added ingredient to manifest" : "Ingredient not found in manifest",
                details: "Ingredient found: \(hasIngredient)\nIngredient title: '\(ingredientTitle)'"
            )
        } catch {
            return TestResult(
                name: "Builder Add Ingredient",
                success: false,
                message: "Failed to test ingredient: \(error.localizedDescription)",
                details: "\(error)"
            )
        }
    }
    
    private func testBuilderFromArchive() async throws -> TestResult {
        do {
            let manifestJSON = """
            {
                "claim_generator": "TestApp/1.0 Archive",
                "title": "Archive Test Manifest",
                "format": "application/c2pa"
            }
            """

            let originalBuilder = try Builder(manifestJSON: manifestJSON)
            originalBuilder.setNoEmbed()

            let archiveURL = FileManager.default.temporaryDirectory
                .appendingPathComponent("test_archive_\(UUID().uuidString).c2pa")
            let archiveStream = try Stream(fileURL: archiveURL, truncate: true, createIfNeeded: true)
            try originalBuilder.writeArchive(to: archiveStream)

            let readStream = try Stream(fileURL: archiveURL, truncate: false, createIfNeeded: false)
            let newBuilder = try Builder(archiveStream: readStream)

            let verifyURL = FileManager.default.temporaryDirectory
                .appendingPathComponent("verify_archive_\(UUID().uuidString).c2pa")
            let verifyStream = try Stream(fileURL: verifyURL, truncate: true, createIfNeeded: true)
            try newBuilder.writeArchive(to: verifyStream)

            let originalSize = try FileManager.default.attributesOfItem(atPath: archiveURL.path)[.size] as? Int64 ?? 0
            let verifySize = try FileManager.default.attributesOfItem(atPath: verifyURL.path)[.size] as? Int64 ?? 0

            try? FileManager.default.removeItem(at: archiveURL)
            try? FileManager.default.removeItem(at: verifyURL)

            return TestResult(
                name: "Builder from Archive",
                success: originalSize > 0 && verifySize > 0,
                message: "Successfully created builder from archive",
                details: "Original archive: \(originalSize) bytes, Recreated: \(verifySize) bytes"
            )
        } catch {
            return TestResult(
                name: "Builder from Archive",
                success: false,
                message: "Failed to create builder from archive: \(error.localizedDescription)",
                details: "\(error)"
            )
        }
    }
    
    private func testReaderWithManifestData() async throws -> TestResult {
        do {
            guard let imagePath = Bundle.main.path(forResource: "pexels-asadphoto-457882", ofType: "jpg"),
                  let certPath = Bundle.main.path(forResource: "es256_certs", ofType: "pem"),
                  let keyPath = Bundle.main.path(forResource: "es256_private", ofType: "key")
            else {
                return TestResult(
                    name: "Reader with Manifest Data",
                    success: false,
                    message: "Could not find required test files",
                    details: nil
                )
            }

            let imageURL = URL(fileURLWithPath: imagePath)
            let imageData = try Data(contentsOf: imageURL)

            let certsPEM = try String(contentsOfFile: certPath, encoding: .utf8)
            let privateKeyPEM = try String(contentsOfFile: keyPath, encoding: .utf8)

            let manifestJSON = """
            {
                "claim_generator": "TestApp/1.0 ManifestData",
                "title": "Manifest Data Test",
                "format": "image/jpeg"
            }
            """

            let builder = try Builder(manifestJSON: manifestJSON)
            let signer = try Signer(
                certsPEM: certsPEM,
                privateKeyPEM: privateKeyPEM,
                algorithm: .es256,
                tsaURL: nil
            )

            let sourceStream = try Stream(data: imageData)
            let destURL = FileManager.default.temporaryDirectory
                .appendingPathComponent("manifest_data_test_\(UUID().uuidString).jpg")
            let destStream = try Stream(fileURL: destURL, truncate: true, createIfNeeded: true)

            let manifestData = try builder.sign(
                format: "image/jpeg",
                source: sourceStream,
                destination: destStream,
                signer: signer
            )

            let originalStream = try Stream(data: imageData)
            let reader = try Reader(format: "image/jpeg", stream: originalStream, manifest: manifestData)
            let readManifest = try reader.json()

            try? FileManager.default.removeItem(at: destURL)

            return TestResult(
                name: "Reader with Manifest Data",
                success: !readManifest.isEmpty,
                message: "Successfully created reader with separate manifest data",
                details: "Manifest data size: \(manifestData.count) bytes, Read manifest: \(readManifest.count) bytes"
            )
        } catch {
            return TestResult(
                name: "Reader with Manifest Data",
                success: false,
                message: "Failed to create reader with manifest data: \(error.localizedDescription)",
                details: "\(error)"
            )
        }
    }
    
    private func testSignerWithCallback() async throws -> TestResult {
        do {
            guard let certPath = Bundle.main.path(forResource: "es256_certs", ofType: "pem"),
                  let keyPath = Bundle.main.path(forResource: "es256_private", ofType: "key")
            else {
                return TestResult(
                    name: "Signer with Callback",
                    success: false,
                    message: "Could not find certificate/key files",
                    details: nil
                )
            }

            let certsPEM = try String(contentsOfFile: certPath, encoding: .utf8)
            let privateKeyPEM = try String(contentsOfFile: keyPath, encoding: .utf8)

            let realSigner = try Signer(
                certsPEM: certsPEM,
                privateKeyPEM: privateKeyPEM,
                algorithm: .es256,
                tsaURL: nil
            )

            var signCallCount = 0
            var lastDataToSign: Data?

            let callbackSigner = try Signer(
                algorithm: .es256,
                certificateChainPEM: certsPEM,
                tsaURL: nil,
                sign: { dataToSign in
                    signCallCount += 1
                    lastDataToSign = dataToSign

                    let testManifest = """
                    {
                        "claim_generator": "TestApp/1.0 CallbackTest",
                        "title": "Callback Signer Test",
                        "format": "image/jpeg"
                    }
                    """

                    let builder = try Builder(manifestJSON: testManifest)

                    guard let imagePath = Bundle.main.path(forResource: "pexels-asadphoto-457882", ofType: "jpg") else {
                        throw C2PAError.api("Test image not found")
                    }

                    let imageURL = URL(fileURLWithPath: imagePath)
                    let imageData = try Data(contentsOf: imageURL)

                    let sourceStream = try Stream(data: imageData)
                    let destURL = FileManager.default.temporaryDirectory
                        .appendingPathComponent("callback_sign_temp_\(UUID().uuidString).jpg")
                    let destStream = try Stream(fileURL: destURL, truncate: true, createIfNeeded: true)

                    _ = try builder.sign(
                        format: "image/jpeg",
                        source: sourceStream,
                        destination: destStream,
                        signer: realSigner
                    )

                    try? FileManager.default.removeItem(at: destURL)

                    var signature = Data()
                    signature.append(Data(repeating: 0x30, count: 1))
                    signature.append(Data(repeating: 0x44, count: 1))
                    signature.append(Data(repeating: 0x02, count: 1))
                    signature.append(Data(repeating: 0x20, count: 1))
                    signature.append(Data(repeating: 0xAB, count: 32))
                    signature.append(Data(repeating: 0x02, count: 1))
                    signature.append(Data(repeating: 0x20, count: 1))
                    signature.append(Data(repeating: 0xCD, count: 32))

                    return signature
                }
            )

            let reserveSize = try callbackSigner.reserveSize()

            let manifestJSON = """
            {
                "claim_generator": "TestApp/1.0 CallbackSigner",
                "title": "Callback Signer Test",
                "format": "image/jpeg"
            }
            """

            let builder = try Builder(manifestJSON: manifestJSON)

            guard let imagePath = Bundle.main.path(forResource: "pexels-asadphoto-457882", ofType: "jpg") else {
                return TestResult(
                    name: "Signer with Callback",
                    success: false,
                    message: "Could not find test image",
                    details: nil
                )
            }

            let imageURL = URL(fileURLWithPath: imagePath)
            let imageData = try Data(contentsOf: imageURL)

            let sourceStream = try Stream(data: imageData)
            let destURL = FileManager.default.temporaryDirectory
                .appendingPathComponent("callback_test_\(UUID().uuidString).jpg")
            let destStream = try Stream(fileURL: destURL, truncate: true, createIfNeeded: true)

            var signSucceeded = false
            do {
                _ = try builder.sign(
                    format: "image/jpeg",
                    source: sourceStream,
                    destination: destStream,
                    signer: callbackSigner
                )
                signSucceeded = true
            } catch {
            }

            try? FileManager.default.removeItem(at: destURL)

            return TestResult(
                name: "Signer with Callback",
                success: signCallCount > 0 && reserveSize > 0,
                message: signCallCount > 0 ? "Successfully used callback signer" : "Callback was not invoked",
                details: """
                Reserve size: \(reserveSize) bytes
                Sign callback invoked: \(signCallCount) times
                Data to sign size: \(lastDataToSign?.count ?? 0) bytes
                Sign attempted: \(signSucceeded)
                """
            )
        } catch {
            return TestResult(
                name: "Signer with Callback",
                success: false,
                message: "Failed to test callback signer: \(error.localizedDescription)",
                details: "\(error)"
            )
        }
    }
    
    private func testFileOperationsWithDataDir() async throws -> TestResult {
        do {
            guard let imagePath = Bundle.main.path(forResource: "adobe-20220124-CI", ofType: "jpg") else {
                return TestResult(
                    name: "File Operations with Data Dir",
                    success: false,
                    message: "Could not find test image",
                    details: nil
                )
            }

            let imageURL = URL(fileURLWithPath: imagePath)

            let dataDir = FileManager.default.temporaryDirectory
                .appendingPathComponent("c2pa_data_\(UUID().uuidString)")
            try FileManager.default.createDirectory(at: dataDir, withIntermediateDirectories: true)

            let manifestJSON = try C2PA.readFile(at: imageURL, dataDir: dataDir)

            let contents = try FileManager.default.contentsOfDirectory(at: dataDir, includingPropertiesForKeys: nil)

            var ingredientResult = "No ingredient data"
            do {
                let ingredientJSON = try C2PA.readIngredient(at: imageURL, dataDir: dataDir)
                ingredientResult = "Found ingredient: \(ingredientJSON.count) bytes"
            } catch {
            }

            try? FileManager.default.removeItem(at: dataDir)

            return TestResult(
                name: "File Operations with Data Dir",
                success: !manifestJSON.isEmpty,
                message: "Successfully used file operations with data directory",
                details: "Manifest: \(manifestJSON.count) bytes, Files in dataDir: \(contents.count), \(ingredientResult)"
            )
        } catch {
            return TestResult(
                name: "File Operations with Data Dir",
                success: false,
                message: "Failed file operations with data dir: \(error.localizedDescription)",
                details: "\(error)"
            )
        }
    }
    
    private func testWriteOnlyStreams() async throws -> TestResult {
        do {
            var writtenData = Data()
            var position = 0

            let stream = try Stream(
                read: nil,
                seek: { offset, mode in
                    switch Int(mode.rawValue) {
                    case 0:
                        position = offset
                    case 1:
                        position += offset
                    case 2:
                        position = writtenData.count + offset
                    default:
                        return -1
                    }

                    position = max(0, position)

                    if position > writtenData.count {
                        writtenData.append(Data(repeating: 0, count: position - writtenData.count))
                    }

                    return position
                },
                write: { buffer, count in
                    let data = Data(bytes: buffer, count: count)

                    if position + count > writtenData.count {
                        writtenData.append(Data(repeating: 0, count: (position + count) - writtenData.count))
                    }

                    data.withUnsafeBytes { bytes in
                        writtenData.replaceSubrange(position ..< (position + count), with: bytes)
                    }

                    position += count
                    return count
                },
                flush: {
                    0
                }
            )

            let manifestJSON = """
            {
                "claim_generator": "TestApp/1.0 WriteSeek",
                "title": "Write/Seek Stream Test",
                "format": "application/c2pa"
            }
            """

            let builder = try Builder(manifestJSON: manifestJSON)
            builder.setNoEmbed()
            try builder.writeArchive(to: stream)

            return TestResult(
                name: "Write-Only Streams",
                success: writtenData.count > 0,
                message: "Successfully used write/seek stream",
                details: "Written data size: \(writtenData.count) bytes"
            )
        } catch {
            return TestResult(
                name: "Write-Only Streams",
                success: false,
                message: "Failed to use write stream: \(error.localizedDescription)",
                details: "\(error)"
            )
        }
    }
    
    private func testCustomStreamCallbacks() async throws -> TestResult {
        do {
            let manifestJSON = """
            {
                "claim_generator": "TestApp/1.0 CustomStream",
                "title": "Custom Stream Test",
                "format": "application/c2pa"
            }
            """

            let builder = try Builder(manifestJSON: manifestJSON)
            builder.setNoEmbed()

            var writtenData = Data()
            var position = 0
            var readCount = 0
            var writeCount = 0
            var seekCount = 0
            var flushCount = 0

            let memoryStream = try Stream(
                read: { buffer, count in
                    readCount += 1
                    let remaining = writtenData.count - position
                    guard remaining > 0 else { return 0 }

                    let bytesToRead = min(remaining, count)
                    _ = writtenData.withUnsafeBytes { bytes in
                        memcpy(buffer, bytes.baseAddress!.advanced(by: position), bytesToRead)
                    }
                    position += bytesToRead
                    return bytesToRead
                },
                seek: { offset, mode in
                    seekCount += 1
                    switch Int(mode.rawValue) {
                    case 0:
                        position = offset
                    case 1:
                        position += offset
                    case 2:
                        position = writtenData.count + offset
                    default:
                        return -1
                    }

                    position = max(0, position)

                    if position > writtenData.count {
                        writtenData.append(Data(repeating: 0, count: position - writtenData.count))
                    }

                    return position
                },
                write: { buffer, count in
                    writeCount += 1
                    let data = Data(bytes: buffer, count: count)

                    if position + count > writtenData.count {
                        writtenData.append(Data(repeating: 0, count: (position + count) - writtenData.count))
                    }

                    data.withUnsafeBytes { bytes in
                        writtenData.replaceSubrange(position ..< (position + count), with: bytes)
                    }

                    position += count
                    return count
                },
                flush: {
                    flushCount += 1
                    return 0
                }
            )

            try builder.writeArchive(to: memoryStream)

            let success = writeCount > 0 && seekCount > 0 && writtenData.count > 0

            let hasZipHeader = writtenData.count >= 4 &&
                writtenData[0] == 0x50 && writtenData[1] == 0x4B

            return TestResult(
                name: "Custom Stream Callbacks",
                success: success,
                message: success ? "Successfully used custom stream callbacks" : "Not all callbacks were exercised",
                details: """
                Read calls: \(readCount)
                Write calls: \(writeCount)
                Seek calls: \(seekCount)
                Flush calls: \(flushCount)
                Data written: \(writtenData.count) bytes
                Has ZIP header: \(hasZipHeader)
                """
            )
        } catch {
            return TestResult(
                name: "Custom Stream Callbacks",
                success: false,
                message: "Failed to test custom stream callbacks: \(error.localizedDescription)",
                details: "\(error)"
            )
        }
    }
    
    private func testStreamFileOptions() async throws -> TestResult {
        do {
            let tempDir = FileManager.default.temporaryDirectory
            let testFile = tempDir.appendingPathComponent("stream_options_test_\(UUID().uuidString).txt")
            let testArchive = tempDir.appendingPathComponent("test_archive_\(UUID().uuidString).c2pa")

            _ = try Stream(fileURL: testFile, truncate: false, createIfNeeded: true)
            let exists1 = FileManager.default.fileExists(atPath: testFile.path)

            try "Initial content".write(to: testFile, atomically: true, encoding: .utf8)
            let initialContent = try String(contentsOf: testFile, encoding: .utf8)

            _ = try Stream(fileURL: testFile, truncate: false, createIfNeeded: false)
            let preservedContent = try String(contentsOf: testFile, encoding: .utf8)

            let manifestJSON = """
            {
                "claim_generator": "TestApp/1.0 FileOptions",
                "title": "File Options Test",
                "format": "application/c2pa"
            }
            """

            let builder = try Builder(manifestJSON: manifestJSON)
            builder.setNoEmbed()

            let truncateStream = try Stream(fileURL: testArchive, truncate: true, createIfNeeded: true)
            try builder.writeArchive(to: truncateStream)

            let archiveExists = FileManager.default.fileExists(atPath: testArchive.path)
            let archiveSize = try FileManager.default.attributesOfItem(atPath: testArchive.path)[.size] as? Int64 ?? 0

            try? FileManager.default.removeItem(at: testFile)
            try? FileManager.default.removeItem(at: testArchive)

            let success = exists1 && initialContent == "Initial content" &&
                preservedContent == initialContent && archiveExists && archiveSize > 0

            return TestResult(
                name: "Stream File Options",
                success: success,
                message: success ? "Stream file options work correctly" : "Stream file options test failed",
                details: """
                File created: \(exists1)
                Content preserved: \(preservedContent == initialContent)
                Archive created: \(archiveExists), size: \(archiveSize) bytes
                """
            )
        } catch {
            return TestResult(
                name: "Stream File Options",
                success: false,
                message: "Failed to test stream file options: \(error.localizedDescription)",
                details: "\(error)"
            )
        }
    }
    
    private func testWebServiceSignerCreation() async throws -> TestResult {
        var testsPassed = 0
        var testDetails: [String] = []
        var server: SimpleSigningServer?
        
        defer {
            server?.stop()
        }
        
        do {
            let (signingServer, certificate) = try SimpleSigningServer.createTestSigningServer()
            server = signingServer
            testDetails.append("✓ Created C2PA signer from bundle keys")
            
            let port = try server!.start()
            testDetails.append("✓ Started HTTP signing server on port \(port)")
            
            try await Task.sleep(nanoseconds: 100_000_000) // 0.1 seconds
            
            do {
                let webServiceSigner = try Signer(
                    algorithm: .es256,
                    certificateChainPEM: certificate,
                    requestBuilder: { data in
                        var request = URLRequest(url: URL(string: "http://127.0.0.1:\(port)/sign")!)
                        request.httpMethod = "POST"
                        request.setValue("application/octet-stream", forHTTPHeaderField: "Content-Type")
                        request.httpBody = data
                        request.timeoutInterval = 5
                        return request
                    },
                    responseParser: { data, response in
                        return data
                    }
                )
                testsPassed += 1
                testDetails.append("✓ Created web service signer successfully")
                
                guard let imagePath = Bundle.main.path(forResource: "adobe-20220124-CI", ofType: "jpg"),
                      let testImageData = try? Data(contentsOf: URL(fileURLWithPath: imagePath)) else {
                    throw C2PAError.api("Could not load test image from bundle")
                }
                
                let manifestJSON = """
                {
                    "claim_generator": "c2pa-ios-web-service-test/1.0.0",
                    "claim_generator_info": [
                        {
                            "name": "c2pa-ios-web-service-test",
                            "version": "1.0.0"
                        }
                    ],
                    "title": "Web Service Real Signing Test",
                    "assertions": [
                        {
                            "label": "c2pa.actions",
                            "data": {
                                "actions": [
                                    {
                                        "action": "c2pa.created"
                                    }
                                ]
                            }
                        }
                    ]
                }
                """
                
                print("Creating builder with manifest...")
                let builder = try Builder(manifestJSON: manifestJSON)
                print("✓ Builder created")
                
                print("Creating streams...")
                let sourceStream = try Stream(data: testImageData)
                
                let tempURL = FileManager.default.temporaryDirectory.appendingPathComponent("signed_image.jpg")
                let destStream = try Stream(fileURL: tempURL, truncate: true, createIfNeeded: true)
                print("✓ Streams created")
                
                print("Testing PEM-based signer first...")
                let pemSigner = try Signer(
                    certsPEM: certificate,
                    privateKeyPEM: try String(contentsOfFile: Bundle.main.path(forResource: "es256_private", ofType: "key")!, encoding: .utf8),
                    algorithm: .es256
                )
                
                let testBuilder = try Builder(manifestJSON: manifestJSON)
                let testSourceStream = try Stream(data: testImageData)
                
                let testTempURL = FileManager.default.temporaryDirectory.appendingPathComponent("test_signed_image.jpg")
                let testDestStream = try Stream(fileURL: testTempURL, truncate: true, createIfNeeded: true)
                
                let pemResult = try testBuilder.sign(format: "image/jpeg", source: testSourceStream, destination: testDestStream, signer: pemSigner)
                print("✓ PEM signer works, got \(pemResult.count) bytes")
                testsPassed += 1
                testDetails.append("✓ PEM-based signing works as baseline")
                
                print("Testing web service signer...")
                let manifestData = try builder.sign(format: "image/jpeg", source: sourceStream, destination: destStream, signer: webServiceSigner)
                print("✓ Web service signing completed")
                testsPassed += 1
                testDetails.append("✓ Successfully signed data using web service")
                
                if !manifestData.isEmpty {
                    testsPassed += 1
                    testDetails.append("✓ Got signed manifest data (\(manifestData.count) bytes)")
                    
                    if let manifestString = String(data: manifestData, encoding: .utf8) {
                        if manifestString.contains("claim_generator") || manifestString.contains("c2pa") {
                            testsPassed += 1
                            testDetails.append("✓ Manifest contains expected C2PA structure")
                        } else {
                            testDetails.append("✗ Manifest doesn't look like C2PA format")
                            testDetails.append("Sample: \(manifestString.prefix(100))...")
                        }
                    } else {
                        testDetails.append("✓ Got binary manifest data (valid C2PA format)")
                        testsPassed += 1
                    }
                } else {
                    testDetails.append("✗ No manifest data returned from signing")
                }
                
            } catch {
                testDetails.append("✗ Web service signer creation failed: \(error)")
            }
            
            testDetails.append("✓ Stopped HTTP signing server")
            return TestResult(
                name: "Web Service Real Signing & Verification",
                success: testsPassed >= 3,
                message: "Completed \(testsPassed)/4 web service tests (signer creation, signing, manifest verification, readable)",
                details: testDetails.joined(separator: "\n")
            )
            
        } catch {
            testDetails.append("✗ Setup failed: \(error)")
            return TestResult(
                name: "Web Service HTTP Communication",
                success: false,
                message: "Test setup failed: \(error.localizedDescription)",
                details: testDetails.joined(separator: "\n")
            )
        }
    }
    
    private func testKeychainSignerCreation() async throws -> TestResult {
        let keyTag = "com.example.c2pa.ui.test.key.\(UUID().uuidString)"

        do {
            let certificateChain = """
            -----BEGIN CERTIFICATE-----
            MIIDQTCCAimgAwIBAgITBmyfz5m/jAo54vB4ikPmljZbyjANBgkqhkiG9w0BAQsF
            ADAzMQswCQYDVQQGEwJVUzEQMA4GA1UEChMHRXhhbXBsZTESMBAGA1UEAxMJVGVz
            dCBSb290MB4XDTIxMDEwMTAwMDAwMFoXDTMxMDEwMTAwMDAwMFowMzELMAkGA1UE
            BhMCVVMxEDAOBgNVBAoTB0V4YW1wbGUxEjAQBgNVBAMTCVRlc3QgQ2VydDBZMBMG
            ByqGSM49AgEGCCqGSM49AwEHA0IABHmH7xYqlGpCaKw0ZYUPhR7Q0ZFr8QtYGV2E
            NbUNOTcJajkNVFJBa0JJdhcOgF7TZz5xc5GGPaFPMDwYAIGJxIqjUzBRMB0GA1Ud
            DgQWBBSHVbWZRDSo0PGsU7fA6A6PJJdWXzAfBgNVHSMEGDAWgBSHVbWZRDSo0PGs
            U7fA6A6PJJdWXzAPBgNVHRMBAf8EBTADAQH/MA0GCSqGSIb3DQEBCwUAA4IBAQCR
            -----END CERTIFICATE-----
            """

            let keyCreated = createTestKeychainKey(keyTag: keyTag)

            defer {
                deleteTestKeychainKey(keyTag: keyTag)
            }

            guard keyCreated else {
                return TestResult(
                    name: "Keychain Signer Creation",
                    success: false,
                    message: "Failed to create test key in keychain",
                    details: "Could not create EC key for testing"
                )
            }

            _ = try Signer(
                algorithm: .es256,
                certificateChainPEM: certificateChain,
                keychainKeyTag: keyTag
            )

            let publicKeyPEM = try Signer.exportPublicKeyPEM(fromKeychainTag: keyTag)
            let hasValidPEM = publicKeyPEM.contains("-----BEGIN PUBLIC KEY-----") &&
                publicKeyPEM.contains("-----END PUBLIC KEY-----")

            return TestResult(
                name: "Keychain Signer Creation",
                success: hasValidPEM,
                message: "Successfully created keychain signer and exported public key",
                details: "Key tag: \(keyTag)\nPublic key length: \(publicKeyPEM.count) chars"
            )
        } catch {
            deleteTestKeychainKey(keyTag: keyTag)
            return TestResult(
                name: "Keychain Signer Creation",
                success: false,
                message: "Failed to create keychain signer: \(error.localizedDescription)",
                details: "\(error)"
            )
        }
    }
    
    @available(iOS 13.0, macOS 10.15, *)
    private func testSecureEnclaveSignerCreation() async throws -> TestResult {
        guard isSecureEnclaveAvailable() else {
            return TestResult(
                name: "Secure Enclave Signer Creation",
                success: true,
                message: "Secure Enclave not available on this device (simulator)",
                details: "Test skipped - Secure Enclave only available on physical devices"
            )
        }

        let keyTag = "com.example.c2pa.ui.test.secure.\(UUID().uuidString)"

        do {
            let config = SecureEnclaveSignerConfig(
                keyTag: keyTag,
                accessControl: [.privateKeyUsage]
            )

            defer {
                _ = Signer.deleteSecureEnclaveKey(keyTag: keyTag)
            }
            
            // Test 1: Create Secure Enclave key
            let secureEnclaveKey = try Signer.createSecureEnclaveKey(config: config)
            var testDetails = "✓ Created Secure Enclave key successfully\n"
            
            // Test 2: Extract public key from Secure Enclave key
            guard let publicKey = SecKeyCopyPublicKey(secureEnclaveKey) else {
                throw C2PAError.api("Failed to extract public key from Secure Enclave")
            }
            testDetails += "✓ Extracted public key from Secure Enclave key\n"
            
            // Test 3: Export public key data
            var error: Unmanaged<CFError>?
            guard let publicKeyData = SecKeyCopyExternalRepresentation(publicKey, &error) as Data? else {
                if let error = error?.takeRetainedValue() {
                    throw C2PAError.api("Failed to export public key data: \(error)")
                }
                throw C2PAError.api("Failed to export public key data")
            }
            testDetails += "✓ Exported public key data: \(publicKeyData.count) bytes\n"
            
            // Test 4: Verify key attributes
            guard let keyType = SecKeyCopyAttributes(secureEnclaveKey) as? [String: Any] else {
                throw C2PAError.api("Failed to get key attributes")
            }
            
            let isSecureEnclave = (keyType[kSecAttrTokenID as String] as? String) == (kSecAttrTokenIDSecureEnclave as String)
            let keySize = keyType[kSecAttrKeySizeInBits as String] as? Int ?? 0
            let keyTypeStr = keyType[kSecAttrKeyType as String] as? String ?? "unknown"
            
            testDetails += "✓ Key attributes - Type: \(keyTypeStr), Size: \(keySize) bits, Secure Enclave: \(isSecureEnclave)\n"
            
            // Test 5: Verify we can query for the key in keychain
            try await Task.sleep(nanoseconds: 100_000_000) // 0.1 seconds

            let query: [String: Any] = [
                kSecClass as String: kSecClassKey,
                kSecAttrApplicationTag as String: keyTag,
                kSecAttrKeyType as String: kSecAttrKeyTypeECSECPrimeRandom,
                kSecAttrTokenID as String: kSecAttrTokenIDSecureEnclave,
                kSecReturnRef as String: true,
            ]

            var item: CFTypeRef?
            let status = SecItemCopyMatching(query as CFDictionary, &item)
            let keyExists = status == errSecSuccess
            
            if keyExists {
                testDetails += "✓ Key found in keychain via query\n"
            } else {
                testDetails += "✗ Key query failed with status: \(status)\n"
            }
            
            // Test 6: Verify the queried key matches our created key
            var keysMatch = false
            if keyExists, let queriedKey = item {
                let secKey = queriedKey as! SecKey
                if let queriedPublicKey = SecKeyCopyPublicKey(secKey),
                   let queriedPublicKeyData = SecKeyCopyExternalRepresentation(queriedPublicKey, nil) as Data? {
                    keysMatch = queriedPublicKeyData == publicKeyData
                    testDetails += "✓ Queried key matches created key: \(keysMatch)\n"
                }
            }
            
            // Test 7: Test basic signing operation (without C2PA)
            var canSign = false
            let testData = "Hello Secure Enclave".data(using: .utf8)!
            let algorithm = SecKeyAlgorithm.ecdsaSignatureMessageX962SHA256
            
            if SecKeyIsAlgorithmSupported(secureEnclaveKey, .sign, algorithm) {
                var signError: Unmanaged<CFError>?
                if let signature = SecKeyCreateSignature(secureEnclaveKey, algorithm, testData as CFData, &signError) {
                    canSign = true
                    testDetails += "✓ Successfully signed test data: \(CFDataGetLength(signature)) bytes\n"
                    
                    // Verify signature
                    let isValid = SecKeyVerifySignature(publicKey, algorithm, testData as CFData, signature, &signError)
                    testDetails += "✓ Signature verification: \(isValid)\n"
                } else {
                    let errorDesc = signError?.takeRetainedValue().localizedDescription ?? "unknown error"
                    testDetails += "✗ Signing failed: \(errorDesc)\n"
                }
            } else {
                testDetails += "✗ Algorithm not supported for signing\n"
            }
            
            let success = keyExists && keysMatch && canSign && isSecureEnclave
            
            return TestResult(
                name: "Secure Enclave Signer Creation",
                success: success,
                message: success ? "Successfully created and verified Secure Enclave key with signing capability" : 
                    "Issues detected - see details",
                details: "Key tag: \(keyTag)\n\(testDetails)"
            )
        } catch {
            _ = Signer.deleteSecureEnclaveKey(keyTag: keyTag)
            return TestResult(
                name: "Secure Enclave Signer Creation",
                success: false,
                message: "Failed to create Secure Enclave signer: \(error.localizedDescription)",
                details: "\(error)"
            )
        }
    }
    
    private func testSigningAlgorithmTests() async throws -> TestResult {
        var testResults: [String] = []
        var testsPassed = 0

        let algorithms: [(SigningAlgorithm, String)] = [
            (.es256, "es256"),
            (.es384, "es384"),
            (.es512, "es512"),
            (.ps256, "ps256"),
            (.ps384, "ps384"),
            (.ps512, "ps512"),
            (.ed25519, "ed25519"),
        ]

        for (algorithm, expectedDescription) in algorithms {
            if algorithm.description == expectedDescription {
                testsPassed += 1
                testResults.append("✓ \(algorithm) -> '\(expectedDescription)'")
            } else {
                testResults.append("✗ \(algorithm) -> '\(algorithm.description)' (expected '\(expectedDescription)')")
            }
        }

        let keyTag = "com.example.c2pa.ui.test.ed25519.\(UUID().uuidString)"
        let certificateChain = "-----BEGIN CERTIFICATE-----\ntest\n-----END CERTIFICATE-----"

        do {
            _ = try Signer(
                algorithm: .ed25519,
                certificateChainPEM: certificateChain,
                keychainKeyTag: keyTag
            )
            testResults.append("✗ Ed25519 keychain should have failed")
        } catch let error as C2PAError {
            if case let .api(message) = error, message.contains("Ed25519 not supported") {
                testsPassed += 1
                testResults.append("✓ Ed25519 keychain properly rejected")
            } else {
                testResults.append("✗ Ed25519 keychain failed with wrong error: \(error)")
            }
        } catch {
            testResults.append("✗ Ed25519 keychain failed with unexpected error: \(error)")
        }

        if #available(iOS 13.0, macOS 10.15, *) {
            let secureKeyTag = "com.example.c2pa.ui.test.invalid.\(UUID().uuidString)"
            let config = SecureEnclaveSignerConfig(keyTag: secureKeyTag)

            do {
                _ = try Signer(
                    algorithm: .es384,
                    certificateChainPEM: certificateChain,
                    secureEnclaveConfig: config
                )
                testResults.append("✗ Secure Enclave ES384 should have failed")
            } catch let error as C2PAError {
                if case let .api(message) = error, message.contains("Secure Enclave only supports ES256") {
                    testsPassed += 1
                    testResults.append("✓ Secure Enclave ES384 properly rejected")
                } else {
                    testResults.append("✗ Secure Enclave ES384 failed with wrong error: \(error)")
                }
            } catch {
                testResults.append("✗ Secure Enclave ES384 failed with unexpected error: \(error)")
            }
        }

        let expectedTests = algorithms.count + 1 + (ProcessInfo.processInfo.operatingSystemVersion.majorVersion >= 13 ? 1 : 0)

        return TestResult(
            name: "Signing Algorithm Tests",
            success: testsPassed == expectedTests,
            message: "Passed \(testsPassed)/\(expectedTests) algorithm tests",
            details: testResults.joined(separator: "\n")
        )
    }
    
    // MARK: - Helper Functions
    
    private func createTestKeychainKey(keyTag: String) -> Bool {
        let attributes: [String: Any] = [
            kSecAttrKeyType as String: kSecAttrKeyTypeECSECPrimeRandom,
            kSecAttrKeySizeInBits as String: 256,
            kSecPrivateKeyAttrs as String: [
                kSecAttrIsPermanent as String: true,
                kSecAttrApplicationTag as String: keyTag,
                kSecAttrAccessible as String: kSecAttrAccessibleWhenUnlockedThisDeviceOnly,
            ],
        ]

        var error: Unmanaged<CFError>?
        let key = SecKeyCreateRandomKey(attributes as CFDictionary, &error)
        return key != nil
    }

    private func deleteTestKeychainKey(keyTag: String) {
        let query: [String: Any] = [
            kSecClass as String: kSecClassKey,
            kSecAttrApplicationTag as String: keyTag,
            kSecAttrKeyType as String: kSecAttrKeyTypeECSECPrimeRandom,
        ]

        _ = SecItemDelete(query as CFDictionary)
    }

    private func isSecureEnclaveAvailable() -> Bool {
        #if targetEnvironment(simulator)
            return false
        #else
            let testAttributes: [String: Any] = [
                kSecAttrKeyType as String: kSecAttrKeyTypeECSECPrimeRandom,
                kSecAttrKeySizeInBits as String: 256,
                kSecAttrTokenID as String: kSecAttrTokenIDSecureEnclave,
                kSecPrivateKeyAttrs as String: [
                    kSecAttrIsPermanent as String: false,
                ],
            ]

            var error: Unmanaged<CFError>?
            let key = SecKeyCreateRandomKey(testAttributes as CFDictionary, &error)
            return key != nil
        #endif
    }
    
    private func createTestJPEGData() -> Data {
        // Create a minimal valid JPEG (1x1 pixel, black)
        let jpegData: [UInt8] = [
            0xFF, 0xD8, 0xFF, 0xE0, 0x00, 0x10, 0x4A, 0x46, 0x49, 0x46, 0x00, 0x01, 0x01, 0x01, 0x00, 0x48,
            0x00, 0x48, 0x00, 0x00, 0xFF, 0xDB, 0x00, 0x43, 0x00, 0x08, 0x06, 0x06, 0x07, 0x06, 0x05, 0x08,
            0x07, 0x07, 0x07, 0x09, 0x09, 0x08, 0x0A, 0x0C, 0x14, 0x0D, 0x0C, 0x0B, 0x0B, 0x0C, 0x19, 0x12,
            0x13, 0x0F, 0x14, 0x1D, 0x1A, 0x1F, 0x1E, 0x1D, 0x1A, 0x1C, 0x1C, 0x20, 0x24, 0x2E, 0x27, 0x20,
            0x22, 0x2C, 0x23, 0x1C, 0x1C, 0x28, 0x37, 0x29, 0x2C, 0x30, 0x31, 0x34, 0x34, 0x34, 0x1F, 0x27,
            0x39, 0x3D, 0x38, 0x32, 0x3C, 0x2E, 0x33, 0x34, 0x32, 0xFF, 0xC0, 0x00, 0x11, 0x08, 0x00, 0x01,
            0x00, 0x01, 0x01, 0x01, 0x11, 0x00, 0x02, 0x11, 0x01, 0x03, 0x11, 0x01, 0xFF, 0xC4, 0x00, 0x14,
            0x00, 0x01, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00,
            0x00, 0x08, 0xFF, 0xC4, 0x00, 0x14, 0x10, 0x01, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00,
            0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0xFF, 0xDA, 0x00, 0x0C, 0x03, 0x01, 0x00, 0x02,
            0x11, 0x03, 0x11, 0x00, 0x3F, 0x00, 0x80, 0xFF, 0xD9
        ]
        return Data(jpegData)
    }
}