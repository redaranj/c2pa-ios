import Foundation
import UIKit
import Photos
import PhotosUI
import C2PA
import CoreLocation
import ImageIO

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
    
    func signAndSaveImage(_ image: UIImage, saveToPhotos: Bool = false, location: CLLocation? = nil, completion: @escaping (Bool, String?, Data?) -> Void) {
        isProcessing = true
        lastError = nil
        
        Task {
            do {
                guard let imageData = image.jpegData(compressionQuality: 0.9) else {
                    await MainActor.run {
                        self.isProcessing = false
                        self.lastError = "Failed to convert image to JPEG"
                        completion(false, self.lastError, nil)
                    }
                    return
                }
                
                print("📸 Original image data size: \(imageData.count) bytes")
                
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
                        isCustom: true,
                        location: location
                    )
                } else if let certData = defaultCertificateData, let keyData = defaultPrivateKeyData {
                    // Use default certificates from bundle
                    print("Using default certificates for signing")
                    signedImageData = try await signWithCertificate(
                        imageData: imageData,
                        certificateData: certData,
                        privateKeyData: keyData,
                        isCustom: false,
                        location: location
                    )
                } else {
                    throw NSError(domain: "C2PAManager", code: 2, userInfo: [
                        NSLocalizedDescriptionKey: "No certificates available for signing"
                    ])
                }
                
                print("📸 Signed image data size: \(signedImageData.count) bytes")
                print("📸 Size difference: \(signedImageData.count - imageData.count) bytes")
                
                // Save to app's documents directory (preserves C2PA metadata)
                let savedURL = try PhotoStorageManager.shared.saveSignedPhoto(signedImageData)
                print("✅ Saved signed photo with C2PA credentials to app storage")
                print("📁 File: \(savedURL.lastPathComponent)")
                
                // Verify the saved file has C2PA
                do {
                    _ = try C2PA.readFile(at: savedURL, dataDir: nil)
                    print("✅ VERIFIED: Saved file HAS C2PA credentials!")
                } catch {
                    print("⚠️ Warning: Could not verify C2PA in saved file")
                }
                
                if saveToPhotos {
                    print("📸 Also saving to photo library (warning: metadata will be stripped)...")
                    try await saveToPhotoLibrary(imageData: signedImageData)
                    print("✅ Saved to photo library (without C2PA metadata)")
                }
                
                // Return the signed data and saved URL
                let fileName = savedURL.lastPathComponent
                let imageDataCopy = signedImageData
                await MainActor.run {
                    self.isProcessing = false
                    completion(true, fileName, imageDataCopy)
                }
            } catch {
                print("❌ Error saving image: \(error)")
                await MainActor.run {
                    self.isProcessing = false
                    self.lastError = error.localizedDescription
                    completion(false, error.localizedDescription, nil)
                }
            }
        }
    }
    
    private func signWithCertificate(imageData: Data, certificateData: Data, privateKeyData: Data, isCustom: Bool, location: CLLocation? = nil) async throws -> Data {
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
            print("Input file exists: \(FileManager.default.fileExists(atPath: inputURL.path))")
            print("Certificate loaded: \(certString.prefix(50))...")
            print("Certificate length: \(certString.count) characters")
            print("Private key length: \(keyString.count) characters")
            print("Using \(isCustom ? "custom" : "default") certificates")
            
            // Validate certificate format
            if !certString.contains("BEGIN CERTIFICATE") {
                print("⚠️ Warning: Certificate doesn't contain BEGIN CERTIFICATE marker")
            }
            if !keyString.contains("BEGIN PRIVATE KEY") && !keyString.contains("BEGIN EC PRIVATE KEY") {
                print("⚠️ Warning: Private key doesn't contain expected BEGIN marker")
            }
            
            // Extract actual EXIF metadata from the image
            var exifData: [String: Any] = [:]
            if let imageSource = CGImageSourceCreateWithData(imageData as CFData, nil),
               let properties = CGImageSourceCopyPropertiesAtIndex(imageSource, 0, nil) as? [String: Any] {
                
                // Extract EXIF dictionary
                if let exifDict = properties[kCGImagePropertyExifDictionary as String] as? [String: Any] {
                    exifData = exifDict
                    print("📸 Found EXIF data: \(exifDict.keys.joined(separator: ", "))")
                }
                
                // Extract GPS dictionary for location
                if let gpsDict = properties[kCGImagePropertyGPSDictionary as String] as? [String: Any] {
                    exifData["GPS"] = gpsDict
                    print("📍 Found GPS data: \(gpsDict)")
                }
                
                // Extract image dimensions
                if let width = properties[kCGImagePropertyPixelWidth as String] as? Int {
                    exifData["PixelWidth"] = width
                }
                if let height = properties[kCGImagePropertyPixelHeight as String] as? Int {
                    exifData["PixelHeight"] = height
                }
            }
            
            // Create manifest with actual EXIF data
            let currentDate = ISO8601DateFormatter().string(from: Date())
            let deviceModel = await MainActor.run { UIDevice.current.model }
            let osVersion = await MainActor.run { UIDevice.current.systemVersion }
            // Build EXIF assertion data
            var exifAssertionData: [String: Any] = [
                "@context": ["exif": "http://ns.adobe.com/exif/1.0/"],
                "exif:Make": "Apple",
                "exif:Model": deviceModel,
                "exif:Software": "C2PA Example iOS \(osVersion)",
                "exif:DateTimeOriginal": currentDate,
                "exif:DateTimeDigitized": currentDate
            ]
            
            // Add actual dimensions if available
            if let width = exifData["PixelWidth"] as? Int {
                exifAssertionData["exif:PixelXDimension"] = "\(width)"
            } else {
                exifAssertionData["exif:PixelXDimension"] = "4032"
            }
            
            if let height = exifData["PixelHeight"] as? Int {
                exifAssertionData["exif:PixelYDimension"] = "\(height)"
            } else {
                exifAssertionData["exif:PixelYDimension"] = "3024"
            }
            
            // Add actual EXIF values if available
            if let focalLength = exifData[kCGImagePropertyExifFocalLength as String] {
                exifAssertionData["exif:FocalLength"] = "\(focalLength)"
            } else {
                exifAssertionData["exif:FocalLength"] = "4.25"
            }
            
            if let fNumber = exifData[kCGImagePropertyExifFNumber as String] {
                exifAssertionData["exif:FNumber"] = "\(fNumber)"
            } else {
                exifAssertionData["exif:FNumber"] = "1.6"
            }
            
            if let exposureTime = exifData[kCGImagePropertyExifExposureTime as String] {
                exifAssertionData["exif:ExposureTime"] = "\(exposureTime)"
            } else {
                exifAssertionData["exif:ExposureTime"] = "1/120"
            }
            
            if let iso = exifData[kCGImagePropertyExifISOSpeedRatings as String] as? [Int], let isoValue = iso.first {
                exifAssertionData["exif:ISOSpeedRatings"] = "\(isoValue)"
            } else {
                exifAssertionData["exif:ISOSpeedRatings"] = "100"
            }
            
            if let whiteBalance = exifData[kCGImagePropertyExifWhiteBalance as String] {
                exifAssertionData["exif:WhiteBalance"] = "\(whiteBalance)"
            } else {
                exifAssertionData["exif:WhiteBalance"] = "0"
            }
            
            if let flash = exifData[kCGImagePropertyExifFlash as String] {
                exifAssertionData["exif:Flash"] = "\(flash)"
            } else {
                exifAssertionData["exif:Flash"] = "0"
            }
            
            if let lensModel = exifData[kCGImagePropertyExifLensModel as String] {
                exifAssertionData["exif:LensModel"] = "\(lensModel)"
            } else {
                exifAssertionData["exif:LensModel"] = "iPhone Camera"
            }
            
            // Add GPS data - try from image metadata first, then use location parameter
            var gpsAdded = false
            
            if let gpsData = exifData["GPS"] as? [String: Any] {
                print("📍 GPS Data found in metadata: \(gpsData)")
                
                // Convert GPS coordinates to decimal degrees format expected by C2PA
                if let latitude = gpsData[kCGImagePropertyGPSLatitude as String] as? Double {
                    let latRef = gpsData[kCGImagePropertyGPSLatitudeRef as String] as? String ?? "N"
                    let latValue = latRef == "S" ? -latitude : latitude
                    exifAssertionData["exif:GPSLatitude"] = "\(latValue)"
                    print("📍 Metadata Latitude: \(latValue)")
                    gpsAdded = true
                }
                
                if let longitude = gpsData[kCGImagePropertyGPSLongitude as String] as? Double {
                    let lonRef = gpsData[kCGImagePropertyGPSLongitudeRef as String] as? String ?? "E"
                    let lonValue = lonRef == "W" ? -longitude : longitude
                    exifAssertionData["exif:GPSLongitude"] = "\(lonValue)"
                    print("📍 Metadata Longitude: \(lonValue)")
                    gpsAdded = true
                }
                
                if let altitude = gpsData[kCGImagePropertyGPSAltitude as String] as? Double {
                    exifAssertionData["exif:GPSAltitude"] = "\(altitude)"
                    print("📍 Metadata Altitude: \(altitude)")
                }
            }
            
            // If no GPS in metadata, use the location parameter
            if !gpsAdded, let location = location {
                print("📍 Using location parameter: lat=\(location.coordinate.latitude), lon=\(location.coordinate.longitude)")
                exifAssertionData["exif:GPSLatitude"] = "\(location.coordinate.latitude)"
                exifAssertionData["exif:GPSLongitude"] = "\(location.coordinate.longitude)"
                exifAssertionData["exif:GPSAltitude"] = "\(location.altitude)"
                gpsAdded = true
            }
            
            if !gpsAdded {
                print("⚠️ No GPS data available from metadata or location parameter")
            }
            
            // Add additional EXIF fields
            if let colorSpace = exifData[kCGImagePropertyExifColorSpace as String] {
                exifAssertionData["exif:ColorSpace"] = "\(colorSpace)"
            } else {
                exifAssertionData["exif:ColorSpace"] = "1"
            }
            
            if let exifVersion = exifData[kCGImagePropertyExifVersion as String] {
                exifAssertionData["exif:ExifVersion"] = "\(exifVersion)"
            } else {
                exifAssertionData["exif:ExifVersion"] = "0232"
            }
            
            exifAssertionData["exif:OffsetTime"] = "+00:00"
            
            // Convert EXIF data to JSON string
            let exifJSONData = try JSONSerialization.data(withJSONObject: exifAssertionData, options: [.sortedKeys])
            let exifJSONString = String(data: exifJSONData, encoding: .utf8) ?? "{}"
            
            let manifestJSON = """
            {
                "claim_generator": "C2PA Example/1.0.0",
                "title": "C2PA Example Image",
                "format": "image/jpeg",
                "assertions": [
                    {
                        "label": "c2pa.actions",
                        "data": {
                            "actions": [
                                {
                                    "action": "c2pa.created",
                                    "when": "\(currentDate)",
                                    "softwareAgent": "C2PA Example iOS/1.0.0"
                                }
                            ]
                        }
                    },
                    {
                        "label": "stds.exif",
                        "data": \(exifJSONString)
                    }
                ]
            }
            """
            
            print("Manifest JSON: \(manifestJSON)")
            
            // Try using the Builder/Stream API for better error handling
            print("Using Builder/Stream API...")
            
            do {
                // Create builder from manifest
                let builder = try Builder(manifestJSON: manifestJSON)
                print("✅ Builder created successfully")
                
                // Create signer
                let signer = try C2PASigner(
                    certsPEM: certString,
                    privateKeyPEM: keyString,
                    algorithm: .es256,
                    tsaURL: nil
                )
                print("✅ Signer created successfully")
                
                // Create streams
                let sourceStream = try Stream(fileURL: inputURL, truncate: false, createIfNeeded: false)
                let destStream = try Stream(fileURL: outputURL, truncate: true, createIfNeeded: true)
                print("✅ Streams created successfully")
                
                // Sign
                let manifestData = try builder.sign(
                    format: "image/jpeg",
                    source: sourceStream,
                    destination: destStream,
                    signer: signer
                )
                print("✅ Signing completed, manifest data size: \(manifestData.count)")
                
            } catch {
                print("❌ Builder/Stream API error details:")
                print("   Error: \(error)")
                print("   Error type: \(type(of: error))")
                if let c2paError = error as? C2PAError {
                    print("   C2PA Error: \(c2paError.description)")
                }
                
                // Fall back to file-based signing as last resort
                print("Falling back to file-based signing...")
                let signerInfo = SignerInfo(
                    algorithm: .es256,
                    certificatePEM: certString,
                    privateKeyPEM: keyString,
                    tsaURL: nil
                )
                
                try C2PA.signFile(
                    source: inputURL,
                    destination: outputURL,
                    manifestJSON: manifestJSON,
                    signerInfo: signerInfo,
                    dataDir: nil
                )
            }
            
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
        let status = await PHPhotoLibrary.requestAuthorization(for: .readWrite)
        
        guard status == .authorized || status == .limited else {
            throw NSError(domain: "C2PAManager", code: 1, userInfo: [
                NSLocalizedDescriptionKey: "Photo library access denied"
            ])
        }
        
        // Save the image and get its identifier
        var savedAssetIdentifier: String?
        try await PHPhotoLibrary.shared().performChanges {
            let creationRequest = PHAssetCreationRequest.forAsset()
            creationRequest.addResource(with: .photo, data: imageData, options: nil)
            savedAssetIdentifier = creationRequest.placeholderForCreatedAsset?.localIdentifier
        }
        
        // Verify the saved image has C2PA credentials
        if let assetId = savedAssetIdentifier {
            print("📸 Saved photo with identifier: \(assetId)")
            print("📸 Verifying C2PA credentials in saved photo...")
            
            // Fetch the saved asset
            let fetchResult = PHAsset.fetchAssets(withLocalIdentifiers: [assetId], options: nil)
            if let asset = fetchResult.firstObject {
                print("📸 Found saved asset, requesting image data...")
                
                // Get the image data from the saved photo
                let options = PHImageRequestOptions()
                options.isSynchronous = false
                options.isNetworkAccessAllowed = true
                options.deliveryMode = .highQualityFormat
                
                await withCheckedContinuation { (continuation: CheckedContinuation<Void, Never>) in
                    PHImageManager.default().requestImageDataAndOrientation(for: asset, options: options) { imageData, dataUTI, orientation, info in
                        if let data = imageData {
                            print("📸 Retrieved saved photo data: \(data.count) bytes")
                            
                            // Write to temp file and verify C2PA
                            let tempURL = FileManager.default.temporaryDirectory.appendingPathComponent("verify_\(UUID().uuidString).jpg")
                            do {
                                try data.write(to: tempURL)
                                
                                // Try to read C2PA manifest from saved photo
                                do {
                                    let manifest = try C2PA.readFile(at: tempURL, dataDir: nil)
                                    print("✅ VERIFICATION SUCCESS: Saved photo HAS C2PA credentials!")
                                    print("📸 Manifest preview: \(manifest.prefix(200))...")
                                } catch {
                                    print("❌ VERIFICATION FAILED: Saved photo has NO C2PA credentials!")
                                    print("❌ Error: \(error)")
                                    print("⚠️ iOS may have stripped the metadata during save!")
                                }
                                
                                // Clean up
                                try? FileManager.default.removeItem(at: tempURL)
                            } catch {
                                print("❌ Error verifying saved photo: \(error)")
                            }
                        } else {
                            print("❌ Could not retrieve image data from saved photo")
                        }
                        continuation.resume()
                    }
                }
            } else {
                print("❌ Could not fetch saved asset with ID: \(assetId)")
            }
        }
    }
}
