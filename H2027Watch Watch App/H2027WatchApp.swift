//
//  H2027WatchApp.swift
//  H2027Watch Watch App
//
//  Created by Shawn Huang on 11/16/26.
//

import SwiftUI

@main
struct H2027Watch_Watch_AppApp: App {
    @State private var store = WatchStore()

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environment(store)
        }
    }
}
