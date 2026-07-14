
import Cocoa
import ServiceManagement
import SwiftUI

@main
class AppDelegate: NSObject, NSApplicationDelegate {

    var statusBarController: StatusBarController?
    let dial = Dial()
    let modeManager = ModeManager()
    let radialMenu = RadialMenuController()
    var inputDispatcher: InputDispatcher?
    var profileManager: ProfileManager?
    
    func requestPermissions() {
        // More information on this behaviour: https://stackoverflow.com/questions/29006379/accessibility-permissions-reset-after-application-update
        if !AXIsProcessTrusted() {
            let alert = NSAlert()
            alert.messageText = "App permissions"
            alert.alertStyle = NSAlert.Style.informational
            alert.informativeText = "Detent needs Accessibility permissions to work. In the next dialog you will be asked to open the Settings app to enable the permissions.\nIMPORTANT! Due to an issue in macOS, if you're upgrading from an earlier version of Detent you might have to remove Detent from the accessibility permissions and then restart the app to re-add the permissions."
            alert.runModal()
        }
        
        let options : NSDictionary = [kAXTrustedCheckOptionPrompt.takeRetainedValue() as NSString: true]
        
        AXIsProcessTrustedWithOptions(options)
    }

    func applicationDidFinishLaunching(_ aNotification: Notification) {
        requestPermissions()
        let inputDispatcher = InputDispatcher(dial: dial, modeManager: modeManager, radialMenu: radialMenu)
        self.inputDispatcher = inputDispatcher
        let profileManager = ProfileManager(modeManager: modeManager)
        self.profileManager = profileManager
        statusBarController = StatusBarController.init(dial, modeManager: modeManager, profileManager: profileManager, dispatcher: inputDispatcher)
        dial.start();
    }

    func applicationWillTerminate(_ aNotification: Notification) {
        dial.stop();
    }
}

