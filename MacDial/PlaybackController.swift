

import Foundation
import AppKit

class PlaybackController : Controller {
    
    var lastClick = Date().timeIntervalSince1970
    
    func onDown() {
        
    }
    
    func onUp() {
        
        let clickDelay = Date().timeIntervalSince1970 - lastClick
        
        // Next song on double click
        if (clickDelay < 0.5) {
            // Undo pause sent on first click
            HIDPostAuxKey(key: NX_KEYTYPE_PLAY, modifiers: [], _repeat: 1)
            
            HIDPostAuxKey(key: NX_KEYTYPE_NEXT, modifiers: [])
        }
        else { // Play / Pause on single click
            
            HIDPostAuxKey(key: NX_KEYTYPE_PLAY, modifiers: [], _repeat: 1)
        }
        
        lastClick = Date().timeIntervalSince1970
    }
    
    
    
    func onRotate(_ rotation: Dial.Rotation,_ scrollDirection: Int) {
        
        let modifiers = [NSEvent.ModifierFlags.shift, NSEvent.ModifierFlags.option]
        
        switch (rotation) {
        case .Clockwise(let _repeat):
            HIDPostAuxKey(key: NX_KEYTYPE_SOUND_UP, modifiers: modifiers, _repeat: _repeat)
            break
        case .CounterClockwise(let _repeat):
            HIDPostAuxKey(key: NX_KEYTYPE_SOUND_DOWN, modifiers: modifiers, _repeat: _repeat)

            break
        }
    }
    
    
}
