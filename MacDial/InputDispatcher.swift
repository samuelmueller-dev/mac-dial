
import Foundation
import AppKit

// Sits between the Dial and the active Controller. Short presses and rotations
// are forwarded to the current mode's controller. Holding the dial down summons
// the radial mode menu: rotate to highlight a mode, press (or release, if the
// dial was rotated while still held) to select it.
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

    private var state = State.idle
    private var longPressTimer: Timer?
    private var menuTimeoutTimer: Timer?

    private let longPressDelay: TimeInterval = 0.5
    private let menuTimeout: TimeInterval = 4.0

    init(dial: Dial, modeManager: ModeManager, radialMenu: RadialMenuController) {
        self.dial = dial
        self.modeManager = modeManager
        self.radialMenu = radialMenu

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

        dial.onRotation = { [weak self] rotation, scrollDirection in
            DispatchQueue.main.async {
                self?.handleRotation(rotation, scrollDirection)
            }
        }
    }

    private func handlePress() {
        switch state {
        case .idle:
            state = .pressed(downForwarded: false)
            longPressTimer = Timer.scheduledTimer(withTimeInterval: longPressDelay, repeats: false) { [weak self] _ in
                self?.handleLongPress()
            }
        case .menuOpen:
            selectHighlightedMode()
            state = .consumingPress
        default:
            break
        }
    }

    private func handleRelease() {
        switch state {
        case .pressed(let downForwarded):
            cancelLongPressTimer()
            if !downForwarded {
                modeManager.currentController.onDown()
            }
            modeManager.currentController.onUp()
            state = .idle
        case .longPressed(let rotated):
            if rotated {
                // Quick gesture: hold, twist, release
                selectHighlightedMode()
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

    private func handleRotation(_ rotation: Dial.Rotation, _ scrollDirection: Int) {
        switch state {
        case .idle:
            modeManager.currentController.onRotate(rotation, scrollDirection)
        case .pressed(let downForwarded):
            // Rotating while pressed is a press-drag, not a long press
            cancelLongPressTimer()
            if !downForwarded {
                modeManager.currentController.onDown()
                state = .pressed(downForwarded: true)
            }
            modeManager.currentController.onRotate(rotation, scrollDirection)
        case .longPressed:
            if radialMenu.rotate(steps(of: rotation)) {
                dial.device.impact()
            }
            state = .longPressed(rotated: true)
        case .menuOpen:
            if radialMenu.rotate(steps(of: rotation)) {
                dial.device.impact()
            }
            restartMenuTimeout()
        case .consumingPress:
            break
        }
    }

    private func handleLongPress() {
        guard case .pressed(downForwarded: false) = state else { return }
        state = .longPressed(rotated: false)
        radialMenu.show(modes: modeManager.modes, current: modeManager.currentMode)
        dial.device.impact(repeatCount: 2)
    }

    private func selectHighlightedMode() {
        if let mode = radialMenu.highlightedMode, mode != modeManager.currentMode {
            modeManager.currentMode = mode
        }
        radialMenu.hide()
        cancelMenuTimeout()
        dial.device.impact()
    }

    private func steps(of rotation: Dial.Rotation) -> Int {
        switch rotation {
        case .Clockwise(let d):
            return d
        case .CounterClockwise(let d):
            return -d
        }
    }

    private func cancelLongPressTimer() {
        longPressTimer?.invalidate()
        longPressTimer = nil
    }

    private func restartMenuTimeout() {
        cancelMenuTimeout()
        menuTimeoutTimer = Timer.scheduledTimer(withTimeInterval: menuTimeout, repeats: false) { [weak self] _ in
            guard let self = self, case .menuOpen = self.state else { return }
            self.radialMenu.hide()
            self.state = .idle
        }
    }

    private func cancelMenuTimeout() {
        menuTimeoutTimer?.invalidate()
        menuTimeoutTimer = nil
    }
}
