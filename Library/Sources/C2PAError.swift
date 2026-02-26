// This file is licensed to you under the Apache License, Version 2.0
// (http://www.apache.org/licenses/LICENSE-2.0) or the MIT license
// (http://opensource.org/licenses/MIT), at your option.
//
// Unless required by applicable law or agreed to in writing, this software is
// distributed on an "AS IS" BASIS, WITHOUT WARRANTIES OR REPRESENTATIONS OF
// ANY KIND, either express or implied. See the LICENSE-MIT and LICENSE-APACHE
// files for the specific language governing permissions and limitations under
// each license.
//
//  C2PAError.swift
//

import Foundation

/// Errors that can occur during C2PA operations.
///
/// `C2PAError` represents various error conditions that may arise when working
/// with the C2PA library, from low-level C API errors to data validation failures.
///
/// ## Topics
///
/// ### Error Cases
/// - ``api(_:)``
/// - ``nilPointer``
/// - ``utf8``
/// - ``negative(_:)``
public enum C2PAError: Error, LocalizedError {
    /// An error reported by the underlying C2PA library.
    ///
    /// - Parameter message: The error message from the Rust/C layer.
    case api(String)

    /// An unexpected NULL pointer was encountered in the C API.
    case nilPointer

    /// Invalid UTF-8 data was returned from the C2PA library.
    case utf8

    /// A negative status code was returned from the C API.
    ///
    /// - Parameter value: The negative status value.
    case negative(Int64)

    /// A human-readable description of the error.
    public var errorDescription: String? {
        switch self {
        case .api(let m): return "C2PA API error: \(m)"
        case .nilPointer: return "Unexpected NULL pointer"
        case .utf8: return "Invalid UTF-8 from C2PA"
        case .negative(let v): return "C2PA negative status \(v)"
        }
    }
}
