import SwiftUI
import C2PA

struct ContentView: View {
    var body: some View {
        VStack {
            Image(systemName: "photo.badge.checkmark")
                .imageScale(.large)
                .foregroundStyle(.tint)
                .padding()
            
            Text("C2PA Example App")
                .font(.title)
                .padding()
            
            Text("Ready for implementation")
                .foregroundColor(.secondary)
        }
        .padding()
    }
}

struct ContentView_Previews: PreviewProvider {
    static var previews: some View {
        ContentView()
    }
}