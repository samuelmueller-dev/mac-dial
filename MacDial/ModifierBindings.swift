
import Foundation
import AppKit
import Carbon.HIToolbox

// Rotation overrides while keyboard modifiers are held: when a bound modifier
// combo is down, dial rotation is routed here instead of to the active mode.
class ModifierBindings {

    struct Binding {
        let modifiers: NSEvent.ModifierFlags
        // Detents needed per trigger, so a small twist doesn't jump several
        // apps or spaces at once
        let stepsPerTrigger: Int
        let perform: (Int) -> Void
    }

    private let bindings: [Binding] = [
        // Shift + rotate: cycle through open applications
        Binding(modifiers: [.shift], stepsPerTrigger: 3, perform: ModifierBindings.switchApplication),
        // Cmd + Shift + rotate: move between desktops/spaces
        Binding(modifiers: [.command, .shift], stepsPerTrigger: 4, perform: ModifierBindings.switchSpace)
    ]

    private let hapticTick: () -> Void
    private var activeModifiers: NSEvent.ModifierFlags = []
    private var accumulatedSteps = 0

    init(hapticTick: @escaping () -> Void) {
        self.hapticTick = hapticTick
    }

    // Returns true if the rotation was consumed by a modifier binding
    func handle(steps: Int) -> Bool {
        let current = NSEvent.modifierFlags.intersection([.shift, .command, .option, .control])

        guard let binding = bindings.first(where: { $0.modifiers == current }) else {
            activeModifiers = []
            accumulatedSteps = 0
            return false
        }

        if current != activeModifiers {
            activeModifiers = current
            accumulatedSteps = 0
        }

        accumulatedSteps += steps
        while abs(accumulatedSteps) >= binding.stepsPerTrigger {
            let direction = accumulatedSteps > 0 ? 1 : -1
            binding.perform(direction)
            hapticTick()
            accumulatedSteps -= direction * binding.stepsPerTrigger
        }
        return true
    }

    private static func switchApplication(_ direction: Int) {
        let apps = NSWorkspace.shared.runningApplications.filter {
            $0.activationPolicy == .regular
        }
        guard apps.count > 1 else { return }

        let frontIndex = apps.firstIndex { $0.isActive } ?? 0
        let next = ((frontIndex + direction) % apps.count + apps.count) % apps.count
        apps[next].activate(options: [])
    }

    private static func switchSpace(_ direction: Int) {
        // Relies on the default Mission Control shortcuts (^Left / ^Right)
        postKeystroke(direction > 0 ? kVK_RightArrow : kVK_LeftArrow, flags: .maskControl)
    }
}
