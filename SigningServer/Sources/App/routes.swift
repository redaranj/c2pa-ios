import Vapor

func routes(_ app: Application) throws {
    app.get { _ async in
        return [
            "status": "C2PA Signing Server is running",
            "version": "1.0.0",
            "mode": "testing"
        ]
    }

    // Health check endpoint
    app.get("health") { _ async in
        return HTTPStatus.ok
    }

    let api = app.grouped("api", "v1")

    // Certificate signing endpoint
    let certificates = api.grouped("certificates")

    let certificateSigningController = CertificateSigningController()
    certificates.post("sign", use: certificateSigningController.signCSR)

    // C2PA endpoints with bearer auth protection
    let c2pa = api.grouped("c2pa")
        .grouped(BearerAuthMiddleware())

    let c2paConfigurationController = C2PAConfigurationController()
    c2pa.get("configuration", use: c2paConfigurationController.getConfiguration)

    let c2paSigningController = C2PASigningController()
    c2pa.post("sign", use: c2paSigningController.signManifest)
}
