import Foundation

enum Constants {
    enum Image {
        static let jpegCompressionQuality: Double = 0.9
    }

    enum Keychain {
        static let keychainPrivateKeyTag = "org.contentauth.ExampleApp.keychain.privatekey"
        static let secureEnclaveKeyTag = "org.contentauth.ExampleApp.secureenclave.key"
        static let customCertificateKey = "org.contentauth.ExampleApp.custom.certificate"
        static let customPrivateKeyKey = "org.contentauth.ExampleApp.custom.privatekey"
        static let customPrivateKeyTag = "org.contentauth.ExampleApp.custom.keychain.privatekey"
        static let certChainSuffix = ".certchain"
    }

    enum UserDefaultsKeys {
        static let signingMode = "signingMode"
        static let remoteSigningURL = "remoteSigningURL"
        static let remoteBearerToken = "remoteBearerToken"
    }

    enum C2PA {
        static let claimGenerator = "C2PA Example/1.0.0"
        static let defaultFormat = "image/jpeg"
    }
}
