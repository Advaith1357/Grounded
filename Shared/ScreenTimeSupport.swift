//
//  ScreenTimeSupport.swift
//  Shared by the app and the DeviceActivityMonitor extension.
//
//  Whether this build actually uses the Screen Time APIs. It's a compile-time
//  switch: only the Screen Time build (project.screentime.yml) defines
//  SCREEN_TIME, and only that build carries the Family Controls entitlement.
//  Without it every Screen Time call is skipped, so a free-account build never
//  asks for the permission, touches the shield, or schedules background
//  monitoring — app blocking is simply paused.
//

import Foundation

enum ScreenTimeSupport {
    static var isEnabled: Bool {
        #if SCREEN_TIME
        return true
        #else
        return false
        #endif
    }
}
