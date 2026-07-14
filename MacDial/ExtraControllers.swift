
import Foundation
import AppKit
import Carbon.HIToolbox

class BrightnessController: Controller {

    func onDown() {
    }

    func onUp() {
    }

    func onRotate(_ rotation: Dial.Rotation, _ scrollDirection: Int) {
        switch rotation {
        case .Clockwise(let _repeat):
            HIDPostAuxKey(key: NX_KEYTYPE_BRIGHTNESS_UP, modifiers: [], _repeat: _repeat)
        case .CounterClockwise(let _repeat):
            HIDPostAuxKey(key: NX_KEYTYPE_BRIGHTNESS_DOWN, modifiers: [], _repeat: _repeat)
        }
    }
}

class ZoomController: Controller {

    func onDown() {
    }

    func onUp() {
        // Reset zoom
        postKeystroke(kVK_ANSI_0, flags: .maskCommand)
    }

    func onRotate(_ rotation: Dial.Rotation, _ scrollDirection: Int) {
        switch rotation {
        case .Clockwise(let _repeat):
            postKeystroke(kVK_ANSI_Equal, flags: .maskCommand, _repeat: _repeat)
        case .CounterClockwise(let _repeat):
            postKeystroke(kVK_ANSI_Minus, flags: .maskCommand, _repeat: _repeat)
        }
    }
}

class UndoRedoController: Controller {

    func onDown() {
    }

    func onUp() {
    }

    func onRotate(_ rotation: Dial.Rotation, _ scrollDirection: Int) {
        switch rotation {
        case .Clockwise(let _repeat):
            postKeystroke(kVK_ANSI_Z, flags: [.maskCommand, .maskShift], _repeat: _repeat)
        case .CounterClockwise(let _repeat):
            postKeystroke(kVK_ANSI_Z, flags: .maskCommand, _repeat: _repeat)
        }
    }
}
