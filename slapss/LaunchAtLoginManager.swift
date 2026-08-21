//
//  LaunchAtLoginManager.swift
//  slapss
//
//  Wraps SMAppService for "open at login" behavior. macOS 13+ unified API —
//  no separate helper bundle required.
//
//  Note: in development (unsigned/dev-signed) builds, the OS may show a
//  "Slapss was added to your Login Items" dialog the first time. In App Store
//  builds this is silent.
//

import Foundation
import ServiceManagement

@MainActor
enum LaunchAtLoginManager {
    static var isEnabled: Bool {
        SMAppService.mainApp.status == .enabled
    }

    /// Returns true on success. Failures are surfaced via the returned bool —
    /// caller can show a non-fatal alert if it returns false.
    @discardableResult
    static func setEnabled(_ enabled: Bool) -> Bool {
        do {
            if enabled {
                if SMAppService.mainApp.status != .enabled {
                    try SMAppService.mainApp.register()
                }
            } else {
                if SMAppService.mainApp.status == .enabled {
                    try SMAppService.mainApp.unregister()
                }
            }
            return true
        } catch {
            return false
        }
    }
}
