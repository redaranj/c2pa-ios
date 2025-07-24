//
//  C2PA.swift
//

import C2PAC
import CryptoKit
import Foundation
import Security

// MARK: - Error model -------------------------------------------------------

public enum C2PAError: Error, CustomStringConvertible {
    case api(String) // message from Rust layer
    case nilPointer // unexpected NULL
    case utf8 // invalid UTF-8 returned
    case negative(Int64) // negative status from C

    public var description: String {
        switch self {
        case let .api(m): return "C2PA-API error: \(m)"
        case .nilPointer: return "Unexpected NULL pointer"
        case .utf8: return "Invalid UTF-8 from C2PA"
        case let .negative(v): return "C2PA negative status \(v)"
        }
    }
}

// MARK: - Tiny helpers  -----------------------------------------------------

@inline(__always)
private func stringFromC(_ p: UnsafeMutablePointer<CChar>?) throws -> String {
    guard let p else { throw C2PAError.api(lastC2PAError()) }
    defer { c2pa_string_free(p) }
    guard let s = String(validatingUTF8: p) else { throw C2PAError.utf8 }
    return s
}

@inline(__always)
private func lastC2PAError() -> String {
    guard let p = c2pa_error() else { return "Unknown C2PA error" }
    defer { c2pa_string_free(p) }
    return String(cString: p)
}

@inline(__always)
private func guardNotNull<T>(_ p: UnsafeMutablePointer<T>?) throws -> UnsafeMutablePointer<T> {
    if let p { return p }
    throw C2PAError.api(lastC2PAError())
}

@inline(__always)
@discardableResult
private func guardNonNegative(_ v: Int64) throws -> Int64 {
    if v < 0 { throw C2PAError.api(lastC2PAError()) }
    return v
}

/// Borrow 4 strings for one call (alg, cert, key, tsa)
@inline(__always)
private func withSignerInfo<R>(
    alg: String, cert: String, key: String, tsa: String?,
    _ body: (UnsafePointer<CChar>, UnsafePointer<CChar>,
             UnsafePointer<CChar>, UnsafePointer<CChar>?) throws -> R
) rethrows -> R {
    try alg.withCString { algPtr in
        try cert.withCString { certPtr in
            try key.withCString { keyPtr in
                if let tsa {
                    return try tsa.withCString { tsaPtr in
                        try body(algPtr, certPtr, keyPtr, tsaPtr)
                    }
                } else {
                    return try body(algPtr, certPtr, keyPtr, nil)
                }
            }
        }
    }
}

/// Borrow optional `String` → `char*` (NULL if nil)
@inline(__always)
private func withOptionalCString<R>(
    _ s: String?, _ body: (UnsafePointer<CChar>?) throws -> R
) rethrows -> R {
    if let s {
        return try s.withCString(body)
    } else {
        return try body(nil)
    }
}

/// Cast opaque pointer to requested `StreamContext*`
@inline(__always)
private func asStreamCtx(_ p: UnsafeMutableRawPointer) -> UnsafeMutablePointer<StreamContext> {
    UnsafeMutablePointer<StreamContext>(OpaquePointer(p))
}

/// C2PA version fetched once
public let C2PAVersion: String = {
    let p = c2pa_version()!
    defer { c2pa_string_free(p) }
    return String(cString: p)
}()

// MARK: - Signing layer -----------------------------------------------------

public enum SigningAlgorithm {
    case es256, es384, es512, ps256, ps384, ps512, ed25519

    fileprivate var cValue: C2paSigningAlg {
        switch self {
        case .es256: return Es256
        case .es384: return Es384
        case .es512: return Es512
        case .ps256: return Ps256
        case .ps384: return Ps384
        case .ps512: return Ps512
        case .ed25519: return Ed25519
        }
    }

    public var description: String {
        switch self {
        case .es256: return "es256"
        case .es384: return "es384"
        case .es512: return "es512"
        case .ps256: return "ps256"
        case .ps384: return "ps384"
        case .ps512: return "ps512"
        case .ed25519: return "ed25519"
        }
    }
}

public struct SignerInfo {
    public let algorithm: SigningAlgorithm
    public let certificatePEM: String
    public let privateKeyPEM: String
    public let tsaURL: String?

