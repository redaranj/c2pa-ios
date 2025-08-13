import SwiftUI
import PhotosUI

struct ContentView: View {
    @State private var showingCamera = true  // Start with camera open
    @State private var showingSettings = false
    @State private var showingVerify = false
    @State private var capturedImage: UIImage?
    @State private var showingAlert = false
    @State private var alertMessage = ""
    @StateObject private var c2paManager = C2PAManager.shared
    
    var body: some View {
        ZStack {
            // Always show camera view as the main interface
            CameraViewWrapper(
                showingCamera: $showingCamera,
                showingSettings: $showingSettings,
                showingVerify: $showingVerify,
                capturedImage: $capturedImage
            )
            .edgesIgnoringSafeArea(.all)
            
            if c2paManager.isProcessing {
                Color.black.opacity(0.5)
                    .edgesIgnoringSafeArea(.all)
                
                VStack {
                    ProgressView()
                        .progressViewStyle(CircularProgressViewStyle(tint: .white))
                        .scaleEffect(1.5)
                    
                    Text("Signing image...")
                        .foregroundColor(.white)
                        .padding(.top)
                }
            }
        }
        .sheet(isPresented: $showingSettings) {
            SettingsView(isPresented: $showingSettings)
        }
        .sheet(isPresented: $showingVerify) {
            VerifyWebView(isPresented: $showingVerify)
        }
        .alert("C2PA Signing", isPresented: $showingAlert) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(alertMessage)
        }
    }
}

struct CameraViewWrapper: View {
    @Binding var showingCamera: Bool
    @Binding var showingSettings: Bool
    @Binding var showingVerify: Bool
    @Binding var capturedImage: UIImage?
    @StateObject private var c2paManager = C2PAManager.shared
    @State private var showingAlert = false
    @State private var alertMessage = ""
    
    var body: some View {
        ZStack {
            CameraView(capturedImage: $capturedImage) { image in
                c2paManager.signAndSaveImage(image) { success, error in
                    showingCamera = false
                    if success {
                        alertMessage = "Photo saved with C2PA credentials!"
                    } else {
                        alertMessage = "Error: \(error ?? "Unknown error")"
                    }
                    showingAlert = true
                }
            }
            
            VStack {
                HStack {
                    Button(action: {
                        showingSettings = true
                    }) {
                        Image(systemName: "gearshape.fill")
                            .font(.title2)
                            .padding()
                            .background(Color.black.opacity(0.7))
                            .foregroundColor(.white)
                            .clipShape(Circle())
                    }
                    .padding(.leading)
                    
                    Spacer()
                    
                    Button(action: {
                        showingVerify = true
                    }) {
                        Image(systemName: "checkmark.shield.fill")
                            .font(.title2)
                            .padding()
                            .background(Color.black.opacity(0.7))
                            .foregroundColor(.white)
                            .clipShape(Circle())
                    }
                    .padding(.trailing)
                }
                .padding(.top, 50)
                
                Spacer()
            }
        }
        .sheet(isPresented: $showingSettings) {
            SettingsView(isPresented: $showingSettings)
        }
        .sheet(isPresented: $showingVerify) {
            VerifyWebView(isPresented: $showingVerify)
        }
        .alert("C2PA Signing", isPresented: $showingAlert) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(alertMessage)
        }
    }
}

struct ContentView_Previews: PreviewProvider {
    static var previews: some View {
        ContentView()
    }
}