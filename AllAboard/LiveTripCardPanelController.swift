import AppKit
import SwiftUI

final class LiveTripCardPanelController: NSObject {

    // MARK: - Properties

    private var panel: NSPanel?
    private var onCloseCallback: (() -> Void)?

    var isVisible: Bool { panel?.isVisible == true }

    // MARK: - Public API

    func show(snapshot: LiveTripCardSnapshot, onClose: @escaping () -> Void) {
        onCloseCallback = onClose
        if let panel {
            panel.contentView = NSHostingView(rootView: makeCardView(snapshot: snapshot))
            panel.orderFrontRegardless()
            return
        }

        let panel = NSPanel(
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
        panel?.orderOut(nil)
    }

    // MARK: - Private helpers

    private func makeCardView(snapshot: LiveTripCardSnapshot) -> some View {
        LiveTripCardView(snapshot: snapshot) { [weak self] in
            self?.close()
            self?.onCloseCallback?()
        }
        .padding(16)
    }

    private func placeNearTopRight(_ panel: NSPanel) {
        guard let screenFrame = NSScreen.main?.visibleFrame else { return }
        let x = screenFrame.maxX - panel.frame.width - 20
        let y = screenFrame.maxY - panel.frame.height - 20
        panel.setFrameOrigin(NSPoint(x: x, y: y))
    }
}
