import Foundation
import UIKit

class PhotoStorageManager {
    static let shared = PhotoStorageManager()
    
    private let documentsDirectory: URL
    private let photosDirectory: URL
    
    private init() {
        documentsDirectory = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first!
        photosDirectory = documentsDirectory.appendingPathComponent("SignedPhotos")
        
        // Create the SignedPhotos directory if it doesn't exist
        try? FileManager.default.createDirectory(at: photosDirectory, withIntermediateDirectories: true)
    }
    
    func saveSignedPhoto(_ imageData: Data) throws -> URL {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd_HH-mm-ss"
        let timestamp = formatter.string(from: Date())
        let fileName = "C2PA_\(timestamp).jpg"
        
        let fileURL = photosDirectory.appendingPathComponent(fileName)
        try imageData.write(to: fileURL)
        
        print("📁 Saved signed photo to: \(fileURL.path)")
        return fileURL
    }
    
    func getLatestSignedPhoto() -> URL? {
        do {
            let files = try FileManager.default.contentsOfDirectory(
                at: photosDirectory,
                includingPropertiesForKeys: [.creationDateKey],
                options: .skipsHiddenFiles
            )
            
            let sortedFiles = files.sorted { url1, url2 in
                let date1 = (try? url1.resourceValues(forKeys: [.creationDateKey]).creationDate) ?? Date.distantPast
                let date2 = (try? url2.resourceValues(forKeys: [.creationDateKey]).creationDate) ?? Date.distantPast
                return date1 > date2
            }
            
            return sortedFiles.first
        } catch {
            print("Error getting latest photo: \(error)")
            return nil
        }
    }
    
    func getAllSignedPhotos() -> [URL] {
        do {
            let files = try FileManager.default.contentsOfDirectory(
                at: photosDirectory,
                includingPropertiesForKeys: [.creationDateKey],
                options: .skipsHiddenFiles
            )
            
            return files.sorted { url1, url2 in
                let date1 = (try? url1.resourceValues(forKeys: [.creationDateKey]).creationDate) ?? Date.distantPast
                let date2 = (try? url2.resourceValues(forKeys: [.creationDateKey]).creationDate) ?? Date.distantPast
                return date1 > date2
            }
        } catch {
            print("Error listing photos: \(error)")
            return []
        }
    }
    
    func getPhotosDirectoryURL() -> URL {
        return photosDirectory
    }
}