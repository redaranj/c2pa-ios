import Foundation
import OSLog

enum Logger {
    private static let subsystem = "org.contentauth.ExampleApp"

    static let signing = OSLog(subsystem: subsystem, category: "signing")
    static let verification = OSLog(subsystem: subsystem, category: "verification")
    static let storage = OSLog(subsystem: subsystem, category: "storage")
    static let general = OSLog(subsystem: subsystem, category: "general")
    static let error = OSLog(subsystem: subsystem, category: "error")
    static let certificate = OSLog(subsystem: subsystem, category: "certificate")
    static let metadata = OSLog(subsystem: subsystem, category: "metadata")
}
