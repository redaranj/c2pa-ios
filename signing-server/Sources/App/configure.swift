import Vapor

public func configure(_ app: Application) async throws {
    app.routes.defaultMaxBodySize = "50mb"

    app.middleware.use(ErrorMiddleware.default(environment: app.environment))

    app.certificateService = CertificateSigningService()
    app.c2paService = C2PASigningService()

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

    struct C2PAServiceKey: StorageKey {
        typealias Value = C2PASigningService
    }

    var c2paService: C2PASigningService {
        get { self.storage[C2PAServiceKey.self]! }
        set { self.storage[C2PAServiceKey.self] = newValue }
    }
}
