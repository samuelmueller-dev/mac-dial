
import Foundation
import AppKit
import Carbon.HIToolbox

enum TapAction: String, CaseIterable {
    case spotlight = "spotlight"
    case radialMenu = "radialmenu"
    case focusWindow = "focuswindow"
    case missionControl = "missioncontrol"
    case none = "none"

    var title: String {
        switch self {
        case .spotlight: return "Spotlight search"
        case .radialMenu: return "Show radial menu"
        case .focusWindow: return "Focus window under cursor"
        case .missionControl: return "Mission Control"
        case .none: return "Do nothing"
        }
    }
}

// Rotation intent gate: at 3600 steps/rev, picking the dial up or tapping it
// leaks a little rotation. Motion starting from rest is buffered until it
// accumulates enough net displacement to be clearly intentional (taps
// oscillate around zero net), then flushed in full so nothing is lost.
private class RotationGate {

    private enum GateState {
        case quiet
        case gating
        case streaming
    }

    private var state = GateState.quiet
    private var buffered = 0
    private var gateStart: TimeInterval = 0
    private var lastEvent: TimeInterval = 0
    private var discardTimer: Timer?

    // Net raw steps that prove intent (tap bursts stay below ~30)
    private let intentThreshold = 40
    // Very slow deliberate turns flush after this long regardless
    private let slowTurnWindow: TimeInterval = 0.6
    // Silence after which streaming motion re-arms the gate
    private let quietGap: TimeInterval = 0.35
    // Silence after which a sub-threshold buffer is discarded as jitter
    private let discardGap: TimeInterval = 0.25

    // Returns the raw steps to route now; 0 while motion is being withheld
    func feed(_ raw: Int) -> Int {
        let now = Date().timeIntervalSince1970
        defer { lastEvent = now }

        switch state {
        case .streaming:
            if now - lastEvent > quietGap {
                state = .gating
                gateStart = now
                buffered = raw
                armDiscardTimer()
                return checkIntent(now)
            }
            return raw
        case .quiet:
            state = .gating
            gateStart = now
            buffered = raw
            armDiscardTimer()
            return checkIntent(now)
        case .gating:
            buffered += raw
            armDiscardTimer()
            return checkIntent(now)
        }
    }

    private func checkIntent(_ now: TimeInterval) -> Int {
        if abs(buffered) >= intentThreshold || now - gateStart >= slowTurnWindow {
            state = .streaming
            discardTimer?.invalidate()
            let flush = buffered
            buffered = 0
            return flush
        }
        return 0
    }

    private func armDiscardTimer() {
        discardTimer?.invalidate()
        discardTimer = Timer.scheduledTimer(withTimeInterval: discardGap, repeats: false) { [weak self] _ in
            self?.state = .quiet
            self?.buffered = 0
        }
    }
}

// Sits between the Dial and the active Controller. The dial runs at 3600
// raw steps/rev; this class synthesizes detents from the raw stream, feeds
// jitter to the tap detector, and dispatches gestures: rotate, click,
// double/triple click, press-drag, long-press (radial menu) and tap.
class InputDispatcher {

    private enum State {
        case idle
        case pressed(downForwarded: Bool)
        case longPressed(rotated: Bool)
        case menuOpen
        case consumingPress
    }

    private let dial: Dial
    private let modeManager: ModeManager
    private let radialMenu: RadialMenuController
    private var modifierBindings: ModifierBindings!
    private let tapDetector = TapDetector()
    private let rotationGate = RotationGate()

    private var state = State.idle
    private var longPressTimer: Timer?
    private var menuTimeoutTimer: Timer?
    private var pressTime: TimeInterval = 0
    private var pressRotationAccum = 0
    private var detentAccumulator = 0

    private let longPressDelay: TimeInterval = 0.5
    private let menuTimeout: TimeInterval = 4.0
    // Raw steps of rotation-while-pressed before it becomes a drag. Must
    // exceed the tap detector's net-drift limit so a tap can't also drag.
    private let dragThreshold = 40

