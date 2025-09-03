import C2PA
import Foundation
import Vapor

class C2PASigningService {
    private let certificateService: CertificateSigningService

    init() {
        self.certificateService = CertificateSigningService()
    }

    func signManifest(
        manifestJSON: String,
        imageData: Data,
        format: String
    ) async throws -> C2PASigningResponse {
        let certificateChain: String
        let privateKeyPEM: String

        do {
            // Use test certificates from Resources
            let certPath = FileManager.default.currentDirectoryPath + "/Resources/es256_certs.pem"
            let keyPath = FileManager.default.currentDirectoryPath + "/Resources/es256_private.key"

            certificateChain = try String(contentsOfFile: certPath, encoding: .utf8)
            privateKeyPEM = try String(contentsOfFile: keyPath, encoding: .utf8)

            guard certificateChain.contains("BEGIN CERTIFICATE") else {
                throw Abort(.internalServerError, reason: "Invalid certificate format")
            }
            guard
                privateKeyPEM.contains("BEGIN PRIVATE KEY")
                    || privateKeyPEM.contains("BEGIN EC PRIVATE KEY")
            else {
                throw Abort(.internalServerError, reason: "Invalid private key format")
            }
        } catch {
            throw Abort(.internalServerError, reason: "Failed to load test certificates: \(error)")
        }

        print("[C2PA] Creating signer with manifest JSON:")
        print(manifestJSON)
        print("[C2PA] Using certificates from: Resources/es256_certs.pem")
        print("[C2PA] Certificate chain length: \(certificateChain.count)")
        print("[C2PA] Private key length: \(privateKeyPEM.count)")

        let tempDir = FileManager.default.temporaryDirectory
        let sourceURL = tempDir.appendingPathComponent(
            "c2pa_source_\(UUID().uuidString).\(format.components(separatedBy: "/").last ?? "jpg")")
        let destinationURL = tempDir.appendingPathComponent(
            "c2pa_signed_\(UUID().uuidString).\(format.components(separatedBy: "/").last ?? "jpg")")

        try imageData.write(to: sourceURL)
        print("[C2PA] Source file written: \(sourceURL.path)")
        print("[C2PA] Destination will be: \(destinationURL.path)")

        defer {
            try? FileManager.default.removeItem(at: sourceURL)
            try? FileManager.default.removeItem(at: destinationURL)
        }

        do {
            print("[C2PA] Using Builder/Stream API directly")

            let builder = try Builder(manifestJSON: manifestJSON)
            print("[C2PA] Builder created successfully")

            let signer = try Signer(
                certsPEM: certificateChain,
                privateKeyPEM: privateKeyPEM,
                algorithm: .es256,
                tsaURL: nil
            )
            print("[C2PA] Signer created successfully")

            let sourceStream = try Stream(
                fileURL: sourceURL, truncate: false, createIfNeeded: false)
            let destStream = try Stream(
                fileURL: destinationURL, truncate: true, createIfNeeded: true)
            print("[C2PA] Streams created successfully")

            let manifestData = try builder.sign(
                format: format,
                source: sourceStream,
                destination: destStream,
                signer: signer
            )
            print("[C2PA] Signing completed, manifest data size: \(manifestData.count)")

        } catch let c2paError as C2PAError {
            print("[C2PA] C2PA Error: \(c2paError.description)")
            throw Abort(.internalServerError, reason: c2paError.description)
        } catch {
            print("[C2PA] Unknown signing error: \(error)")
            throw error
        }

        let signedImageData = try Data(contentsOf: destinationURL)

        let signatureInfo = SignatureInfo(
            algorithm: "ES256",
            certificateChain: certificateChain,
            timestamp: Date()
        )

        return C2PASigningResponse(
            manifestStore: signedImageData,
            signatureInfo: signatureInfo
        )
    }
}
