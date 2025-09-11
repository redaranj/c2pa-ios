import Vapor

public func configure(_ app: Application) async throws {
    app.routes.defaultMaxBodySize = "50mb"
    app.middleware.use(ErrorMiddleware.default(environment: app.environment))
    app.certificateService = CertificateSigningService()

    try routes(app)
}

extension Application {
    struct CertificateServiceKey: StorageKey {
        typealias Value = CertificateSigningService
    }

    var certificateService: CertificateSigningService {
        get { self.storage[CertificateServiceKey.self]! }
        set { self.storage[CertificateServiceKey.self] = newValue }
    }
}
