//
//  ActionsAssertion.swift
//  C2PA
//
//  Created by Benjamin Erhart on 08.10.25.
//

import Foundation

/**
 https://opensource.contentauthenticity.org/docs/manifest/writing/assertions-actions#actions
 */
open class ActionsAssertion: AssertionDefinition {

    open var actions: [Action] {
        get {
            return self.getJsonData() ?? []
        }
        set {
            setJsonData(content: newValue)
        }
    }

    public init(actions: [Action] = []) {
        super.init(label: StandardAssertionLabel.actions.rawValue)

        self.actions = actions
    }
    
    public required init(from decoder: any Decoder) throws {
        try super.init(from: decoder)
    }
}
