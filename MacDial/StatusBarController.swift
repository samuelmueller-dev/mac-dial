
import Foundation
import AppKit

enum WheelSensitivity: String {
    case low = "low"
    case medium = "medium"
    case high = "high"
    case extreme = "extreme"
}

enum ScrollDirection: String {
    case standard = "standard"
    case natural = "natural"
}

enum HapticsMode: String {
    case enabled = "enabled"
    case disabled = "disabled"
}

extension NSMenuItem {
    convenience init(title: String) {
        self.init()
        self.title = title
    }
}

class MenuOptionItem<Type>: NSMenuItem {
    init(title: String, option: Type) {
        super.init(title: title, action: nil, keyEquivalent: "")
        self.representedObject = option
    }

    required init(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    var selected : Bool
    {
        get { return self.state == .on }
        set (on) { self.state = on ? .on : .off }
    }

    var option : Type
    {
        get
        {
            return self.representedObject as! Type
        }
    }
}

class StatusBarController: NSObject, NSMenuDelegate
{
    private let statusBar: NSStatusBar
    private let statusItem: NSStatusItem
    private let menu: NSMenu
    private let dial: Dial
    private let modeManager: ModeManager
    private let profileManager: ProfileManager
    private let dispatcher: InputDispatcher

    private let connectionStatusItem = NSMenuItem.init()
    private var modeItems: [MenuOptionItem<Mode>] = []
    private let profilesItem = NSMenuItem.init(title: "Per-App Profiles")
    private let profilesMenu = NSMenu.init()
    private let smoothScrollingItem = NSMenuItem.init(title: "Smooth Scrolling")
    private let tapActionOptions = TapAction.allCases.map {
        MenuOptionItem<TapAction>.init(title: $0.title, option: $0)
    }

    private let wheelSensitivityOptions = [
        MenuOptionItem<WheelSensitivity>.init(title: "Low", option: .low),
        MenuOptionItem<WheelSensitivity>.init(title: "Medium", option: .medium),
        MenuOptionItem<WheelSensitivity>.init(title: "High", option: .high),
        MenuOptionItem<WheelSensitivity>.init(title: "Extreme", option: .extreme)
    ]
    private let scrollDirectionOptions = [
        MenuOptionItem<ScrollDirection>.init(title: "Standard", option: .standard),
        MenuOptionItem<ScrollDirection>.init(title: "Natural", option: .natural)
    ]
    private let hapticsModeOptions = [
        MenuOptionItem<HapticsMode>.init(title: "Disabled", option: .disabled),
        MenuOptionItem<HapticsMode>.init(title: "Enabled", option: .enabled)
    ]

    var wheelSensitivity: WheelSensitivity? {
        get {
            let raw = UserDefaults.standard.string(forKey: "sensitivity") ?? WheelSensitivity.medium.rawValue
            return WheelSensitivity(rawValue: raw)
        }
        set (sensitivity) {
            // Detents per revolution, synthesized from the 3600-step raw stream
            switch sensitivity {
            case .low:
                dispatcher.rawPerDetent = Dial.stepsPerRevolution / 18
            case .medium:
                dispatcher.rawPerDetent = Dial.stepsPerRevolution / 36
            case .high:
                dispatcher.rawPerDetent = Dial.stepsPerRevolution / 72
            case .extreme:
                dispatcher.rawPerDetent = Dial.stepsPerRevolution / 360
            case .none:
                break
            }
            for option in wheelSensitivityOptions {
                option.selected = option.option == sensitivity
            }

            UserDefaults.standard.setValue(sensitivity?.rawValue, forKey: "sensitivity")
        }
    }

    var scrollDirection: ScrollDirection? {
        get {
            let raw = UserDefaults.standard.string(forKey: "direction") ?? ScrollDirection.natural.rawValue
            return ScrollDirection(rawValue: raw)
        }
        set (scrollingDirection) {
            switch scrollingDirection {
            case .standard:
                dial.scrollDirection = 1
            case .natural:
                dial.scrollDirection = -1
            case .none:
                break
            }
            for option in scrollDirectionOptions {
                option.selected = option.option == scrollingDirection
            }

            UserDefaults.standard.setValue(scrollingDirection?.rawValue, forKey: "direction")
        }
    }

