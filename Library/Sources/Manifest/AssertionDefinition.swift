//
//  AssertionDefinition.swift
//  C2PA
//
//  Created by Benjamin Erhart on 06.10.25.
//

import Foundation

/**
 Defines an assertion that consists of a label that can be either a C2PA-defined assertion label or a custom label in reverse domain format.

 https://opensource.contentauthenticity.org/docs/manifest/json-ref/manifest-def#assertiondefinition
 */
open class AssertionDefinition: Codable, Equatable, CustomStringConvertible {

    // MARK: Equatable

    public static func == (lhs: AssertionDefinition, rhs: AssertionDefinition) -> Bool {
        lhs.data == rhs.data && lhs.label == rhs.label && lhs.kind == rhs.kind
    }


    // MARK: AssertionDefinition

    /**
     This allows the assertion to be expressed as CBOR or JSON. The default is CBOR unless you specify that an assertion should be JSON.
     */
    public private(set) var data: String = ""

    /**
     This is typically one of ``StandardAssertionLabel``.
     */
    public let label: String

    /**
     The data type of ``data``. Defaults to JSON for now, because we don't have a CBOR encoder at hand.
     */
    public private(set) var kind: AssertionKind = .json


    public init(label: String) {
        self.label = label
    }

    func getJsonData<T: Decodable>() -> T? {
        guard kind == .json,
              let data = data.data(using: .utf8)
        else {
            return nil
        }

        return try? ManifestDefinition.jsonDecoder.decode(T.self, from: data)
    }

    func setJsonData<T: Encodable>(content: T) {
        kind = .json

        guard let data = try? ManifestDefinition.jsonEncoder.encode(content) else {
            data = ""

            return
        }

        self.data = String(data: data, encoding: .utf8) ?? ""
    }


    // MARK: CustomStringConvertible

    public var description: String {
        "[\(String(describing: type(of: self)))] label=\(label), kind=\(kind), data=\(data)"
    }
}

public enum AssertionKind: String, Codable {
    case cbor = "Cbor"
    case json = "Json"
    case binary = "Binary"
    case uri = "Uri"
}
