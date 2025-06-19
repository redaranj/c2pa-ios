import C2PA
import CryptoKit
import Foundation
import Network

/// A minimal HTTP server for testing web service signers without external dependencies
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
                semaphore.signal()
            case .failed:
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
                guard error == nil, let data = data, !data.isEmpty else {
                    if isComplete {
                        self?.processRequest(buffer, connection: connection)
                    }
                    return
                }
                
                buffer.append(data)
                
                // Parse Content-Length from headers
                if expectedContentLength == nil {
                    if let headerEnd = buffer.range(of: Data([0x0D, 0x0A, 0x0D, 0x0A])) {
                        let headerData = buffer.subdata(in: 0..<headerEnd.lowerBound)
                        if let headerString = String(data: headerData, encoding: .utf8) {
                            for line in headerString.components(separatedBy: "\r\n") {
                                if line.lowercased().hasPrefix("content-length:") {
                                    expectedContentLength = Int(line.dropFirst(15).trimmingCharacters(in: .whitespaces)) ?? 0
                                    break
                                }
                            }
                        }
                        expectedContentLength = expectedContentLength ?? 0
                    }
                }
                
                // Check if we have complete request
                if let contentLength = expectedContentLength {
                    let headerSeparator = Data([0x0D, 0x0A, 0x0D, 0x0A])
                    if let headerEnd = buffer.range(of: headerSeparator) {
                        let bodyStart = headerEnd.upperBound
                        let currentBodyLength = buffer.count - bodyStart
                        
                        if currentBodyLength >= contentLength {
                            self?.processRequest(buffer, connection: connection)
                            return
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
    
    private func processRequest(_ data: Data, connection: NWConnection) {
        guard let request = parseHTTPRequest(data) else {
            sendResponse(createErrorResponse(), to: connection)
            return
        }
        
        guard request.method == "POST", request.path == "/sign" else {
            sendResponse(createErrorResponse(status: "404 Not Found", message: "Endpoint not found"), to: connection)
            return
        }
        
        do {
            let manifestData = try signData(request.body)
            let response = "HTTP/1.1 200 OK\r\nContent-Type: application/octet-stream\r\nContent-Length: \(manifestData.count)\r\nConnection: close\r\n\r\n"
            var responseData = response.data(using: .utf8) ?? Data()
            responseData.append(manifestData)
            sendResponse(responseData, to: connection)
        } catch {
            sendResponse(createErrorResponse(message: error.localizedDescription), to: connection)
        }
    }
    
    private func parseHTTPRequest(_ data: Data) -> HTTPRequest? {
        let headerSeparator = Data([0x0D, 0x0A, 0x0D, 0x0A])
        guard let separatorRange = data.range(of: headerSeparator) else { return nil }
        
        let headerData = data.subdata(in: 0..<separatorRange.lowerBound)
        let bodyData = data.subdata(in: separatorRange.upperBound..<data.count)
        
        guard let headerString = String(data: headerData, encoding: .utf8) else { return nil }
        
        let lines = headerString.components(separatedBy: "\r\n")
        guard let firstLine = lines.first else { return nil }
        
        let components = firstLine.components(separatedBy: " ")
        guard components.count >= 2 else { return nil }
        
        return HTTPRequest(method: components[0], path: components[1], body: bodyData)
    }
    
    private func signData(_ data: Data) throws -> Data {
        if #available(iOS 13.0, macOS 10.15, *) {
            let privateKey = try getPrivateKey()
            let signature = try privateKey.signature(for: data)
            return signature.rawRepresentation
        } else {
            throw C2PAError.api("CryptoKit required for signing")
        }
    }
    
    private func getCertificateChain() throws -> String {
        guard let certPath = Bundle.main.path(forResource: "es256_certs", ofType: "pem") else {
            throw C2PAError.api("Could not find certificate file")
        }
        return try String(contentsOfFile: certPath, encoding: .utf8)
    }
    
    private func getPrivateKey() throws -> P256.Signing.PrivateKey {
        guard let keyPath = Bundle.main.path(forResource: "es256_private", ofType: "key") else {
            throw C2PAError.api("Could not find private key file")
        }
        let privateKeyPEM = try String(contentsOfFile: keyPath, encoding: .utf8)
        
        if #available(iOS 13.0, macOS 10.15, *) {
            return try P256.Signing.PrivateKey(pemRepresentation: privateKeyPEM)
        } else {
            throw C2PAError.api("CryptoKit required")
        }
    }
    
    private func sendResponse(_ responseData: Data, to connection: NWConnection) {
        connection.send(content: responseData, completion: .contentProcessed { _ in
            connection.cancel()
        })
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