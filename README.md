# Mac Dial

macOS support for the Surface Dial. The surface dial can be paired with macOS but any input results in invalid mouse inputs on macOS. This app reads the raw data from the dial and translates them to correct mouse and media inputs for macOS.

## Building

Make sure to clone the hidapi submodule and build the library using the build_hidapi.sh script. Note: This app depends on a hidapi fork, check the submodule to see what changed. App should then build with XCode.

Note: with CMake 4.x the hidapi fork needs a compatibility flag; pass `-DCMAKE_POLICY_VERSION_MINIMUM=3.5` to the cmake invocations in build_hidapi.sh.

You can find universal builds of the app under "releases". Note that these builds can be outdated.

## Usage

The app will continously try to open any Surface Dial connected to the computer and then process input controls. You will need to pair and connect the device as any other bluetooth device.

### Modes

The app supports five modes:

* **Scroll mode**: Turning the dial scrolls. Pressing the dial is interpreted as a mouse click at the current cursor position. Press-and-turn drags while scrolling.
* **Playback mode**: Turning the dial controls the system volume. Pressing the dial plays / pauses any current playback while a double click sends the "next" media action.
* **Brightness mode**: Turning the dial adjusts display brightness.
* **Zoom mode**: Turning the dial zooms in / out (sends ⌘+ / ⌘−). Pressing the dial resets zoom (⌘0).
* **Undo / Redo mode**: Turning the dial counterclockwise scrubs through undo history (⌘Z), clockwise redoes (⇧⌘Z). Great for creative apps.

### Triple click to focus a window

**Triple-click** the dial to inject a real mouse click at the cursor. This gives keyboard/scroll focus to the window under the pointer without moving your hand to the mouse. It's useful after switching apps or spaces: some apps (notably Firefox) ignore synthetic scroll events until a genuine click has landed inside their content area, so a quick triple-click primes the window and rotation starts scrolling immediately. Works in any mode.

### Radial menu (mode switching on the dial)

Press and **hold** the dial for half a second: a radial menu pops up around your cursor, replicating the Surface Dial on-screen menu from Windows. Then either:

* keep holding, turn to highlight a mode, and release to select it, or
* release first, turn to highlight, and press once to select.

Each segment change gives a haptic tick. The menu dismisses itself after 4 seconds of inactivity.

Modes can also be changed by clicking the Mac Dial icon in the system menu bar.

### Modifier bindings

Holding a keyboard modifier changes what rotation does, regardless of the active mode:

* **⇧ Shift + rotate**: cycle through open applications.
* **⌘⇧ Cmd+Shift + rotate**: switch desktops/spaces (uses the default Mission Control ^← / ^→ shortcuts — these must be enabled in *System Settings → Keyboard → Shortcuts → Mission Control*).

Each switch gives a haptic tick. Bindings are defined in `ModifierBindings.swift` and are easy to extend with additional combos.

### Per-app profiles

You can pin a mode to an application so the dial switches automatically when that app comes to the foreground (e.g. Undo/Redo in your editor, Playback everywhere else):

1. Focus the app you care about, then click the Mac Dial menu bar icon.
2. Make sure the mode you want is active, then choose *Per-App Profiles → Pin '<mode>' to <app>*.
3. To remove a pin, click its entry in the *Per-App Profiles* submenu.

### Other settings

Wheel sensitivity, scroll direction and haptics can be configured from the menu bar menu. If you want the app to run at startup you will need to add it yourself to the "login items" for your user.

## Improvements

* More input modes
* ~~Change input mode using the dial itself~~
* ~~Smarter device discovery (currently tries to open the dial every 50 ms)~~
