import Foundation
import UIKit
import Photos
import C2PA

class C2PAManager: ObservableObject {
    static let shared = C2PAManager()
    
    @Published var isProcessing = false
    @Published var lastError: String?
    
    private var defaultCertificateData: Data?
    private var defaultPrivateKeyData: Data?
    
    private init() {
        loadDefaultCertificates()
    }
    
    private func loadDefaultCertificates() {
        // Load default certificates from bundle
        if let certURL = Bundle.main.url(forResource: "default_certs", withExtension: "pem"),
           let keyURL = Bundle.main.url(forResource: "default_private", withExtension: "key") {
            do {
                defaultCertificateData = try Data(contentsOf: certURL)
                defaultPrivateKeyData = try Data(contentsOf: keyURL)
                print("Default certificates loaded successfully")
            } catch {
                print("Error loading default certificates: \(error)")
            }
        }
    }
    
    func signAndSaveImage(_ image: UIImage, completion: @escaping (Bool, String?) -> Void) {
        isProcessing = true
        lastError = nil
        
        Task {
            do {
                guard let imageData = image.jpegData(compressionQuality: 0.9) else {
                    await MainActor.run {
                        self.isProcessing = false
                        self.lastError = "Failed to convert image to JPEG"
                        completion(false, self.lastError)
                    }
                    return
                }
                
                // Check for custom certificates first, then fall back to defaults
                let customCertData = UserDefaults.standard.data(forKey: "certificateData")
                let customKeyData = UserDefaults.standard.data(forKey: "privateKeyData")
                
                var signedImageData: Data
                
                if let certData = customCertData, let keyData = customKeyData {
                    // Use custom certificates provided by user
                    print("Using custom certificates for signing")
                    signedImageData = try await signWithCertificate(
                        imageData: imageData,
                        certificateData: certData,
                        privateKeyData: keyData,
                        isCustom: true
                    )
                } else if let certData = defaultCertificateData, let keyData = defaultPrivateKeyData {
                    // Use default certificates from bundle
                    print("Using default certificates for signing")
                    signedImageData = try await signWithCertificate(
                        imageData: imageData,
                        certificateData: certData,
                        privateKeyData: keyData,
                        isCustom: false
                    )
                } else {
                    throw NSError(domain: "C2PAManager", code: 2, userInfo: [
                        NSLocalizedDescriptionKey: "No certificates available for signing"
                    ])
                }
                
                try await saveToPhotoLibrary(imageData: signedImageData)
                
                await MainActor.run {
                    self.isProcessing = false
                    completion(true, nil)
                }
            } catch {
                await MainActor.run {
                    self.isProcessing = false
                    self.lastError = error.localizedDescription
                    completion(false, error.localizedDescription)
                }
            }
        }
    }
    
    private func signWithCertificate(imageData: Data, certificateData: Data, privateKeyData: Data, isCustom: Bool) async throws -> Data {
        do {
            // Create temporary files for the image
            let tempDir = FileManager.default.temporaryDirectory
            let inputURL = tempDir.appendingPathComponent("input_\(UUID().uuidString).jpg")
            let outputURL = tempDir.appendingPathComponent("output_\(UUID().uuidString).jpg")
            
            defer {
                // Clean up temp files
                try? FileManager.default.removeItem(at: inputURL)
                try? FileManager.default.removeItem(at: outputURL)
            }
            
            // Write input image to temp directory
            try imageData.write(to: inputURL)
            
            // Convert certificate and key data to strings
            guard let certString = String(data: certificateData, encoding: .utf8),
                  let keyString = String(data: privateKeyData, encoding: .utf8) else {
                throw NSError(domain: "C2PAManager", code: 3, userInfo: [
                    NSLocalizedDescriptionKey: "Invalid certificate or key format"
                ])
            }
            
            print("=== C2PA Signing Debug ===")
            print("Input file size: \(imageData.count) bytes")
            print("Certificate loaded: \(certString.prefix(50))...")
            print("Using \(isCustom ? "custom" : "default") certificates")
            
            // Create a simple manifest JSON - starting with minimal structure
            let manifest: [String: Any] = [
                "claim_generator": "ProofMode iOS/1.0.0",
                "title": "ProofMode Image",
                "format": "image/jpeg"
            ]
            
            let manifestData = try JSONSerialization.data(withJSONObject: manifest, options: [])
            let manifestJSON = String(data: manifestData, encoding: .utf8)!
            
            print("Manifest JSON created: \(manifestJSON.prefix(200))...")
            
            // Use the file-based signing method
            let signerInfo = SignerInfo(
                algorithm: .es256,
                certificatePEM: certString,
                privateKeyPEM: keyString,
                tsaURL: nil
            )
            
            print("Using C2PA.signFile method...")
            
            // Sign the file directly using C2PA.signFile
            try C2PA.signFile(
                source: inputURL,
                destination: outputURL,
                manifestJSON: manifestJSON,
                signerInfo: signerInfo,
                dataDir: nil
            )
            
            print("Sign operation completed")
            
            // Read the signed image
            let signedData = try Data(contentsOf: outputURL)
            print("Output file size: \(signedData.count) bytes")
            print("Size difference: \(signedData.count - imageData.count) bytes")
            
            // Verify the manifest was embedded
            if signedData.count > imageData.count {
                print("✅ Image size increased, manifest likely embedded")
                
                // Try to read back the manifest to verify
                do {
                    let verifyJSON = try C2PA.readFile(at: outputURL, dataDir: nil)
                    print("✅ Verification successful! Manifest found in output image")
                    print("Manifest preview: \(verifyJSON.prefix(200))...")
                } catch {
                    print("⚠️ Warning: Could not verify manifest in output: \(error)")
                }
            } else {
                print("❌ Warning: Output file is not larger than input, manifest may not be embedded")
            }
            
            return signedData
        } catch {
            print("❌ Error in C2PA signing: \(error)")
            throw error
        }
    }
    
    private func saveToPhotoLibrary(imageData: Data) async throws {
        let status = await PHPhotoLibrary.requestAuthorization(for: .addOnly)
        
        guard status == .authorized || status == .limited else {
            throw NSError(domain: "C2PAManager", code: 1, userInfo: [
                NSLocalizedDescriptionKey: "Photo library access denied"
            ])
        }
        
        try await PHPhotoLibrary.shared().performChanges {
            let creationRequest = PHAssetCreationRequest.forAsset()
            creationRequest.addResource(with: .photo, data: imageData, options: nil)
        }
    }
}