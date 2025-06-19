import SwiftUI

struct C2PATestView: View {
    @State private var isRunning = false
    @State private var testResults: [TestResult] = []

    var body: some View {
        NavigationView {
            VStack {
                if isRunning {
                    ProgressView("Running tests...")
                        .padding()
                } else {
                    Button(action: {
                        runTests()
                    }) {
                        Text("Run Tests")
                            .frame(maxWidth: .infinity)
                            .padding()
                            .background(Color.blue)
                            .foregroundColor(.white)
                            .cornerRadius(8)
                    }
                    .padding(.horizontal)
                }

                List(testResults) { result in
                    VStack(alignment: .leading, spacing: 4) {
                        HStack {
                            Image(systemName: result.success ? "checkmark.circle.fill" : "xmark.circle.fill")
                                .foregroundColor(result.success ? .green : .red)
                            Text(result.name)
                                .font(.headline)
                        }
                        
                        Text(result.message)
                            .font(.subheadline)
                            .foregroundColor(.secondary)
                        
                        if let details = result.details {
                            Text(details)
                                .font(.caption)
                                .foregroundColor(.secondary)
                        }
                    }
                    .padding(.vertical, 4)
                }
            }
            .navigationTitle("C2PA Tests")
        }
    }

    func runTests() {
        isRunning = true
        testResults = []

        Task {
            let results = await TestEngine.shared.runAllTests()
            
            await MainActor.run {
                self.testResults = results
                self.isRunning = false
            }
        }
    }
}

#Preview {
    C2PATestView()
}