    private var clickCount = 0
    private var lastClickTime: TimeInterval = 0

    private var escTap: CFMachPort?
    private var escTapRunLoopSource: CFRunLoopSource?

    // Set from the status bar menu
    var rawPerDetent = 100
    var smoothScrolling = true

    var onTapActionChanged: ((TapAction) -> Void)?

    var tapAction: TapAction {
        get {
            let raw = UserDefaults.standard.string(forKey: "tapaction") ?? TapAction.none.rawValue
            return TapAction(rawValue: raw) ?? .none
        }
        set (action) {
            UserDefaults.standard.setValue(action.rawValue, forKey: "tapaction")
            onTapActionChanged?(action)
        }
    }

    // Flip taps between disabled and the last enabled action (radial menu toggle)
    func toggleTapEnabled() {
        if tapAction == .none {
            let raw = UserDefaults.standard.string(forKey: "tapaction.previous") ?? TapAction.spotlight.rawValue
            tapAction = TapAction(rawValue: raw) ?? .spotlight
        } else {
            UserDefaults.standard.setValue(tapAction.rawValue, forKey: "tapaction.previous")
            tapAction = .none
        }
    }

    init(dial: Dial, modeManager: ModeManager, radialMenu: RadialMenuController) {
        self.dial = dial
        self.modeManager = modeManager
        self.radialMenu = radialMenu
        self.modifierBindings = ModifierBindings { [weak dial] in
            dial?.device.impact()
        }

        tapDetector.onTap = { [weak self] in
            self?.performTap()
        }

        dial.onButtonStateChanged = { [weak self] buttonState in
            DispatchQueue.main.async {
                switch buttonState {
                case .pressed:
                    self?.handlePress()
                case .released:
                    self?.handleRelease()
                }
            }
        }

        dial.onRotation = { [weak self] rawSteps, scrollDirection in
            DispatchQueue.main.async {
                self?.handleRotation(rawSteps, scrollDirection)
            }
        }
    }

    private func handlePress() {
        switch state {
        case .idle:
            state = .pressed(downForwarded: false)
            pressTime = Date().timeIntervalSince1970
            pressRotationAccum = 0
            longPressTimer = Timer.scheduledTimer(withTimeInterval: longPressDelay, repeats: false) { [weak self] _ in
                self?.handleLongPress()
            }
        case .menuOpen:
            selectHighlightedItem()
            state = .consumingPress
        default:
            break
        }
    }

    private func handleRelease() {
        switch state {
        case .pressed(let downForwarded):
            cancelLongPressTimer()
            if downForwarded {
                // Was a press-drag; onDown already fired when rotation began
                modeManager.currentController.onUp()
                clickCount = 0
            } else {
                let duration = Date().timeIntervalSince1970 - pressTime
                // Phantom-click suppression can eat very fast real clicks, so
                // it only runs while the tap gesture is actually in use
                if tapAction != .none && tapDetector.shouldSuppressClick(pressDuration: duration) {
                    // Phantom click from a physical tap; TapDetector fires onTap
                } else {
                    registerClick()
                }
            }
            state = .idle
        case .longPressed(let rotated):
            if rotated {
                // Quick gesture: hold, twist, release
                selectHighlightedItem()
                state = .idle
            } else {
                state = .menuOpen
                restartMenuTimeout()
            }
        case .consumingPress:
            state = .idle
        default:
            break
        }
    }

