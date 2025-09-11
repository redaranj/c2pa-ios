//
//  Builder.swift
//

import C2PAC
import Foundation

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
    public func sign(
        format: String,
        source: Stream,
        destination: Stream,
        signer: Signer
    ) throws -> Data {
        var manifestPtr: UnsafePointer<UInt8>?
        let size = try guardNonNegative(
            c2pa_builder_sign(
                ptr,
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
