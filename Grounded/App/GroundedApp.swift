//
//  GroundedApp.swift
//  Grounded
//
//  Entry point. Creates the single view model (with the real GeminiService,
//  the real TaskStore and the MockAppBlocker) and hands it to ContentView.
//
//  To plug in real blocking later: build a `ScreenTimeBlocker: AppBlocker` and
//  pass it here instead of `MockAppBlocker()`. Nothing else changes.
//

import SwiftUI

@main
struct GroundedApp: App {
    @StateObject private var viewModel = GroundedViewModel()

    var body: some Scene {
        WindowGroup {
            ContentView(viewModel: viewModel)
        }
    }
}