    private func handleRotation(_ rawSteps: Int, _ scrollDirection: Int) {
        switch state {
        case .idle:
            tapDetector.feed(rawSteps: rawSteps)

            let routed = rotationGate.feed(rawSteps)
            if routed == 0 {
                return
            }

            if modifierBindings.isComboHeld {
                let detents = accumulateDetents(routed)
                if detents != 0 {
                    _ = modifierBindings.handle(steps: detents)
                }
                return
            }
            modifierBindings.noteInactive()

            if smoothScrolling && modeManager.currentMode == .scrolling {
                modeManager.currentController.onRotateRaw(routed, scrollDirection)
                return
            }
            emitDetents(routed, scrollDirection)
        case .pressed(let downForwarded):
            if downForwarded {
                routePressedRotation(rawSteps, scrollDirection)
            } else {
                tapDetector.feed(rawSteps: rawSteps)
                pressRotationAccum += rawSteps
                // Enough rotation while pressed becomes a press-drag (jitter
                // from clicks and taps stays below the threshold)
                if abs(pressRotationAccum) >= dragThreshold {
                    cancelLongPressTimer()
                    modeManager.currentController.onDown()
                    state = .pressed(downForwarded: true)
                    routePressedRotation(pressRotationAccum, scrollDirection)
                    pressRotationAccum = 0
                }
            }
        case .longPressed:
            if radialMenu.rotate(rawSteps) {
                dial.device.impact()
                state = .longPressed(rotated: true)
            }
        case .menuOpen:
            if radialMenu.rotate(rawSteps) {
                dial.device.impact()
            }
            restartMenuTimeout()
        case .consumingPress:
            break
        }
    }

    private func routePressedRotation(_ rawSteps: Int, _ scrollDirection: Int) {
        if smoothScrolling && modeManager.currentMode == .scrolling {
            modeManager.currentController.onRotateRaw(rawSteps, scrollDirection)
        } else {
            emitDetents(rawSteps, scrollDirection)
        }
    }

    private func accumulateDetents(_ rawSteps: Int) -> Int {
        detentAccumulator += rawSteps
        let detents = detentAccumulator / rawPerDetent
        detentAccumulator -= detents * rawPerDetent
        return detents
    }

    private func emitDetents(_ rawSteps: Int, _ scrollDirection: Int) {
        let detents = accumulateDetents(rawSteps)
        guard detents != 0 else { return }

        let rotation: Dial.Rotation = detents > 0 ? .Clockwise(detents) : .CounterClockwise(-detents)
        modeManager.currentController.onRotate(rotation, scrollDirection)
        if dial.hapticsEnabled {
            dial.device.impact()
        }
    }

    private func menuItems() -> [RadialMenuItem] {
        var items = modeManager.modes.map {
            RadialMenuItem(title: $0.title, symbolName: $0.symbolName, action: .mode($0))
        }
        let tapEnabled = tapAction != .none
        items.append(RadialMenuItem(title: tapEnabled ? "Tap: On" : "Tap: Off",
                                    symbolName: tapEnabled ? "hand.tap" : "hand.raised.slash",
                                    action: .toggleTap))
        return items
    }

    private func presentMenu() {
        let items = menuItems()
        let highlighted = items.firstIndex {
            if case .mode(let mode) = $0.action {
                return mode == modeManager.currentMode
            }
            return false
        } ?? 0
        radialMenu.show(items: items, highlightedIndex: highlighted)
        enableEscMonitor()
    }

    private func closeMenu() {
        radialMenu.hide()
        cancelMenuTimeout()
        disableEscMonitor()
    }

    private func handleLongPress() {
        guard case .pressed(downForwarded: false) = state else { return }
        state = .longPressed(rotated: false)
        presentMenu()
        dial.device.impact(repeatCount: 2)
    }

    private func performTap() {
        guard case .idle = state else { return }
        switch tapAction {
        case .spotlight:
            postKeystroke(kVK_Space, flags: .maskCommand)
            dial.device.impact()
        case .radialMenu:
            presentMenu()
            dial.device.impact()
            state = .menuOpen
            restartMenuTimeout()
        case .focusWindow:
            postLeftClickAtCursor()
            dial.device.impact()
        case .missionControl:
            postKeystroke(kVK_UpArrow, flags: .maskControl)
            dial.device.impact()
        case .none:
            break
        }
    }

