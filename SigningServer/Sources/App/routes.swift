import Vapor
import C2PA

func routes(_ app: Application) throws {
    app.get { req async in
        return [
            "status": "C2PA Signing Server is running", 
            "version": "1.0.0", 
            "mode": "testing",
            "c2pa_version": C2PAVersion
        ]
    }

    app.get("health") { req async in
        return HTTPStatus.ok
    }
    
    // API v1 routes
    let api = app.grouped("api", "v1")
    
    // Certificate endpoints
    let certificates = api.grouped("certificates")
    let certificateController = CertificateController()
    certificates.post("sign", use: certificateController.signCSR)
    
    // C2PA signing endpoints
    let c2pa = api.grouped("c2pa")
    let c2paController = C2PAController()
    c2pa.post("sign", use: c2paController.signManifest)
}