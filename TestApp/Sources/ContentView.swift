import SwiftUI
import C2PA

struct ContentView: View {
    @State private var testResults: [TestResult] = []
    @State private var isRunning = false
    
    var body: some View {
        NavigationView {
            VStack {
                if isRunning {
                    ProgressView("Running tests...")
                        .padding()
                } else {
                    Button("Run Tests") {
                        runTests()
                    }
                    .buttonStyle(.borderedProminent)
                    .padding()
                }
                
                List(testResults) { result in
                    HStack {
                        Image(systemName: result.passed ? "checkmark.circle.fill" : "xmark.circle.fill")
                            .foregroundColor(result.passed ? .green : .red)
                        VStack(alignment: .leading) {
                            Text(result.name)
                                .font(.headline)
                            if let error = result.error {
                                Text(error)
                                    .font(.caption)
                                    .foregroundColor(.red)
                            }
                        }
                    }
                }
            }
            .navigationTitle("C2PA Tests")
        }
    }
    
    func runTests() {
        isRunning = true
        testResults = []
        
        Task {
            let runner = TestRunner()
            let results = await runner.runAllTests()
            
            await MainActor.run {
                testResults = results
                isRunning = false
            }
        }
    }
}

struct TestResult: Identifiable {
    let id = UUID()
    let name: String
    let passed: Bool
    let error: String?
}

struct ContentView_Previews: PreviewProvider {
    static var previews: some View {
        ContentView()
    }
}