    var hapticsMode: HapticsMode? {
        get {
            let raw = UserDefaults.standard.string(forKey: "hapticsmode") ?? HapticsMode.disabled.rawValue
            return HapticsMode(rawValue: raw)
        }
        set (hapticsModeSet) {
            switch hapticsModeSet {
            case .disabled:
                dial.hapticsEnabled = false
            case .enabled:
                dial.hapticsEnabled = true
            case .none:
                break
            }
            for option in hapticsModeOptions {
                option.selected = option.option == hapticsModeSet
            }

            UserDefaults.standard.setValue(String(hapticsModeSet!.rawValue), forKey: "hapticsmode")
        }
    }

    var smoothScrolling: Bool {
        get {
            return UserDefaults.standard.object(forKey: "smoothscroll") as? Bool ?? true
        }
        set (enabled) {
            dispatcher.smoothScrolling = enabled
            smoothScrollingItem.state = enabled ? .on : .off
            UserDefaults.standard.setValue(enabled, forKey: "smoothscroll")
        }
    }

    // Persistence and change notification live in the dispatcher, since the
    // radial menu's tap toggle also changes this setting
    var tapAction: TapAction {
        get {
            return dispatcher.tapAction
        }
        set (action) {
            dispatcher.tapAction = action
        }
    }

    init(_ dial: Dial, modeManager: ModeManager, profileManager: ProfileManager, dispatcher: InputDispatcher) {
        self.dial = dial
        self.modeManager = modeManager
        self.profileManager = profileManager
        self.dispatcher = dispatcher
        self.menu = NSMenu.init()

        statusBar = NSStatusBar.system
        statusItem = statusBar.statusItem(withLength: NSStatusItem.variableLength)

        super.init()

        menu.minimumWidth = 260

        let titleItem = NSMenuItem.init(title: "Mac Dial")
        let attributes: [NSAttributedString.Key: Any] = [
            .font: NSFont.boldSystemFont(ofSize: 0)
        ]
        titleItem.attributedTitle = NSAttributedString(string: titleItem.title, attributes: attributes)
        menu.addItem(titleItem)

        connectionStatusItem.isEnabled = false
        menu.addItem(connectionStatusItem)

        menu.addItem(NSMenuItem.separator())

        for mode in modeManager.modes {
            let item = MenuOptionItem<Mode>.init(title: "\(mode.title) mode", option: mode)
            item.target = self
            item.action = #selector(setMode(sender:))
            item.image = mode.image
            item.image?.size = NSSize(width: 16, height: 16)
            item.selected = mode == modeManager.currentMode
            modeItems.append(item)
            menu.addItem(item)
        }

        menu.addItem(NSMenuItem.separator())

        let wheelSensitivityItem = NSMenuItem.init(title: "Wheel Sensitivity")
        wheelSensitivityItem.submenu = NSMenu.init()
        for option in wheelSensitivityOptions {
            option.target = self
            option.action = #selector(setSensitivity(sender:))
            option.selected = option.option == wheelSensitivity
            wheelSensitivityItem.submenu?.addItem(option)
        }
        menu.addItem(wheelSensitivityItem)
        wheelSensitivity = wheelSensitivity // trigger set which updates dial

        let scrollDirectionItem = NSMenuItem.init(title: "Scroll Direction")
        scrollDirectionItem.submenu = NSMenu.init()
        for option in scrollDirectionOptions {
            option.target = self
            option.action = #selector(setScrollDirection(sender:))
            option.selected = option.option == scrollDirection
            scrollDirectionItem.submenu?.addItem(option)
        }
        menu.addItem(scrollDirectionItem)
        scrollDirection = scrollDirection // trigger set which updates dial

        let hapticsItem = NSMenuItem.init(title: "Haptics")
        hapticsItem.submenu = NSMenu.init()
        for option in hapticsModeOptions {
            option.target = self
            option.action = #selector(setHaptics(sender:))
            option.selected = option.option == hapticsMode
            hapticsItem.submenu?.addItem(option)
        }
        menu.addItem(hapticsItem)
        hapticsMode = hapticsMode // trigger set which updates dial

        smoothScrollingItem.target = self
        smoothScrollingItem.action = #selector(toggleSmoothScrolling(sender:))
        menu.addItem(smoothScrollingItem)
        smoothScrolling = smoothScrolling // trigger set which updates dispatcher

        let tapActionItem = NSMenuItem.init(title: "Tap Gesture")
        tapActionItem.submenu = NSMenu.init()
        for option in tapActionOptions {
            option.target = self
            option.action = #selector(setTapAction(sender:))
            tapActionItem.submenu?.addItem(option)
        }
        menu.addItem(tapActionItem)
        dispatcher.onTapActionChanged = { [weak self] action in
            guard let self = self else { return }
            for option in self.tapActionOptions {
                option.selected = option.option == action
            }
        }
        tapAction = tapAction // trigger change notification to set checkmarks

        menu.addItem(NSMenuItem.separator())

        profilesMenu.delegate = self
        profilesItem.submenu = profilesMenu
        menu.addItem(profilesItem)

        menu.addItem(NSMenuItem.separator())

        let quitItem = NSMenuItem.init(title: "Quit")
        quitItem.target = self
        quitItem.action = #selector(quitApp(sender:))
        menu.addItem(quitItem)

        statusItem.menu = menu

        updateIcon()

        Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true) { [weak self]_ in
            self?.updateConnectionStatus()
        }

