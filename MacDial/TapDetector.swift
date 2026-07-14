
import Foundation

// Detects physical taps of the puck against a surface from encoder jitter.
//
// Empirically (at 3600 steps/rev): a tap produces a 130-620ms burst of 3-23
// reports with tiny mixed-sign deltas summing to ~nothing, while even the
// gentlest intentional rotation is a sustained same-sign stream that
// accumulates hundreds of steps. Firm taps can also mechanically actuate the
// button for <60ms; those phantom clicks are suppressed and folded into the
// tap classification.
class TapDetector {

    var onTap: (() -> Void)?

    private struct Sample {
        let time: TimeInterval
        let delta: Int
    }

    private var burst: [Sample] = []
    private var burstHadSuppressedClick = false
    private var endTimer: Timer?

    // Burst ends after this much silence
    private let burstGap: TimeInterval = 0.25
    // Tap signature limits (rotation exceeds all of these)
    private let maxSpan: TimeInterval = 0.7
    private let maxReports = 40
    private let maxNetSteps = 30
    private let maxSingleDelta = 6
    private let minReports = 3
    // A button actuation this short, during jitter, is a tap side-effect
    private let maxPhantomClickDuration: TimeInterval = 0.06

    func feed(rawSteps: Int) {
        let now = Date().timeIntervalSince1970
        if let last = burst.last, now - last.time > burstGap {
            reset()
        }
        burst.append(Sample(time: now, delta: rawSteps))

        endTimer?.invalidate()
        endTimer = Timer.scheduledTimer(withTimeInterval: burstGap, repeats: false) { [weak self] _ in
            self?.classify()
        }
    }

    // Called on button release while a click (not drag/long-press) is pending.
    // Returns true if the click should be swallowed as a tap artifact.
    func shouldSuppressClick(pressDuration: TimeInterval) -> Bool {
        guard pressDuration < maxPhantomClickDuration,
              let last = burst.last,
              Date().timeIntervalSince1970 - last.time < burstGap else {
            return false
        }
        burstHadSuppressedClick = true
        return true
    }

    private func classify() {
        defer { reset() }
        guard let first = burst.first, let last = burst.last else { return }

        // A tap that actuated the button is a tap regardless of jitter stats
        if burstHadSuppressedClick {
            onTap?()
            return
        }

        let span = last.time - first.time
        let net = burst.reduce(0) { $0 + $1.delta }
        let peak = burst.map { abs($0.delta) }.max() ?? 0

        if burst.count >= minReports
            && burst.count <= maxReports
            && span <= maxSpan
            && abs(net) <= maxNetSteps
            && peak <= maxSingleDelta {
            onTap?()
        }
    }

    private func reset() {
        burst = []
        burstHadSuppressedClick = false
        endTimer?.invalidate()
        endTimer = nil
    }
}
