import AppKit
import SwiftUI

// Velocity sample used for flick detection
private struct DragSample {
    let position: NSPoint
    let time: TimeInterval
}

final class LiveTripCardPanelController: NSObject {

    // MARK: - Flick-aware panel

    private class FlickablePanel: NSPanel {
        private var dragSamples: [DragSample] = []
        var onFlick: ((CGVector) -> Void)?

        override func sendEvent(_ event: NSEvent) {
            switch event.type {
            case .leftMouseDown:
                dragSamples = []
            case .leftMouseDragged:
                // Track absolute screen position of the mouse for velocity calculation
                let screenPos = NSPoint(
                    x: frame.origin.x + event.locationInWindow.x,
                    y: frame.origin.y + event.locationInWindow.y
                )
                dragSamples.append(DragSample(position: screenPos, time: event.timestamp))
                if dragSamples.count > 5 { dragSamples.removeFirst() }
            case .leftMouseUp:
                let vel = computeVelocity()
                super.sendEvent(event)
                if let vel { onFlick?(vel) }
                dragSamples = []
                return
            default:
                break
            }
            super.sendEvent(event)
        }

        private func computeVelocity() -> CGVector? {
            // Use last 3 samples for a stable estimate
            let samples = dragSamples.suffix(3)
            guard let first = samples.first, let last = samples.last,
                  first.time != last.time else { return nil }
            let dt = last.time - first.time
            guard dt > 0.005 else { return nil }
            return CGVector(
                dx: (last.position.x - first.position.x) / dt,
                dy: (last.position.y - first.position.y) / dt
            )
        }
    }

    // MARK: - Properties

    private var panel: FlickablePanel?
    private var onCloseCallback: (() -> Void)?
    private var springTimer: Timer?

    var isVisible: Bool { panel?.isVisible == true }

    // MARK: - Public API

    func show(snapshot: LiveTripCardSnapshot, onClose: @escaping () -> Void) {
        onCloseCallback = onClose
        if let panel {
            panel.contentView = NSHostingView(rootView: makeCardView(snapshot: snapshot))
            panel.orderFrontRegardless()
            return
        }

        let panel = FlickablePanel(
            contentRect: NSRect(x: 0, y: 0, width: 292, height: 110),
            styleMask: [.nonactivatingPanel, .borderless],
            backing: .buffered,
            defer: false
        )
        panel.level = .floating
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = false
        panel.hidesOnDeactivate = false
        panel.isReleasedWhenClosed = false
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        panel.ignoresMouseEvents = false
        panel.isMovableByWindowBackground = true
        panel.contentView = NSHostingView(rootView: makeCardView(snapshot: snapshot))
        panel.onFlick = { [weak self] vel in self?.handleFlick(velocity: vel) }

        placeNearTopRight(panel)
        panel.orderFrontRegardless()
        self.panel = panel
    }

    /// Push a fresh snapshot into the visible card without recreating the panel.
    func update(snapshot: LiveTripCardSnapshot) {
        guard let panel else { return }
        panel.contentView = NSHostingView(rootView: makeCardView(snapshot: snapshot))
    }

    func close() {
        springTimer?.invalidate()
        springTimer = nil
        panel?.orderOut(nil)
    }

    // MARK: - Private helpers

    private func makeCardView(snapshot: LiveTripCardSnapshot) -> some View {
        LiveTripCardView(snapshot: snapshot) { [weak self] in
            self?.close()
            self?.onCloseCallback?()
        }
        // Extra padding so the drop shadow renders without clipping
        .padding(16)
    }

    private func placeNearTopRight(_ panel: NSPanel) {
        guard let screenFrame = NSScreen.main?.visibleFrame else { return }
        let x = screenFrame.maxX - panel.frame.width - 20
        let y = screenFrame.maxY - panel.frame.height - 20
        panel.setFrameOrigin(NSPoint(x: x, y: y))
    }

    // MARK: - Flick to corner

    private func handleFlick(velocity: CGVector) {
        let speed = sqrt(velocity.dx * velocity.dx + velocity.dy * velocity.dy)
        guard speed > 400, let screen = NSScreen.main, let panel else { return }

        let sf = screen.visibleFrame
        let margin: CGFloat = 20

        // Horizontal corner: follow vx direction
        let snapX: CGFloat = velocity.dx >= 0
            ? sf.maxX - panel.frame.width - margin
            : sf.minX + margin

        // Vertical corner: follow vy if significant, otherwise use nearest edge
        let snapY: CGFloat
        if abs(velocity.dy) > 60 {
            snapY = velocity.dy >= 0
                ? sf.maxY - panel.frame.height - margin
                : sf.minY + margin
        } else {
            snapY = panel.frame.midY > sf.midY
                ? sf.maxY - panel.frame.height - margin
                : sf.minY + margin
        }

        animateToCorner(NSPoint(x: snapX, y: snapY))
    }

    /// Spring-physics animation toward a target corner with a subtle bounce.
    private func animateToCorner(_ target: NSPoint) {
        springTimer?.invalidate()
        guard let panel else { return }

        var pos = CGPoint(x: panel.frame.origin.x, y: panel.frame.origin.y)
        var vel = CGPoint.zero

        // Underdamped spring (zeta ≈ 0.55) for a visible but not wild bounce
        let stiffness: CGFloat = 90
        let damping: CGFloat = 12
        let dt: CGFloat = 1.0 / 60.0

        let timer = Timer(timeInterval: dt, repeats: true) { [weak self] t in
            guard let self, let panel = self.panel else { t.invalidate(); return }

            let dx = target.x - pos.x
            let dy = target.y - pos.y

            vel.x += (stiffness * dx - damping * vel.x) * dt
            vel.y += (stiffness * dy - damping * vel.y) * dt
            pos.x += vel.x * dt
            pos.y += vel.y * dt

            panel.setFrameOrigin(NSPoint(x: pos.x, y: pos.y))

            let dist = sqrt(dx * dx + dy * dy)
            let speed = sqrt(vel.x * vel.x + vel.y * vel.y)
            if dist < 0.5 && speed < 1 {
                panel.setFrameOrigin(target)
                t.invalidate()
                self.springTimer = nil
            }
        }
        RunLoop.main.add(timer, forMode: .common)
        springTimer = timer
    }
}
