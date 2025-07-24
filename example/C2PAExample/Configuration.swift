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
    // When testing on physical devices, you may need to use a tunnel or proxy service
    
    /// The base URL for the C2PA signing server
    /// Update this to match your signing server location
    /// Examples:
    /// - Local development: "http://127.0.0.1:8080"
    /// - Production server: "https://your-signing-server.com"
    /// 
    /// Note: When testing on physical devices, you may need to:
    /// 1. Use a tunneling service to expose your local server with HTTPS
    /// 2. Update the URL below to your server's public URL
    /// 3. Ensure the device can reach the server
    static let signingServerBaseURL = "http://127.0.0.1:8080"
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
