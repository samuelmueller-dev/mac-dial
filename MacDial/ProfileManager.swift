
import Foundation
import AppKit

// Automatically switches mode when the frontmost application changes,
// based on user-pinned app → mode assignments.
class ProfileManager {

    struct AppInfo {
        let bundleId: String
        let name: String
    }

    private static let profilesKey = "appProfiles"
    private static let namesKey = "appProfileNames"

    private let modeManager: ModeManager

    // The frontmost app, excluding ourselves — the app a pinned mode would apply to
    private(set) var lastActiveApp: AppInfo?

    private(set) var profiles: [String: Mode] = [:]
    private var appNames: [String: String] = [:]

    init(modeManager: ModeManager) {
        self.modeManager = modeManager

        let defaults = UserDefaults.standard
        if let raw = defaults.dictionary(forKey: ProfileManager.profilesKey) as? [String: String] {
            profiles = raw.compactMapValues { Mode(rawValue: $0) }
        }
        appNames = defaults.dictionary(forKey: ProfileManager.namesKey) as? [String: String] ?? [:]

        if let frontmost = NSWorkspace.shared.frontmostApplication {
            noteActivated(frontmost)
        }

        NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.didActivateApplicationNotification,
            object: nil,
            queue: .main
        ) { [weak self] notification in
            guard let app = notification.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication else {
                return
            }
            self?.noteActivated(app)
        }
    }

    private func noteActivated(_ app: NSRunningApplication) {
        guard let bundleId = app.bundleIdentifier,
              bundleId != Bundle.main.bundleIdentifier else {
            return
        }

        lastActiveApp = AppInfo(bundleId: bundleId, name: app.localizedName ?? bundleId)

        if let mode = profiles[bundleId], mode != modeManager.currentMode {
            modeManager.currentMode = mode
        }
    }

    func name(for bundleId: String) -> String {
        return appNames[bundleId] ?? bundleId
    }

    func pinCurrentMode() {
        guard let app = lastActiveApp else { return }
        profiles[app.bundleId] = modeManager.currentMode
        appNames[app.bundleId] = app.name
        save()
    }

    func removeProfile(bundleId: String) {
        profiles.removeValue(forKey: bundleId)
        appNames.removeValue(forKey: bundleId)
        save()
    }

    private func save() {
        let defaults = UserDefaults.standard
        defaults.setValue(profiles.mapValues { $0.rawValue }, forKey: ProfileManager.profilesKey)
        defaults.setValue(appNames, forKey: ProfileManager.namesKey)
    }
}