    public init(algorithm: SigningAlgorithm,
                certificatePEM: String,
                privateKeyPEM: String,
                tsaURL: String? = nil)
    {
        self.algorithm = algorithm
        self.certificatePEM = certificatePEM
        self.privateKeyPEM = privateKeyPEM
        self.tsaURL = tsaURL
    }
}

public final class Signer {
    // raw pointer owned
    let ptr: UnsafeMutablePointer<C2paSigner>
    private var retainedContext: Unmanaged<AnyObject>?

    /// internal designated init
    private init(ptr: UnsafeMutablePointer<C2paSigner>) {
        self.ptr = ptr
    }

    // --------------------------------------------------------------------
    // 1) PEM-based convenience
    // --------------------------------------------------------------------
    public convenience init(certsPEM: String,
                            privateKeyPEM: String,
                            algorithm: SigningAlgorithm,
                            tsaURL: String? = nil) throws
    {
        var raw: UnsafeMutablePointer<C2paSigner>!
        try withSignerInfo(alg: algorithm.description,
                           cert: certsPEM,
                           key: privateKeyPEM,
                           tsa: tsaURL)
        { algPtr, certPtr, keyPtr, tsaPtr in
            var info = C2paSignerInfo(alg: algPtr,
                                      sign_cert: certPtr,
                                      private_key: keyPtr,
                                      ta_url: tsaPtr)
            raw = try guardNotNull(c2pa_signer_from_info(&info))
        }
        self.init(ptr: raw)
    }

    public convenience init(info: SignerInfo) throws {
        try self.init(certsPEM: info.certificatePEM,
                      privateKeyPEM: info.privateKeyPEM,
                      algorithm: info.algorithm,
                      tsaURL: info.tsaURL)
    }

    // --------------------------------------------------------------------
    // 2) Swift-native closure  (Data in → Data out)
    // --------------------------------------------------------------------
    public convenience init(algorithm: SigningAlgorithm,
                            certificateChainPEM: String,
                            tsaURL: String? = nil,
                            sign: @escaping (Data) throws -> Data) throws
    {
        // keep closure alive
        final class Box {
            let fn: (Data) throws -> Data
            init(_ fn: @escaping (Data) throws -> Data) { self.fn = fn }
        }
        let box = Box(sign)
        let ref = Unmanaged.passRetained(box as AnyObject) // Retain Box as AnyObject

        let tramp: SignerCallback = { ctx, bytes, len, dst, dstCap in
            // ctx is the opaque pointer to our Box instance
            guard let ctx, let bytes, let dst else { return -1 }
            let b = Unmanaged<Box>.fromOpaque(ctx).takeUnretainedValue()
            let msg = Data(bytes: bytes, count: Int(len)) // len is uintptr_t (UInt)

            do {
                let sig = try b.fn(msg)
                // dstCap is uintptr_t (UInt)
                guard UInt(sig.count) <= dstCap else { return -1 } // Compare UInts
                sig.copyBytes(to: dst, count: sig.count)
                return sig.count
            } catch {
                return -1
            }
        }

        var raw: UnsafeMutablePointer<C2paSigner>!
        try certificateChainPEM.withCString { certPtr in
            try withOptionalCString(tsaURL) { tsaPtr in
                raw = try guardNotNull(
                    c2pa_signer_create(
                        ref.toOpaque(), // Pass opaque pointer to Box instance
                        tramp,
                        algorithm.cValue,
                        certPtr,
                        tsaPtr
                    )
                )
            }
        }

        self.init(ptr: raw)
        retainedContext = ref // Store the Unmanaged<AnyObject>
    }

    // --------------------------------------------------------------------
    deinit {
        c2pa_signer_free(ptr)
        retainedContext?.release()
    }

    public func reserveSize() throws -> Int {
        try Int(guardNonNegative(c2pa_signer_reserve_size(ptr)))
    }
}

// MARK: - Stream wrapper ----------------------------------------------------

public struct StreamOptions: OptionSet {
    public let rawValue: UInt8
    public static let read = StreamOptions(rawValue: 1 << 0)
    public static let write = StreamOptions(rawValue: 1 << 1)
    public init(rawValue: UInt8) { self.rawValue = rawValue }
}

public final class Stream {
    public typealias Reader = (_ buffer: UnsafeMutableRawPointer, _ count: Int) -> Int
    public typealias Seeker = (_ offset: Int, _ origin: C2paSeekMode) -> Int
    public typealias Writer = (_ buffer: UnsafeRawPointer, _ count: Int) -> Int
    public typealias Flusher = () -> Int

