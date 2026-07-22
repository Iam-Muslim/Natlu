//
//  ReciteQuran_iOS_NativeApp.swift
//  ReciteQuran-iOS-Native
//
//  Created by Tarek Mansour on 13/7/26.
//

import SwiftUI

@main
struct ReciteQuran_iOS_NativeApp: App {
    init() { try? FontRegistrar.register() }
    var body: some Scene {
        WindowGroup {
            ContentView()
        }
    }
}
