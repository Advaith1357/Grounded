//
//  GroundedApp.swift
//  Grounded
//
//  Entry point. Creates the single view model (with the real GeminiService,
//  the real TaskStore, and the MockShieldManager) and hands it to RootTabView,
//  the 4-tab shell.
//
//  To plug in real screen-time enforcement later: build a
//  `ScreenTimeShieldManager: ShieldManager` and pass it here instead of
//  `MockShieldManager()`. Nothing else changes.
//

import SwiftUI

@main
struct GroundedApp: App {
    @StateObject private var viewModel = GroundedViewModel()

    var body: some Scene {
        WindowGroup {
            RootTabView(viewModel: viewModel)
        }
    }
}