    private final class Bundle {
        let r: Reader?
        let s: Seeker?
        let w: Writer?
        let f: Flusher?
        // Also store the FileHandle Box if created by Stream(fileURL:)
        // to ensure its lifetime is tied to the Stream object itself.
        var fileHandleBox: AnyObject?

        init(r: Reader?, s: Seeker?, w: Writer?, f: Flusher?, fileHandleBox: AnyObject? = nil) {
            self.r = r; self.s = s; self.w = w; self.f = f
            self.fileHandleBox = fileHandleBox
        }
    }

    private static let cRead: ReadCallback = { ctx, data, len in
        guard let ctx, let data else { return -1 }
        let b = Unmanaged<Bundle>.fromOpaque(ctx).takeUnretainedValue()
        guard let r = b.r else { return -1 }
        return r(data, Int(len))
    }

    private static let cSeek: SeekCallback = { ctx, off, mode in
        guard let ctx else { return -1 }
        let b = Unmanaged<Bundle>.fromOpaque(ctx).takeUnretainedValue()
        guard let s = b.s else { return -1 }
        return s(Int(off), mode)
    }

    private static let cWrite: WriteCallback = { ctx, data, len in
        guard let ctx, let data else { return -1 }
        let b = Unmanaged<Bundle>.fromOpaque(ctx).takeUnretainedValue()
        guard let w = b.w else { return -1 }
        return w(data, Int(len))
    }

    private static let cFlush: FlushCallback = { ctx in
        guard let ctx else { return -1 }
        let b = Unmanaged<Bundle>.fromOpaque(ctx).takeUnretainedValue()
        return b.f?() ?? 0
    }

    private let bundleRef: Unmanaged<Bundle>
    private let contextPtr: UnsafeMutablePointer<StreamContext>
    private let streamPtr: UnsafeMutablePointer<C2paStream>

    // generic constructor for user-provided callbacks
    private init(bundle: Bundle) { // Made fileprivate to guide users to public inits
        bundleRef = .passRetained(bundle)
        contextPtr = asStreamCtx(bundleRef.toOpaque())

        streamPtr = c2pa_create_stream(
            contextPtr,
            bundle.r != nil ? Stream.cRead : nil,
            bundle.s != nil ? Stream.cSeek : nil,
            bundle.w != nil ? Stream.cWrite : nil,
            bundle.f != nil ? Stream.cFlush : nil
        )
    }

    public convenience init(read: Reader? = nil,
                            seek: Seeker? = nil,
                            write: Writer? = nil,
                            flush: Flusher? = nil) throws
    {
        self.init(bundle: Bundle(r: read, s: seek, w: write, f: flush, fileHandleBox: nil))
    }

    // Data → read-only stream
    public convenience init(data: Data) throws {
        var cursor = 0
        let bundle = Bundle(
            r: { buffer, count in
                let remain = data.count - cursor
                guard remain > 0 else { return 0 }
                let n = Swift.min(remain, count)
                _ = data.withUnsafeBytes { // Silence "unused result" warning
                    memcpy(buffer, $0.baseAddress!.advanced(by: cursor), n)
                }
                cursor += n
                return n
            },
            s: { offset, mode in
                switch mode {
                case Start: cursor = max(0, offset)
                case Current: cursor = max(0, cursor + offset)
                case End: cursor = max(0, data.count + offset)
                default: return -1
                }
                return cursor
            },
            w: nil, f: nil, fileHandleBox: nil
        )
        self.init(bundle: bundle)
    }

    deinit {
        c2pa_release_stream(streamPtr)
        bundleRef.release()
    }

    /// raw C pointer (internal)
    var rawPtr: UnsafeMutablePointer<C2paStream> { streamPtr }
}

// MARK: - File-based stream helper ------------------------------------------

