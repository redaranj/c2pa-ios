//
//  Configuration.swift
//  C2PAExample
//
//  Configuration settings for the C2PA Example app
//

import Foundation

struct Configuration {
    // MARK: - Signing Server Configuration
    
    // IMPORTANT: iOS App Transport Security requires HTTPS connections
    // When testing on physical devices, use Tailscale with HTTPS:
    // tailscale serve --bg --https 8081 http://localhost:8080
    
    /// The base URL for the C2PA signing server
    /// Update this to match your signing server location
    /// Examples:
    /// - Local development: "http://127.0.0.1:8080"
    /// - Tailscale network (HTTPS): "https://air.tiger-agama.ts.net:8081"
    /// - Production server: "https://your-signing-server.com"
    /// 
    /// To test on a physical device:
    /// 1. Run: tailscale serve --bg --https 8081 http://localhost:8080
    /// 2. Update the URL below to your Tailscale URL (use HTTPS)
    /// 3. Make sure your device is on the same Tailscale network
    // static let signingServerBaseURL = "http://127.0.0.1:8080"
    static let signingServerBaseURL = "https://air.tiger-agama.ts.net:8081"
    /// Health check endpoint
    static var signingServerHealthURL: URL {
        URL(string: "\(signingServerBaseURL)/health")!
    }
    
    /// Signing endpoint
    static var signingServerSignURL: URL {
        URL(string: "\(signingServerBaseURL)/api/v1/c2pa/sign")!
    }
    
    // MARK: - Test Configuration
    
    /// Timeout for network requests in seconds
    static let networkTimeout: TimeInterval = 30.0
    
    /// Enable detailed logging
    static let verboseLogging = false
}
