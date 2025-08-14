import Foundation
import UIKit
import UniformTypeIdentifiers

class FileSaveManager {
    // Store delegates to prevent deallocation
    private static var retainedDelegates: Set<DocumentPickerDelegate> = []
    
    static func saveToFiles(imageData: Data, fileName: String, from viewController: UIViewController, completion: @escaping (Bool, String?) -> Void) {
        // Create a temporary file
        let tempDir = FileManager.default.temporaryDirectory
        let fileURL = tempDir.appendingPathComponent(fileName)
        
        do {
            // Write the data to temporary file
            try imageData.write(to: fileURL)
            
            // Create the delegate first without cleanup logic
            let delegate = DocumentPickerDelegate()
            
            // Set up the completion handler with cleanup
            delegate.completion = { success, message in
                completion(success, message)
                // Clean up the delegate after completion
                FileSaveManager.retainedDelegates.remove(delegate)
            }
            
            // Retain the delegate
            retainedDelegates.insert(delegate)
            
            // Create document picker for saving
            let documentPicker = UIDocumentPickerViewController(forExporting: [fileURL], asCopy: true)
            documentPicker.delegate = delegate
            documentPicker.shouldShowFileExtensions = true
            
            // Present the picker
            viewController.present(documentPicker, animated: true)
            
        } catch {
            completion(false, "Failed to prepare file: \(error.localizedDescription)")
        }
    }
}

private class DocumentPickerDelegate: NSObject, UIDocumentPickerDelegate {
    var completion: ((Bool, String?) -> Void)?
    
    override init() {
        super.init()
    }
    
    func documentPicker(_ controller: UIDocumentPickerViewController, didPickDocumentsAt urls: [URL]) {
        // File was successfully saved
        completion?(true, "File saved to: \(urls.first?.lastPathComponent ?? "Unknown")")
    }
    
    func documentPickerWasCancelled(_ controller: UIDocumentPickerViewController) {
        completion?(false, "Save cancelled")
    }
}

// Make DocumentPickerDelegate Hashable for Set storage
extension DocumentPickerDelegate {
    static func == (lhs: DocumentPickerDelegate, rhs: DocumentPickerDelegate) -> Bool {
        return lhs === rhs
    }
    
    override var hash: Int {
        return ObjectIdentifier(self).hashValue
    }
}

extension FileSaveManager {
    static func createShareSheet(for imageData: Data, fileName: String, from viewController: UIViewController) {
        // Create a temporary file
        let tempDir = FileManager.default.temporaryDirectory
        let fileURL = tempDir.appendingPathComponent(fileName)
        
        do {
            try imageData.write(to: fileURL)
            
            // Create activity controller
            let activityController = UIActivityViewController(
                activityItems: [fileURL],
                applicationActivities: nil
            )
            
            // Exclude certain activities
            activityController.excludedActivityTypes = [
                .saveToCameraRoll, // Exclude camera roll to avoid metadata stripping
                .assignToContact,
                .addToReadingList,
                .postToFacebook,
                .postToTwitter,
                .postToWeibo,
                .postToVimeo,
                .postToTencentWeibo,
                .postToFlickr
            ]
            
            // For iPad
            if let popover = activityController.popoverPresentationController {
                popover.sourceView = viewController.view
                popover.sourceRect = CGRect(x: viewController.view.bounds.midX, y: viewController.view.bounds.midY, width: 0, height: 0)
                popover.permittedArrowDirections = []
            }
            
            viewController.present(activityController, animated: true)
            
        } catch {
            print("Error creating share sheet: \(error)")
        }
    }
}