public extension Stream {
    /// Fully-featured stream backed by a file on disk.
    ///
    /// The wrapper owns the `FileHandle` and closes it automatically via the Bundle's FileHandleBox.
    convenience init(fileURL url: URL,
                     truncate: Bool = true,
                     createIfNeeded: Bool = true) throws
    {
        if createIfNeeded, !FileManager.default.fileExists(atPath: url.path) {
            FileManager.default.createFile(atPath: url.path, contents: nil)
        }

        let fh = try FileHandle(forUpdating: url)
        if truncate { try fh.truncate(atOffset: 0) }

        // Box to manage FileHandle lifetime, will be stored in the Bundle
        final class FileHandleBox {
            let fh: FileHandle
            init(_ fh: FileHandle) { self.fh = fh }
            deinit { try? fh.close() }
        }
        let fhBox = FileHandleBox(fh)

        let bundle = Bundle(
            r: { buffer, count in
                let data: Data
                if #available(iOS 13.4, macOS 10.15.4, *) {
                    data = (try? fhBox.fh.read(upToCount: count)) ?? Data()
                } else {
                    data = fhBox.fh.readData(ofLength: count)
                }
                data.copyBytes(to: buffer.assumingMemoryBound(to: UInt8.self),
                               count: data.count)
                return data.count
            },
            s: { offset, mode in
                do {
                    let off = Int64(offset)
                    let newPos: UInt64

                    switch mode {
                    case Start:
                        newPos = UInt64(max(0, off))
                    case Current:
                        let currentOffset = Int64(fhBox.fh.offsetInFile)
                        var targetOffset = currentOffset + off
                        if targetOffset < 0 { targetOffset = 0 }
                        newPos = UInt64(targetOffset)
                    case End:
                        let end = try fhBox.fh.seekToEnd()
                        var targetOffset = Int64(end) + off
                        if targetOffset < 0 { targetOffset = 0 }
                        newPos = UInt64(targetOffset)
                    default:
                        return -1
                    }
                    try fhBox.fh.seek(toOffset: newPos)
                    return Int(newPos) // Return Int as per Seeker typealias
                } catch { return -1 }
            },
            w: { buffer, count in
                if #available(iOS 13.4, macOS 10.15.4, *) {
                    try? fhBox.fh.write(contentsOf: Data(bytes: buffer, count: count))
                } else {
                    fhBox.fh.write(Data(bytes: buffer, count: count))
                }
                return count
            },
            f: {
                if #available(iOS 15, macOS 12, *) {
                    try? fhBox.fh.synchronize()
                } else {
                    fhBox.fh.synchronizeFile()
                }
                return 0
            },
            fileHandleBox: fhBox // Store the box in the bundle
        )
        self.init(bundle: bundle)
    }
}

// MARK: - Reader -------------------------------------------------------------

public final class Reader {
    private let ptr: UnsafeMutablePointer<C2paReader>

    public init(format: String, stream: Stream) throws {
        ptr = try guardNotNull(c2pa_reader_from_stream(format, stream.rawPtr))
    }

    public init(format: String, stream: Stream, manifest: Data) throws {
        ptr = try manifest.withUnsafeBytes { buf in
            try guardNotNull(
                c2pa_reader_from_manifest_data_and_stream(
                    format,
                    stream.rawPtr,
                    buf.bindMemory(to: UInt8.self).baseAddress!,
                    UInt(manifest.count)
                )
            )
        }
    }

    deinit { c2pa_reader_free(ptr) }

    public func json() throws -> String {
        try stringFromC(c2pa_reader_json(ptr))
    }

    public func resource(uri: String, to dest: Stream) throws {
        _ = try guardNonNegative(
            c2pa_reader_resource_to_stream(ptr, uri, dest.rawPtr)
        )
    }
}

// MARK: - Builder ------------------------------------------------------------

public final class Builder {
    private let ptr: UnsafeMutablePointer<C2paBuilder>

    public init(manifestJSON: String) throws {
        ptr = try guardNotNull(c2pa_builder_from_json(manifestJSON))
    }

    public init(archiveStream: Stream) throws {
        ptr = try guardNotNull(c2pa_builder_from_archive(archiveStream.rawPtr))
    }

    deinit { c2pa_builder_free(ptr) }

    public func setNoEmbed() { c2pa_builder_set_no_embed(ptr) }

    public func setRemoteURL(_ url: String) throws {
        _ = try guardNonNegative(
            Int64(c2pa_builder_set_remote_url(ptr, url))
        )
    }

    public func addResource(uri: String, stream: Stream) throws {
        _ = try guardNonNegative(
            Int64(c2pa_builder_add_resource(ptr, uri, stream.rawPtr))
        )
    }

    public func addIngredient(json: String, format: String, from stream: Stream) throws {
        _ = try guardNonNegative(
            Int64(c2pa_builder_add_ingredient_from_stream(ptr, json, format, stream.rawPtr))
        )
    }

