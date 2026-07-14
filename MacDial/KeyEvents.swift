
import Foundation
import AppKit
import Carbon.HIToolbox

// https://stackoverflow.com/a/55854051
func HIDPostAuxKey(key: Int32, modifiers: [NSEvent.ModifierFlags], _repeat: Int = 1) {
    func doKey(down: Bool) {

        var rawFlags: UInt = (down ? 0xa00 : 0xb00);

        for modifier in modifiers {
            rawFlags |= modifier.rawValue
        }

        let flags = NSEvent.ModifierFlags(rawValue: rawFlags)

        let data1 = Int((key<<16) | (down ? 0xa00 : 0xb00))

        let ev = NSEvent.otherEvent(with: NSEvent.EventType.systemDefined,
                                    location: NSPoint(x:0,y:0),
                                    modifierFlags: flags,
                                    timestamp: 0,
                                    windowNumber: 0,
                                    context: nil,
                                    subtype: 8,
                                    data1: data1,
                                    data2: -1
                                    )
        let cev = ev?.cgEvent
        cev?.post(tap: CGEventTapLocation.cghidEventTap)
    }
    for _ in 0..<_repeat {
        doKey(down: true)
        doKey(down: false)
    }
}

func postKeystroke(_ keyCode: Int, flags: CGEventFlags = [], _repeat: Int = 1) {
    for _ in 0..<_repeat {
        let down = CGEvent(keyboardEventSource: nil, virtualKey: CGKeyCode(keyCode), keyDown: true)
        down?.flags = flags
        down?.post(tap: .cghidEventTap)

        let up = CGEvent(keyboardEventSource: nil, virtualKey: CGKeyCode(keyCode), keyDown: false)
        up?.flags = flags
        up?.post(tap: .cghidEventTap)
    }
}
