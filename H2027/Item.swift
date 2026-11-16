//
//  Item.swift
//  H2027
//
//  Created by Shawn Huang on 11/16/26.
//

import Foundation
import SwiftData

@Model
final class Item {
    var timestamp: Date
    
    init(timestamp: Date) {
        self.timestamp = timestamp
    }
}
