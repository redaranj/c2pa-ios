//
//  Action.swift
//

import Foundation

/// Represents an action that can be added to a C2PA manifest.
///
/// Actions describe operations performed on the content, such as editing,
/// cropping, or applying filters. Each action has a type identifier and
/// optional parameters.
///
/// ## Topics
///
/// ### Standard C2PA Actions
/// - ``created``
/// - ``opened``
/// - ``edited``
/// - ``cropped``
/// - ``filtered``
/// - ``orientationChanged``
/// - ``resized``
/// - ``placed``
/// - ``converted``
/// - ``colorAdjusted``
/// - ``drawn``
/// - ``published``
/// - ``transcoded``
/// - ``unknown``
/// - ``redacted``
/// - ``removed``
///
/// ### Custom Actions
/// - ``custom(_:parameters:)``
///
/// - SeeAlso: ``Builder/addAction(_:)``
public struct Action: Encodable, Sendable {
    /// The action identifier string.
    public let action: String

    /// Optional parameters associated with the action.
    public let parameters: [String: String]?

    /// Creates a custom action with the specified identifier and parameters.
    ///
    /// - Parameters:
    ///   - action: The action identifier (e.g., "c2pa.edited" or a custom URI).
    ///   - parameters: Optional dictionary of parameters for the action.
    public init(action: String, parameters: [String: String]? = nil) {
        self.action = action
        self.parameters = parameters
    }

    // MARK: - Standard C2PA Actions

    /// Content was created.
    public static let created = Action(action: "c2pa.created")

    /// Content was opened from a source.
    public static let opened = Action(action: "c2pa.opened")

    /// Content was edited.
    public static let edited = Action(action: "c2pa.edited")

    /// Content was cropped.
    public static let cropped = Action(action: "c2pa.cropped")

    /// A filter was applied to the content.
    public static let filtered = Action(action: "c2pa.filtered")

    /// The orientation of the content was changed.
    public static let orientationChanged = Action(action: "c2pa.orientation_changed")

    /// Content was resized.
    public static let resized = Action(action: "c2pa.resized")

    /// Content was placed or composited.
    public static let placed = Action(action: "c2pa.placed")

    /// Content format was converted.
    public static let converted = Action(action: "c2pa.converted")

    /// Color adjustments were made.
    public static let colorAdjusted = Action(action: "c2pa.color_adjusted")

    /// Content was drawn or painted.
    public static let drawn = Action(action: "c2pa.drawing")

    /// Content was published.
    public static let published = Action(action: "c2pa.published")

    /// Content was transcoded.
    public static let transcoded = Action(action: "c2pa.transcoded")

    /// An unknown action was performed.
    public static let unknown = Action(action: "c2pa.unknown")

    /// Content was redacted.
    public static let redacted = Action(action: "c2pa.redacted")

    /// Content was removed.
    public static let removed = Action(action: "c2pa.removed")

    // MARK: - Factory Methods

    /// Creates a custom action with the specified identifier.
    ///
    /// Use this for vendor-specific actions that are not part of the standard
    /// C2PA action set.
    ///
    /// - Parameters:
    ///   - identifier: The action identifier URI (e.g., "com.example.myaction").
    ///   - parameters: Optional dictionary of parameters.
    /// - Returns: A new action with the specified identifier.
    ///
    /// ## Example
    ///
    /// ```swift
    /// let action = Action.custom(
    ///     "com.example.ai-enhancement",
    ///     parameters: ["model": "v2.0", "strength": "0.8"]
    /// )
    /// try builder.addAction(action)
    /// ```
    public static func custom(_ identifier: String, parameters: [String: String]? = nil) -> Action {
        Action(action: identifier, parameters: parameters)
    }

    /// Creates an edited action with the specified parameters.
    ///
    /// - Parameter parameters: Dictionary of parameters describing the edit.
    /// - Returns: An edited action with the given parameters.
    public static func edited(parameters: [String: String]) -> Action {
        Action(action: "c2pa.edited", parameters: parameters)
    }

    /// Creates a cropped action with the specified parameters.
    ///
    /// - Parameter parameters: Dictionary of parameters describing the crop.
    /// - Returns: A cropped action with the given parameters.
    public static func cropped(parameters: [String: String]) -> Action {
        Action(action: "c2pa.cropped", parameters: parameters)
    }

    /// Creates a filtered action with the specified parameters.
    ///
    /// - Parameter parameters: Dictionary of parameters describing the filter.
    /// - Returns: A filtered action with the given parameters.
    public static func filtered(parameters: [String: String]) -> Action {
        Action(action: "c2pa.filtered", parameters: parameters)
    }

    /// Creates a resized action with the specified parameters.
    ///
    /// - Parameter parameters: Dictionary of parameters describing the resize.
    /// - Returns: A resized action with the given parameters.
    public static func resized(parameters: [String: String]) -> Action {
        Action(action: "c2pa.resized", parameters: parameters)
    }

    // MARK: - Internal

    internal func toJSON() throws -> String {
        let encoder = JSONEncoder()
        let data = try encoder.encode(self)
        guard let json = String(data: data, encoding: .utf8) else {
            throw C2PAError.api("Failed to encode action to JSON")
        }
        return json
    }
}
