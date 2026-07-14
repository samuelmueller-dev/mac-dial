
import Foundation

protocol Controller: AnyObject
{
    func onDown()

    func onUp()

    // Synthesized detents (default path for all modes)
    func onRotate(_ rotation: Dial.Rotation,_ scrollDirection: Int)

    // Raw encoder steps at 3600/rev, for modes that support smooth input
    func onRotateRaw(_ rawSteps: Int,_ scrollDirection: Int)
}

extension Controller {
    func onRotateRaw(_ rawSteps: Int,_ scrollDirection: Int) {}
}
