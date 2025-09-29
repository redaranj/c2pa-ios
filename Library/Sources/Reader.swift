//
//  Reader.swift
//

import C2PAC
import Foundation

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