    // Counts rapid clicks. Single/double clicks fire the active mode's action
    // immediately (no added latency); a triple click instead injects a real
    // mouse click at the cursor to give the window under it scroll focus.
    private func registerClick() {
        let now = Date().timeIntervalSince1970
        if now - lastClickTime < NSEvent.doubleClickInterval {
            clickCount += 1
        } else {
            clickCount = 1
        }
        lastClickTime = now

        if clickCount >= 3 {
            clickCount = 0
            postLeftClickAtCursor()
            dial.device.impact()
        } else {
            modeManager.currentController.onDown()
            modeManager.currentController.onUp()
        }
    }

    private func selectHighlightedItem() {
        if let item = radialMenu.highlightedItem {
            switch item.action {
            case .mode(let mode):
                if mode != modeManager.currentMode {
                    modeManager.currentMode = mode
                }
            case .toggleTap:
                toggleTapEnabled()
            }
        }
        closeMenu()
        dial.device.impact()
    }

    private func cancelLongPressTimer() {
        longPressTimer?.invalidate()
        longPressTimer = nil
    }

    private func restartMenuTimeout() {
        cancelMenuTimeout()
        menuTimeoutTimer = Timer.scheduledTimer(withTimeInterval: menuTimeout, repeats: false) { [weak self] _ in
            guard let self = self, case .menuOpen = self.state else { return }
            self.closeMenu()
            self.state = .idle
        }
    }

    private func cancelMenuTimeout() {
        menuTimeoutTimer?.invalidate()
        menuTimeoutTimer = nil
    }

    // MARK: Escape key dismissal

    // While the radial menu is visible, a session event tap intercepts (and
    // swallows) the Esc key so it dismisses the menu instead of reaching the
    // frontmost app. The tap only exists while the menu is on screen.
    private func enableEscMonitor() {
        guard escTap == nil else { return }

        let callback: CGEventTapCallBack = { _, type, event, refcon in
            guard let refcon = refcon else {
                return Unmanaged.passUnretained(event)
            }
            let dispatcher = Unmanaged<InputDispatcher>.fromOpaque(refcon).takeUnretainedValue()

            if type == .tapDisabledByTimeout || type == .tapDisabledByUserInput {
                DispatchQueue.main.async { dispatcher.reenableEscTapIfNeeded() }
                return Unmanaged.passUnretained(event)
            }
            if type == .keyDown && event.getIntegerValueField(.keyboardEventKeycode) == 53 { // Esc
                DispatchQueue.main.async { dispatcher.handleEscape() }
                return nil
            }
            return Unmanaged.passUnretained(event)
        }

        escTap = CGEvent.tapCreate(tap: .cgSessionEventTap,
                                   place: .headInsertEventTap,
                                   options: .defaultTap,
                                   eventsOfInterest: CGEventMask(1 << CGEventType.keyDown.rawValue),
                                   callback: callback,
                                   userInfo: Unmanaged.passUnretained(self).toOpaque())
        if let tap = escTap {
            escTapRunLoopSource = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, tap, 0)
            CFRunLoopAddSource(CFRunLoopGetMain(), escTapRunLoopSource, .commonModes)
            CGEvent.tapEnable(tap: tap, enable: true)
        }
    }

    private func disableEscMonitor() {
        if let source = escTapRunLoopSource {
            CFRunLoopRemoveSource(CFRunLoopGetMain(), source, .commonModes)
        }
        if let tap = escTap {
            CGEvent.tapEnable(tap: tap, enable: false)
            CFMachPortInvalidate(tap)
        }
        escTap = nil
        escTapRunLoopSource = nil
    }

    private func reenableEscTapIfNeeded() {
        if let tap = escTap {
            CGEvent.tapEnable(tap: tap, enable: true)
        }
    }

    private func handleEscape() {
        switch state {
        case .menuOpen, .longPressed:
            closeMenu()
            state = .idle
        default:
            break
        }
    }
}