        modeManager.onModeChanged.append { [weak self] mode in
            guard let self = self else { return }
            for item in self.modeItems {
                item.selected = item.option == mode
            }
            self.updateIcon()
        }
    }

    // Rebuild the per-app profiles submenu each time it is opened
    func menuWillOpen(_ menu: NSMenu) {
        guard menu == profilesMenu else { return }

        menu.removeAllItems()

        let pinItem: NSMenuItem
        if let app = profileManager.lastActiveApp {
            pinItem = NSMenuItem.init(title: "Pin '\(modeManager.currentMode.title)' to \(app.name)")
            pinItem.target = self
            pinItem.action = #selector(pinCurrentMode(sender:))
        } else {
            pinItem = NSMenuItem.init(title: "Pin mode to frontmost app")
        }
        menu.addItem(pinItem)

        if !profileManager.profiles.isEmpty {
            menu.addItem(NSMenuItem.separator())

            let sorted = profileManager.profiles.sorted {
                profileManager.name(for: $0.key) < profileManager.name(for: $1.key)
            }
            for (bundleId, mode) in sorted {
                let item = NSMenuItem.init(title: "\(profileManager.name(for: bundleId)) — \(mode.title)")
                item.target = self
                item.action = #selector(removeProfile(sender:))
                item.representedObject = bundleId
                item.toolTip = "Click to remove this profile"
                menu.addItem(item)
            }
        }
    }

    private func updateConnectionStatus() {
        if dial.device.isConnected {
            let serialNumber = dial.device.serialNumber
            connectionStatusItem.title = "Surface Dial '\(serialNumber)' connected"
        }
        else {
            connectionStatusItem.title = "No Surface Dial connected"
        }
    }

    private func updateIcon() {
        if let button = statusItem.button {
            if let image = modeManager.currentMode.image {
                button.image = image
                button.image?.size = NSSize(width: 18, height: 18)
                button.imagePosition = .imageLeft
                button.title = ""
            } else {
                // Never leave the status item invisible
                button.image = nil
                button.title = "Dial"
            }
        }
    }

    @objc func setMode(sender: AnyObject) {
        let item = sender as! MenuOptionItem<Mode>
        modeManager.currentMode = item.option
    }

    @objc func pinCurrentMode(sender: AnyObject) {
        profileManager.pinCurrentMode()
    }

    @objc func removeProfile(sender: AnyObject) {
        let item = sender as! NSMenuItem
        if let bundleId = item.representedObject as? String {
            profileManager.removeProfile(bundleId: bundleId)
        }
    }

    @objc func setSensitivity(sender: AnyObject) {
        let item = sender as! NSMenuItem
        wheelSensitivity = (item.representedObject as! WheelSensitivity)
    }

    @objc func setScrollDirection(sender: AnyObject) {
        let item = sender as! NSMenuItem
        scrollDirection = (item.representedObject as! ScrollDirection)
    }

    @objc func setHaptics(sender: AnyObject) {
        let item = sender as! NSMenuItem
        hapticsMode = (item.representedObject as! HapticsMode)
    }

    @objc func toggleSmoothScrolling(sender: AnyObject) {
        smoothScrolling = !smoothScrolling
    }

    @objc func setTapAction(sender: AnyObject) {
        let item = sender as! MenuOptionItem<TapAction>
        tapAction = item.option
    }

    @objc func quitApp(sender: AnyObject) {
        NSApplication.shared.terminate(self)
    }

}
