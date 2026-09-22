//
//  AppTab.swift
//  Grounded
//
//  The MVP's flat 4-tab navigation. Settings ("The Kernel") is NOT a tab — it's
//  a `.sheet` off Home's toolbar gear icon. There's no other full-screen
//  routing: Active/Standby live inline in Queue, and verification results show
//  as a dismissible banner there too.
//

import Foundation

enum AppTab: Int, CaseIterable, Identifiable {
    case home
    case queue
    case insights
    case grid

    var id: Int { rawValue }

    var title: String {
        switch self {
        case .home: return "Home"
        case .queue: return "Queue"
        case .insights: return "Insights"
        case .grid: return "The Grid"
        }
    }

    var icon: String {
        switch self {
        case .home: return "bolt.circle"
        case .queue: return "list.bullet"
        case .insights: return "waveform.path.ecg"
        case .grid: return "square.grid.2x2"
        }
    }
}
