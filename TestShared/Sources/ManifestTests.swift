import C2PA
import Foundation

// Manifest tests - pure Swift implementation
public final class ManifestTests: TestImplementation {

    public init() {}

    public func testMinimal() -> TestResult {
        let manifest = ManifestDefinition(claimGeneratorInfo: [], title: "test")

        if manifest.claimVersion != 1 {
            return .failure("Manifest", "claimVersion != 1, got \(manifest.claimVersion)")
        }

        if manifest.format != "application/octet-stream" {
            return .failure("Manifest", "format != application/octet-stream, got \(manifest.format)")
        }

        if manifest.title != "test" {
            return .failure("Manifest", "title != test, got \(manifest.title)")
        }

        return cloneAndCompare(manifest)
    }

    public func testCreated() -> TestResult {
        let manifest = ManifestDefinition(
            assertions: [.actions(actions: [.init(action: .created, digitalSourceType: .digitalCapture)])],
            claimGeneratorInfo: [.init()],
            title: "test")

        guard case .actions(let actions) = manifest.assertions.first! else {
            return .failure("Manifest", "manifest.assertions.first != .actions")
        }

        guard let action = actions.first else {
            return .failure("Manifest", "actions.first == nil")
        }

        if action.action != "c2pa.created" {
            return .failure("Manifest", "action.action != c2pa.created, got \(action.action)")
        }

        if action.digitalSourceType != "http://cv.iptc.org/newscodes/digitalsourcetype/digitalCapture" {
            return .failure("Manifest", "action.digitalSourceType != http://cv.iptc.org/newscodes/digitalsourcetype/digitalCapture, got \(action.digitalSourceType ?? "(nil)")")
        }

        guard let info = manifest.claimGeneratorInfo.first else {
            return .failure("Manifest", "claimGeneratorInfo.first == nil")
        }

        if info.name != "xctest" {
            return .failure("Manifest", "claimGeneratorInfo.name != xctest, got \(manifest.claimGeneratorInfo.first?.name ?? "(nil)")")
        }

        guard let version = info.version else {
            return .failure("Manifest", "claimGeneratorInfo.version == nil")
        }

        let regex: NSRegularExpression

        do {
            regex = try NSRegularExpression(pattern: "^[\\d.]+$")
        } catch {
            return .failure("Manifest", "Error: \(error)")
        }

        guard let match = regex.firstMatch(in: version, range: .init(version.startIndex ..< version.endIndex, in: version)),
              match.range.lowerBound == 0 && match.range.upperBound == version.count
        else {
            return .failure("Manifest", "claimGeneratorInfo.version !~ /^[\\d.]+$/")
        }

        return cloneAndCompare(manifest)
    }

    public func testEnumRendering() -> TestResult {
        let shape = Shape(type: .rectangle, origin: .init(x: 10, y: 10), width: 80, height: 80, unit: .percent)

        do {
            let data = try JSONEncoder().encode(shape)
            let json = String(data: data, encoding: .utf8)

            let s2 = try JSONDecoder().decode(Shape.self, from: data)

            if shape == s2 {
                return .success("Manifest", "[PASS] enums rendered as expected.")
            } else {
                return .failure("Manifest", "JSON rendering unexpected: \(json ?? "(nil)")")
            }

        } catch {
            return .failure("Manifest", "Error: \(error)")
        }
    }

    @MainActor
    public func runAllTests() async -> [TestResult] {
        return [
            testMinimal(),
            testCreated(),
            testEnumRendering()
        ]
    }


    // MARK: Private Methods

    private func cloneAndCompare(_ manifest: ManifestDefinition) -> TestResult {
        guard let data = manifest.description.data(using: .utf8) else {
            return .failure("Manifest", "ManifestDefinition.description could not be decoded to UTF-8 Data!")
        }

        let m2: ManifestDefinition

        do {
            m2 = try JSONDecoder().decode(ManifestDefinition.self, from: data)
        } catch {
            return .failure("Manifest", "Error: \(error)")
        }

        if manifest == m2 {
            return .success("Manifest", "[PASS] Manifest rendered as expected.")
        }

        return .failure("Manifest", "Broken compiled manifest: \(manifest.description) != \(m2.description)")
    }
}
