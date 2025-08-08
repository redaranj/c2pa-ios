import Vapor

// configures your application
public func configure(_ app: Application) async throws {
    // Configure maximum body size for image uploads (50MB)
    app.routes.defaultMaxBodySize = "50mb"
    
    // Configure CORS for development
    let corsConfiguration = CORSMiddleware.Configuration(
        allowedOrigin: .all,
        allowedMethods: [.GET, .POST, .PUT, .OPTIONS, .DELETE, .PATCH],
        allowedHeaders: [.accept, .authorization, .contentType, .origin, .xRequestedWith, .userAgent, .accessControlAllowOrigin]
    )
    let cors = CORSMiddleware(configuration: corsConfiguration)
    app.middleware.use(cors)
    
    // Configure file middleware for serving static files
    app.middleware.use(FileMiddleware(publicDirectory: app.directory.publicDirectory))
    
    // Configure error middleware
    app.middleware.use(ErrorMiddleware.default(environment: app.environment))
    
    // Initialize services
    app.certificateService = CertificateSigningService()
    app.c2paService = C2PASigningService()
    
    // register routes
    try routes(app)
}

// Service storage
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