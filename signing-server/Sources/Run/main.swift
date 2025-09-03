import App
import Vapor

@main
enum Main {
    static func main() async throws {
        var env = try Environment.detect()
        try LoggingSystem.bootstrap(from: &env)
        let app = try await Application.make(env)
        do {
            try await configure(app)
            try await app.execute()
        } catch {
            try await app.asyncShutdown()
            throw error
        }
    }
}
