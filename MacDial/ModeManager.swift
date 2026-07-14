
import Foundation
import AppKit

enum Mode: String, CaseIterable {
    case scrolling = "scroll"
    case playback = "playback"
    case brightness = "brightness"
    case zoom = "zoom"
    case undoRedo = "undoredo"

    var title: String {
        switch self {
        case .scrolling: return "Scroll"
        case .playback: return "Playback"
        case .brightness: return "Brightness"
        case .zoom: return "Zoom"
        case .undoRedo: return "Undo / Redo"
        }
    }

    var symbolName: String {
        switch self {
        case .scrolling: return "arrow.up.arrow.down.circle"
        case .playback: return "playpause.circle"
        case .brightness: return "sun.max"
        case .zoom: return "plus.magnifyingglass"
        case .undoRedo: return "arrow.uturn.backward.circle"
        }
    }

    var image: NSImage? {
        let image = NSImage(systemSymbolName: symbolName, accessibilityDescription: title)
        image?.isTemplate = true
        return image
    }
}

class ModeManager {

    let modes = Mode.allCases

    private let controllers: [Mode: Controller] = [
        .scrolling: ScrollController(),
        .playback: PlaybackController(),
        .brightness: BrightnessController(),
        .zoom: ZoomController(),
        .undoRedo: UndoRedoController()
    ]

    var onModeChanged: [(Mode) -> Void] = []

    var currentMode: Mode {
        get {
            guard let raw = UserDefaults.standard.string(forKey: "mode"),
                  let mode = Mode(rawValue: raw) else {
                return .scrolling
            }
            return mode
        }
        set (mode) {
            UserDefaults.standard.setValue(mode.rawValue, forKey: "mode")
            for observer in onModeChanged {
                observer(mode)
            }
        }
    }

    var currentController: Controller {
        return controllers[currentMode]!
    }
}
