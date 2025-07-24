import Vapor
import C2PA

func routes(_ app: Application) throws {
    app.get { req async in
        return ["status": "C2PA Signing Server is running", "version": "1.0.0", "mode": "testing"]
    }

    app.get("health") { req async in
        return HTTPStatus.ok
    }
    
    // C2PA version check endpoint
    app.get("c2pa-version") { req async in
        return ["c2pa_version": C2PAVersion, "status": "C2PA library loaded"]
    }
    
    // C2PA read test endpoint
    app.get("c2pa-test-read") { req async throws -> [String: String] in
        // Try to read the test image that has C2PA data
        let testImagePath = FileManager.default.currentDirectoryPath + "/../example/C2PAExample/adobe-20220124-CI.jpg"
        let testImageURL = URL(fileURLWithPath: testImagePath)
        
        do {
            let manifest = try C2PA.readFile(at: testImageURL)
            return ["status": "success", "manifest_length": String(manifest.count), "has_manifest": "true"]
        } catch {
            return ["status": "error", "error": error.localizedDescription, "path": testImagePath]
        }
    }
    
    // C2PA simple sign test endpoint
    app.get("c2pa-test-sign") { req async throws -> [String: String] in
        let manifestJSON = """
        {
            "claim_generator": "TestServer/1.0",
            "title": "Test Sign"
        }
        """
        
        let sourceImagePath = FileManager.default.currentDirectoryPath + "/../example/C2PAExample/pexels-asadphoto-457882.jpg"
        let sourceURL = URL(fileURLWithPath: sourceImagePath)
        let destURL = FileManager.default.temporaryDirectory.appendingPathComponent("test_signed_\(UUID().uuidString).jpg")
        
        let certPath = FileManager.default.currentDirectoryPath + "/Resources/es256_certs.pem"
        let keyPath = FileManager.default.currentDirectoryPath + "/Resources/es256_private.key"
        
        do {
            let certsPEM = try String(contentsOfFile: certPath)
            let privateKeyPEM = try String(contentsOfFile: keyPath)
            
            let signerInfo = SignerInfo(
                algorithm: .es256,
                certificatePEM: certsPEM,
                privateKeyPEM: privateKeyPEM,
                tsaURL: nil
            )
            
            try C2PA.signFile(
                source: sourceURL,
                destination: destURL,
                manifestJSON: manifestJSON,
                signerInfo: signerInfo,
                dataDir: nil
            )
            
            return ["status": "success", "destination": destURL.path]
        } catch let c2paError as C2PAError {
            return ["status": "error", "error": "C2PA: \(c2paError.description)"]
        } catch {
            return ["status": "error", "error": error.localizedDescription]
        }
    }
    
    // API v1 routes
    let api = app.grouped("api", "v1")
    
    // Certificate endpoints
    let certificates = api.grouped("certificates")
    let certificateController = CertificateController()
    certificates.post("csr", use: certificateController.signCSR)
    certificates.get("ca", use: certificateController.getCACertificate)
    certificates.get(":id", use: certificateController.getCertificate)
    certificates.delete(":id", use: certificateController.revokeCertificate)  // No auth required for testing
    
    // C2PA signing endpoints
    let c2pa = api.grouped("c2pa")
    let c2paController = C2PAController()
    c2pa.post("sign", use: c2paController.signManifest)
    c2pa.post("verify", use: c2paController.verifyManifest)
}