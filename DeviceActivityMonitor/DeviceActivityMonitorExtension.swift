//
//  DeviceActivityMonitorExtension.swift
//  DeviceActivityMonitor
//
//  Re-grounds the device when nothing in the app is running to do it:
//    breakEnd        a Discharge break has run out
//    circuitBreaker  the nightly lockout window has opened
//  Both just re-apply the shield from the selection the app saved to the App
//  Group. The app reconciles its own state (and refunds any unused Voltage)
//  the next time it launches.
//

import DeviceActivity

final class DeviceActivityMonitorExtension: DeviceActivityMonitor {

    override func intervalDidStart(for activity: DeviceActivityName) {
        super.intervalDidStart(for: activity)
        // .breakEnd also "starts" immediately when scheduled — ignore that.
        if activity == .circuitBreaker {
            ShieldApplier.groundFromSavedSelection()
        }
    }

    override func intervalDidEnd(for activity: DeviceActivityName) {
        super.intervalDidEnd(for: activity)
        if activity == .breakEnd {
            ShieldApplier.groundFromSavedSelection()
        }
    }
}