    public func writeArchive(to dest: Stream) throws {
        _ = try guardNonNegative(
            Int64(c2pa_builder_to_archive(ptr, dest.rawPtr))
        )
    }

    @discardableResult
    public func sign(format: String,
                     source: Stream,
                     destination: Stream,
                     signer: Signer) throws -> Data
    {
        var manifestPtr: UnsafePointer<UInt8>?
        let size = try guardNonNegative(
            c2pa_builder_sign(ptr,
                              format,
                              source.rawPtr,
                              destination.rawPtr,
                              signer.ptr,
                              &manifestPtr)
        )
        guard let mp = manifestPtr else { return Data() }
        let data = Data(bytes: mp, count: Int(size))
        c2pa_manifest_bytes_free(mp)
        return data
    }
}

// MARK: - Whole-file helpers -------------------------------------------------

public enum C2PA {
    public static func readFile(at url: URL,
                                dataDir: URL? = nil) throws -> String
    {
        try stringFromC(
            c2pa_read_file(url.path, dataDir?.path)
        )
    }

    public static func readIngredient(at url: URL,
                                      dataDir: URL? = nil) throws -> String
    {
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

    public static func signFile(source: URL,
                                destination: URL,
                                manifestJSON: String,
                                signerInfo: SignerInfo,
                                dataDir: URL? = nil) throws
    {
        var maybeErr: UnsafeMutablePointer<CChar>?
        withSignerInfo(alg: signerInfo.algorithm.description,
                       cert: signerInfo.certificatePEM,
                       key: signerInfo.privateKeyPEM,
                       tsa: signerInfo.tsaURL)
        { algPtr, certPtr, keyPtr, tsaPtr in
            var sInfo = C2paSignerInfo(alg: algPtr,
                                       sign_cert: certPtr,
                                       private_key: keyPtr,
                                       ta_url: tsaPtr)
            maybeErr = c2pa_sign_file(source.path,
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

// MARK: - Web Service Signing -----------------------------------------------

public typealias WebServiceRequestBuilder = (Data) throws -> URLRequest
public typealias WebServiceResponseParser = (Data, HTTPURLResponse) throws -> Data

public extension Signer {
    convenience init(algorithm: SigningAlgorithm,
                     certificateChainPEM: String,
                     tsaURL: String? = nil,
                     requestBuilder: @escaping WebServiceRequestBuilder,
                     responseParser: @escaping WebServiceResponseParser = { data, _ in data }) throws
    {
        try self.init(algorithm: algorithm,
                      certificateChainPEM: certificateChainPEM,
                      tsaURL: tsaURL)
        { data in
            let request = try requestBuilder(data)

            let semaphore = DispatchSemaphore(value: 0)
            var result: Result<Data, Error>?

            let task = URLSession.shared.dataTask(with: request) { responseData, response, error in
                if let error = error {
                    result = .failure(error)
                } else if let httpResponse = response as? HTTPURLResponse {
                    if (200 ... 299).contains(httpResponse.statusCode), let responseData = responseData {
                        do {
                            let signature = try responseParser(responseData, httpResponse)
                            result = .success(signature)
                        } catch {
                            result = .failure(error)
                        }
                    } else {
                        result = .failure(C2PAError.api("HTTP \(httpResponse.statusCode)"))
                    }
                } else {
                    result = .failure(C2PAError.api("Invalid response"))
                }
                semaphore.signal()
            }

            task.resume()
            semaphore.wait()

            switch result {
            case let .success(signature):
                return signature
            case let .failure(error):
                throw error
            case .none:
                throw C2PAError.api("No result from web service")
            }
        }
    }
}

public enum WebServiceHelpers {
    public static func basicPOSTRequestBuilder(url: URL,
                                               authToken: String? = nil,
                                               contentType: String = "application/octet-stream") -> WebServiceRequestBuilder
    {
        return { data in
            var request = URLRequest(url: url)
            request.httpMethod = "POST"
            request.httpBody = data
            request.setValue(contentType, forHTTPHeaderField: "Content-Type")
            if let authToken = authToken {
                request.setValue(authToken, forHTTPHeaderField: "Authorization")
            }
            return request
        }
    }

    public static func jsonRequestBuilder(url: URL,
                                          authToken: String? = nil,
                                          additionalFields: [String: Any] = [:]) -> WebServiceRequestBuilder
    {
        return { data in
            var json = additionalFields
            json["data"] = data.base64EncodedString()

            let jsonData = try JSONSerialization.data(withJSONObject: json)

            var request = URLRequest(url: url)
            request.httpMethod = "POST"
            request.httpBody = jsonData
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")
            if let authToken = authToken {
                request.setValue(authToken, forHTTPHeaderField: "Authorization")
            }
            return request
        }
    }

    public static func jsonResponseParser(signatureField: String = "signature") -> WebServiceResponseParser {
        return { data, _ in
            guard let json = try JSONSerialization.jsonObject(with: data) as? [String: Any],
                  let signatureBase64 = json[signatureField] as? String,
                  let signature = Data(base64Encoded: signatureBase64)
            else {
                throw C2PAError.api("Invalid JSON response or missing signature field")
            }
            return signature
        }
    }
}

// MARK: - Keychain Signing --------------------------------------------------

public extension Signer {
    convenience init(algorithm: SigningAlgorithm,
                     certificateChainPEM: String,
                     tsaURL: String? = nil,
                     keychainKeyTag: String) throws
    {
        let secAlgorithm: SecKeyAlgorithm
        switch algorithm {
        case .es256:
            secAlgorithm = .ecdsaSignatureMessageX962SHA256
        case .es384:
            secAlgorithm = .ecdsaSignatureMessageX962SHA384
        case .es512:
            secAlgorithm = .ecdsaSignatureMessageX962SHA512
        case .ps256:
            secAlgorithm = .rsaSignatureMessagePSSSHA256
        case .ps384:
            secAlgorithm = .rsaSignatureMessagePSSSHA384
        case .ps512:
            secAlgorithm = .rsaSignatureMessagePSSSHA512
        case .ed25519:
            throw C2PAError.api("Ed25519 not supported by iOS Keychain")
        }

        try self.init(algorithm: algorithm,
                      certificateChainPEM: certificateChainPEM,
                      tsaURL: tsaURL)
        { data in
            let query: [String: Any] = [
                kSecClass as String: kSecClassKey,
                kSecAttrApplicationTag as String: keychainKeyTag,
                kSecAttrKeyType as String: kSecAttrKeyTypeECSECPrimeRandom,
                kSecReturnRef as String: true,
            ]

            var item: CFTypeRef?
            let status = SecItemCopyMatching(query as CFDictionary, &item)

            guard status == errSecSuccess,
                  let privateKey = item as! SecKey?
            else {
                throw C2PAError.api("Failed to find key '\(keychainKeyTag)' in keychain: \(status)")
            }

            guard SecKeyIsAlgorithmSupported(privateKey, .sign, secAlgorithm) else {
                throw C2PAError.api("Key doesn't support algorithm \(algorithm)")
            }

            var error: Unmanaged<CFError>?
            guard let signature = SecKeyCreateSignature(privateKey,
                                                        secAlgorithm,
                                                        data as CFData,
                                                        &error)
            else {
                if let error = error?.takeRetainedValue() {
                    throw C2PAError.api("Signing failed: \(error)")
                }
                throw C2PAError.api("Signing failed")
            }

            return signature as Data
        }
    }
}

// MARK: - Secure Enclave Signing --------------------------------------------

@available(iOS 13.0, macOS 10.15, *)
public struct SecureEnclaveSignerConfig {
    public let keyTag: String
    public let accessControl: SecAccessControlCreateFlags

    public init(keyTag: String,
                accessControl: SecAccessControlCreateFlags = [.privateKeyUsage])
    {
        self.keyTag = keyTag
        self.accessControl = accessControl
    }
}

@available(iOS 13.0, macOS 10.15, *)
public extension Signer {
    convenience init(algorithm: SigningAlgorithm,
                     certificateChainPEM: String,
                     tsaURL: String? = nil,
                     secureEnclaveConfig: SecureEnclaveSignerConfig) throws
    {
        guard algorithm == .es256 else {
            throw C2PAError.api("Secure Enclave only supports ES256 (P-256)")
        }

        try self.init(algorithm: algorithm,
                      certificateChainPEM: certificateChainPEM,
                      tsaURL: tsaURL)
        { data in
            let query: [String: Any] = [
                kSecClass as String: kSecClassKey,
                kSecAttrApplicationTag as String: secureEnclaveConfig.keyTag,
                kSecAttrKeyType as String: kSecAttrKeyTypeECSECPrimeRandom,
                kSecAttrTokenID as String: kSecAttrTokenIDSecureEnclave,
                kSecReturnRef as String: true,
            ]

            var item: CFTypeRef?
            var status = SecItemCopyMatching(query as CFDictionary, &item)

            let privateKey: SecKey
            if status == errSecItemNotFound {
                privateKey = try Signer.createSecureEnclaveKey(config: secureEnclaveConfig)
            } else if status == errSecSuccess,
                      let key = item as! SecKey?
            {
                privateKey = key
            } else {
                throw C2PAError.api("Failed to access Secure Enclave key: \(status)")
            }

            let algorithm = SecKeyAlgorithm.ecdsaSignatureMessageX962SHA256

            guard SecKeyIsAlgorithmSupported(privateKey, .sign, algorithm) else {
                throw C2PAError.api("Secure Enclave key doesn't support required algorithm")
            }

            var error: Unmanaged<CFError>?
            guard let signature = SecKeyCreateSignature(privateKey,
                                                        algorithm,
                                                        data as CFData,
                                                        &error)
            else {
                if let error = error?.takeRetainedValue() {
                    throw C2PAError.api("Secure Enclave signing failed: \(error)")
                }
                throw C2PAError.api("Secure Enclave signing failed")
            }

            return signature as Data
        }
    }

    static func createSecureEnclaveKey(config: SecureEnclaveSignerConfig) throws -> SecKey {
        guard let access = SecAccessControlCreateWithFlags(
            kCFAllocatorDefault,
            kSecAttrAccessibleWhenUnlockedThisDeviceOnly,
            config.accessControl,
            nil
        ) else {
            throw C2PAError.api("Failed to create access control")
        }

        let attributes: [String: Any] = [
            kSecAttrKeyType as String: kSecAttrKeyTypeECSECPrimeRandom,
            kSecAttrKeySizeInBits as String: 256,
            kSecAttrTokenID as String: kSecAttrTokenIDSecureEnclave,
            kSecPrivateKeyAttrs as String: [
                kSecAttrIsPermanent as String: true,
                kSecAttrApplicationTag as String: config.keyTag,
                kSecAttrAccessControl as String: access,
            ],
        ]

        var error: Unmanaged<CFError>?
        guard let privateKey = SecKeyCreateRandomKey(attributes as CFDictionary, &error) else {
            if let error = error?.takeRetainedValue() {
                throw C2PAError.api("Failed to create Secure Enclave key: \(error)")
            }
            throw C2PAError.api("Failed to create Secure Enclave key")
        }

        return privateKey
    }

    static func deleteSecureEnclaveKey(keyTag: String) -> Bool {
        let query: [String: Any] = [
            kSecClass as String: kSecClassKey,
            kSecAttrApplicationTag as String: keyTag,
            kSecAttrKeyType as String: kSecAttrKeyTypeECSECPrimeRandom,
            kSecAttrTokenID as String: kSecAttrTokenIDSecureEnclave,
        ]

        let status = SecItemDelete(query as CFDictionary)
        return status == errSecSuccess || status == errSecItemNotFound
    }
}

// MARK: - Helper Extensions -------------------------------------------------

public extension Signer {
    static func exportPublicKeyPEM(fromKeychainTag keyTag: String) throws -> String {
        let query: [String: Any] = [
            kSecClass as String: kSecClassKey,
            kSecAttrApplicationTag as String: keyTag,
            kSecAttrKeyType as String: kSecAttrKeyTypeECSECPrimeRandom,
            kSecReturnRef as String: true,
        ]

        var item: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &item)

        guard status == errSecSuccess,
              let privateKey = item as! SecKey?
        else {
            throw C2PAError.api("Failed to find key '\(keyTag)' in keychain: \(status)")
        }

        guard let publicKey = SecKeyCopyPublicKey(privateKey) else {
            throw C2PAError.api("Failed to extract public key")
        }

        var error: Unmanaged<CFError>?
        guard let publicKeyData = SecKeyCopyExternalRepresentation(publicKey, &error) as Data? else {
            if let error = error?.takeRetainedValue() {
                throw C2PAError.api("Failed to export public key: \(error)")
            }
            throw C2PAError.api("Failed to export public key")
        }

        let base64 = publicKeyData.base64EncodedString(options: [.lineLength64Characters, .endLineWithLineFeed])
        return "-----BEGIN PUBLIC KEY-----\n\(base64)\n-----END PUBLIC KEY-----"
    }
}
