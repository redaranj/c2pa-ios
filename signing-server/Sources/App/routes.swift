import C2PA
import Vapor

func routes(_ app: Application) throws {
    app.get { req async in
        return [
            "status": "C2PA Signing Server is running",
            "version": "1.0.0",
            "mode": "testing",
            "c2pa_version": C2PAVersion,
        ]
    }

    // health check endpoint
    app.get("health") { req async in
        return HTTPStatus.ok
    }

    let api = app.grouped("api", "v1")

    // Certificate signing endpoint
    let certificates = api.grouped("certificates")
    let certificateSigningController = CertificateSigningController()
    certificates.post("sign", use: certificateSigningController.signCSR)

    // C2PA signing endpoint
    let c2pa = api.grouped("c2pa")
    let c2paSigningController = C2PASigningController()
    c2pa.post("sign", use: c2paSigningController.signManifest)
}
