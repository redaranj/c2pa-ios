//
//  C2PA.swift
//

import C2PAC
import Foundation

public enum C2PA {
    public static func readFile(
        at url: URL,
        dataDir: URL? = nil
    ) throws -> String {
        try stringFromC(
            c2pa_read_file(url.path, dataDir?.path)
        )
    }

    public static func readIngredient(
        at url: URL,
        dataDir: URL? = nil
    ) throws -> String {
        let result = c2pa_read_ingredient_file(url.path, dataDir?.path)
        guard let result = result else {
            let errorMsg = lastC2PAError()
            // TODO: This special case handling may be removable if the underlying C API
            // is updated to handle NULL data_dir consistently with c2pa_read_file
            if errorMsg.contains("null parameter data_dir") || errorMsg.contains("data_dir") {
                throw C2PAError.api("No ingredient data found")
            }
            throw C2PAError.api(errorMsg)
        }
        return try stringFromC(result)
    }

    public static func signFile(
        source: URL,
        destination: URL,
        manifestJSON: String,
        signerInfo: SignerInfo,
        dataDir: URL? = nil
    ) throws {
        var maybeErr: UnsafeMutablePointer<CChar>?
        withSignerInfo(
            alg: signerInfo.algorithm.description,
            cert: signerInfo.certificatePEM,
            key: signerInfo.privateKeyPEM,
            tsa: signerInfo.tsaURL
        ) { algPtr, certPtr, keyPtr, tsaPtr in
            var sInfo = C2paSignerInfo(
                alg: algPtr,
                sign_cert: certPtr,
                private_key: keyPtr,
                ta_url: tsaPtr)
            maybeErr = c2pa_sign_file(
                source.path,
                destination.path,
                manifestJSON,
                &sInfo,
                dataDir?.path)
        }

        if let e = maybeErr {
            let msg = try stringFromC(e)
            throw C2PAError.api(msg)
        }
    }
}

public enum C2PAError: Error, CustomStringConvertible {
    case api(String)  // message from Rust layer
    case nilPointer  // unexpected NULL
    case utf8  // invalid UTF-8 returned
    case negative(Int64)  // negative status from C

    public var description: String {
        switch self {
        case let .api(m): return "C2PA-API error: \(m)"
        case .nilPointer: return "Unexpected NULL pointer"
        case .utf8: return "Invalid UTF-8 from C2PA"
        case let .negative(v): return "C2PA negative status \(v)"
        }
    }
}
