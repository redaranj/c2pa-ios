import SwiftUI
import UniformTypeIdentifiers

extension UTType {
    static let pemCertificate = UTType(filenameExtension: "pem")!
    static let crtCertificate = UTType(filenameExtension: "crt")!
    static let derCertificate = UTType(filenameExtension: "der")!
    static let keyFile = UTType(filenameExtension: "key")!
}

struct SettingsView: View {
    @Binding var isPresented: Bool
    @AppStorage("certificatePath") private var certificatePath: String = ""
    @AppStorage("privateKeyPath") private var privateKeyPath: String = ""
    @State private var showingCertificatePicker = false
    @State private var showingKeyPicker = false
    @State private var certificateData: Data?
    @State private var privateKeyData: Data?
    @State private var statusMessage = ""
    
    var body: some View {
        NavigationView {
            Form {
                Section(header: Text("C2PA Signing Certificate")) {
                    VStack(alignment: .leading, spacing: 10) {
                        Button("Select Certificate (.pem/.crt)") {
                            showingCertificatePicker = true
                        }
                        .buttonStyle(.borderedProminent)
                        
                        if !certificatePath.isEmpty {
                            Label(certificatePath.components(separatedBy: "/").last ?? "Certificate selected", 
                                  systemImage: "checkmark.seal.fill")
                                .foregroundColor(.green)
                                .font(.caption)
                        }
                    }
                    .padding(.vertical, 5)
                }
                
                Section(header: Text("Private Key")) {
                    VStack(alignment: .leading, spacing: 10) {
                        Button("Select Private Key (.pem/.key)") {
                            showingKeyPicker = true
                        }
                        .buttonStyle(.borderedProminent)
                        
                        if !privateKeyPath.isEmpty {
                            Label(privateKeyPath.components(separatedBy: "/").last ?? "Key selected", 
                                  systemImage: "key.fill")
                                .foregroundColor(.green)
                                .font(.caption)
                        }
                    }
                    .padding(.vertical, 5)
                }
                
                Section(header: Text("Status")) {
                    if !statusMessage.isEmpty {
                        Text(statusMessage)
                            .foregroundColor(.secondary)
                            .font(.caption)
                    } else if !certificatePath.isEmpty && !privateKeyPath.isEmpty {
                        VStack(alignment: .leading, spacing: 5) {
                            Label("Using custom certificates", systemImage: "person.circle.fill")
                                .foregroundColor(.blue)
                            Label("Ready to sign", systemImage: "checkmark.circle.fill")
                                .foregroundColor(.green)
                                .font(.caption)
                        }
                    } else {
                        VStack(alignment: .leading, spacing: 5) {
                            Label("Using default certificates", systemImage: "checkmark.shield.fill")
                                .foregroundColor(.green)
                            Text("C2PA Example demo certificates are being used. You can add your own certificates above.")
                                .font(.caption)
                                .foregroundColor(.secondary)
                        }
                    }
                }
                
                Section(header: Text("Certificate Info")) {
                    if !certificatePath.isEmpty && !privateKeyPath.isEmpty {
                        VStack(alignment: .leading, spacing: 10) {
                            Text("Custom Certificate Active")
                                .font(.headline)
                            Text("Certificate: \(certificatePath)")
                                .font(.caption)
                                .foregroundColor(.secondary)
                            Text("Key: \(privateKeyPath)")
                                .font(.caption)
                                .foregroundColor(.secondary)
                        }
                    } else {
                        VStack(alignment: .leading, spacing: 10) {
                            Text("Default Certificate Active")
                                .font(.headline)
                            Text("Using C2PA Example ES256 demo certificate")
                                .font(.caption)
                                .foregroundColor(.secondary)
                            Text("This certificate is for testing purposes only")
                                .font(.caption)
                                .foregroundColor(.orange)
                        }
                    }
                }
                
                Section {
                    Button("Clear Custom Certificates", role: .destructive) {
                        certificatePath = ""
                        privateKeyPath = ""
                        certificateData = nil
                        privateKeyData = nil
                        UserDefaults.standard.removeObject(forKey: "certificateData")
                        UserDefaults.standard.removeObject(forKey: "privateKeyData")
                        statusMessage = "Custom certificates cleared, using defaults"
                    }
                    .disabled(certificatePath.isEmpty && privateKeyPath.isEmpty)
                }
            }
            .navigationTitle("Settings")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("Done") {
                        isPresented = false
                    }
                }
            }
        }
        .fileImporter(
            isPresented: $showingCertificatePicker,
            allowedContentTypes: [.pemCertificate, .crtCertificate, .derCertificate, .x509Certificate, .item],
            allowsMultipleSelection: false
        ) { result in
            handleFileSelection(result: result, isCertificate: true)
        }
        .fileImporter(
            isPresented: $showingKeyPicker,
            allowedContentTypes: [.pemCertificate, .keyFile, .item],
            allowsMultipleSelection: false
        ) { result in
            handleFileSelection(result: result, isCertificate: false)
        }
    }
    
    private func handleFileSelection(result: Result<[URL], Error>, isCertificate: Bool) {
        switch result {
        case .success(let urls):
            guard let url = urls.first else { return }
            
            do {
                let accessing = url.startAccessingSecurityScopedResource()
                defer {
                    if accessing {
                        url.stopAccessingSecurityScopedResource()
                    }
                }
                
                let data = try Data(contentsOf: url)
                
                if isCertificate {
                    certificateData = data
                    certificatePath = url.lastPathComponent
                    UserDefaults.standard.set(data, forKey: "certificateData")
                } else {
                    privateKeyData = data
                    privateKeyPath = url.lastPathComponent
                    UserDefaults.standard.set(data, forKey: "privateKeyData")
                }
                
                statusMessage = "\(isCertificate ? "Certificate" : "Key") loaded successfully"
            } catch {
                statusMessage = "Error loading file: \(error.localizedDescription)"
            }
            
        case .failure(let error):
            statusMessage = "Selection failed: \(error.localizedDescription)"
        }
    }
}