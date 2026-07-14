
import Foundation
import AppKit

class RadialMenuView: NSView {

    var modes: [Mode] = []
    var highlightedIndex: Int = 0 {
        didSet { needsDisplay = true }
    }

    private let outerRadius: CGFloat = 130
    private let innerRadius: CGFloat = 44
    private let iconSize: CGFloat = 30

    private func tintedIcon(for mode: Mode, color: NSColor) -> NSImage? {
        guard let symbol = NSImage(systemSymbolName: mode.symbolName, accessibilityDescription: mode.title)?
            .withSymbolConfiguration(.init(pointSize: iconSize, weight: .medium)) else {
            return nil
        }
        let size = symbol.size
        let image = NSImage(size: size)
        image.lockFocus()
        symbol.draw(in: NSRect(origin: .zero, size: size))
        color.set()
        NSRect(origin: .zero, size: size).fill(using: .sourceAtop)
        image.unlockFocus()
        return image
    }

    // Mid-angle of segment i in AppKit degrees (counterclockwise from +x).
    // Segment 0 sits at the top, segments advance clockwise.
    private func midAngle(_ index: Int) -> CGFloat {
        let span = 360.0 / CGFloat(modes.count)
        return 90.0 - CGFloat(index) * span
    }

    override func draw(_ dirtyRect: NSRect) {
        guard !modes.isEmpty else { return }

        let center = NSPoint(x: bounds.midX, y: bounds.midY)
        let span = 360.0 / CGFloat(modes.count)

        let disc = NSBezierPath()
        disc.appendArc(withCenter: center, radius: outerRadius, startAngle: 0, endAngle: 360)
        NSColor(calibratedWhite: 0.11, alpha: 0.92).setFill()
        disc.fill()

        // Highlighted wedge
        let start = midAngle(highlightedIndex) - span / 2
        let end = midAngle(highlightedIndex) + span / 2
        let wedge = NSBezierPath()
        wedge.move(to: center)
        wedge.appendArc(withCenter: center, radius: outerRadius, startAngle: start, endAngle: end)
        wedge.close()
        NSColor.controlAccentColor.withAlphaComponent(0.9).setFill()
        wedge.fill()

        // Segment separators
        NSColor(calibratedWhite: 1.0, alpha: 0.15).setStroke()
        for i in 0..<modes.count {
            let angle = (midAngle(i) + span / 2) * .pi / 180
            let line = NSBezierPath()
            line.move(to: NSPoint(x: center.x + cos(angle) * innerRadius,
                                  y: center.y + sin(angle) * innerRadius))
            line.line(to: NSPoint(x: center.x + cos(angle) * outerRadius,
                                  y: center.y + sin(angle) * outerRadius))
            line.lineWidth = 1
            line.stroke()
        }

        // Center hub
        let hub = NSBezierPath()
        hub.appendArc(withCenter: center, radius: innerRadius, startAngle: 0, endAngle: 360)
        NSColor(calibratedWhite: 0.05, alpha: 0.95).setFill()
        hub.fill()

        let ring = NSBezierPath()
        ring.appendArc(withCenter: center, radius: outerRadius, startAngle: 0, endAngle: 360)
        ring.lineWidth = 1.5
        NSColor(calibratedWhite: 1.0, alpha: 0.2).setStroke()
        ring.stroke()

        // Icons
        let iconRadius = (outerRadius + innerRadius) / 2
        for (i, mode) in modes.enumerated() {
            guard let icon = tintedIcon(for: mode, color: .white) else { continue }
            let angle = midAngle(i) * .pi / 180
            let pos = NSPoint(x: center.x + cos(angle) * iconRadius - icon.size.width / 2,
                              y: center.y + sin(angle) * iconRadius - icon.size.height / 2)
            icon.draw(in: NSRect(origin: pos, size: icon.size))
        }

        // Highlighted mode title in the hub
        let title = modes[highlightedIndex].title
        let attributes: [NSAttributedString.Key: Any] = [
            .font: NSFont.systemFont(ofSize: 11, weight: .semibold),
            .foregroundColor: NSColor.white
        ]
        let textSize = title.size(withAttributes: attributes)
        title.draw(at: NSPoint(x: center.x - textSize.width / 2,
                               y: center.y - textSize.height / 2),
                   withAttributes: attributes)
    }
}

class RadialMenuController {

    private var panel: NSPanel?
    private var view: RadialMenuView?
    private var accumulatedSteps = 0

    // Detents needed to move the highlight by one segment
    private let stepsPerSegment = 2

    var isVisible: Bool {
        return panel?.isVisible ?? false
    }

    var highlightedMode: Mode? {
        guard let view = view, !view.modes.isEmpty else { return nil }
        return view.modes[view.highlightedIndex]
    }

    func show(modes: [Mode], current: Mode) {
        hide(animated: false)
        accumulatedSteps = 0

        let size = NSSize(width: 280, height: 280)
        let menuView = RadialMenuView(frame: NSRect(origin: .zero, size: size))
        menuView.modes = modes
        menuView.highlightedIndex = modes.firstIndex(of: current) ?? 0

        let panel = NSPanel(contentRect: NSRect(origin: .zero, size: size),
                            styleMask: [.borderless, .nonactivatingPanel],
                            backing: .buffered,
                            defer: false)
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = false
        panel.level = .popUpMenu
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        panel.ignoresMouseEvents = true
        panel.isReleasedWhenClosed = false
        panel.contentView = menuView

        // Center on the cursor, clamped to the screen it is on
        let mouse = NSEvent.mouseLocation
        var origin = NSPoint(x: mouse.x - size.width / 2, y: mouse.y - size.height / 2)
        if let screen = NSScreen.screens.first(where: { NSMouseInRect(mouse, $0.frame, false) }) {
            let frame = screen.visibleFrame
            origin.x = min(max(origin.x, frame.minX), frame.maxX - size.width)
            origin.y = min(max(origin.y, frame.minY), frame.maxY - size.height)
        }
        panel.setFrameOrigin(origin)

        panel.alphaValue = 0
        panel.orderFrontRegardless()
        NSAnimationContext.runAnimationGroup { context in
            context.duration = 0.12
            panel.animator().alphaValue = 1
        }

        self.panel = panel
        self.view = menuView
    }

    // Returns true if the highlight moved (used for haptic ticks)
    func rotate(_ delta: Int) -> Bool {
        guard let view = view, !view.modes.isEmpty else { return false }

        accumulatedSteps += delta
        var moved = false
        while abs(accumulatedSteps) >= stepsPerSegment {
            let direction = accumulatedSteps > 0 ? 1 : -1
            let count = view.modes.count
            view.highlightedIndex = (view.highlightedIndex + direction + count) % count
            accumulatedSteps -= direction * stepsPerSegment
            moved = true
        }
        return moved
    }

    func hide(animated: Bool = true) {
        guard let panel = self.panel else { return }
        self.panel = nil
        self.view = nil

        if animated {
            NSAnimationContext.runAnimationGroup({ context in
                context.duration = 0.15
                panel.animator().alphaValue = 0
            }, completionHandler: {
                panel.orderOut(nil)
            })
        } else {
            panel.orderOut(nil)
        }
    }
}
