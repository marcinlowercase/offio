//
//  offioApp.swift
//  offio
//
//  Created by Theo on 12/16/25.
//

import SwiftUI

@main
struct offioApp: App {

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environment(AudioManager.shared)
        }
    }
}
