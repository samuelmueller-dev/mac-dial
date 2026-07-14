
import Foundation
import AppKit

class ScrollController: Controller
{
    enum Direction {
        case up
        case down
    }
    
    private func sendMouse(button direction: Direction) {
        let mousePos = NSEvent.mouseLocation
        let screenHeight = NSScreen.main?.frame.height ?? 0
        
        let translatedMousePos = NSPoint(x: mousePos.x, y: screenHeight - mousePos.y)
        
        let event = CGEvent(mouseEventSource: nil, mouseType: direction == .down ? .leftMouseDown : .leftMouseUp, mouseCursorPosition: translatedMousePos, mouseButton: .left)
        
        event?.post(tap: .cghidEventTap)
    }
    
    func onDown() {
        sendMouse(button: .down)
    }
    
    func onUp() {
        sendMouse(button: .up)
    }
    
    var lastRotate: TimeInterval = Date().timeIntervalSince1970

    // Smooth path: raw encoder steps (3600/rev) posted as pixel-unit scroll
    // events, i.e. trackpad-style continuous scrolling
    func onRotateRaw(_ rawSteps: Int, _ scrollDirection: Int) {
        let steps = rawSteps * scrollDirection

        let diff = (Date().timeIntervalSince1970 - lastRotate) * 1000
        let multiplier = 1.0 + ((150.0 - min(diff, 150.0)) / 60.0)
        let pixels = Int32((Double(steps) * 1.5 * multiplier).rounded())

        let event = CGEvent(scrollWheelEvent2Source: nil, units: .pixel, wheelCount: 1, wheel1: pixels, wheel2: 0, wheel3: 0)
        event?.post(tap: .cghidEventTap)

        lastRotate = Date().timeIntervalSince1970
    }

    func onRotate(_ rotation: Dial.Rotation,_ scrollDirection: Int) {
        var steps = 0
        switch rotation {
        case .Clockwise(let d):
            steps = d
        case .CounterClockwise(let d):
            steps = -d
        }
        
        steps *= scrollDirection;
        
        let diff = (Date().timeIntervalSince1970 - lastRotate) * 1000
        let multiplifer = Int(1 + ((150 - min(diff, 150)) / 40))
        
        
        let event = CGEvent(scrollWheelEvent2Source: nil, units: .line, wheelCount: 1, wheel1: Int32(steps * multiplifer), wheel2: 0, wheel3: 0)
        
        event?.post(tap: .cghidEventTap)
        
        lastRotate = Date().timeIntervalSince1970
    }
}
