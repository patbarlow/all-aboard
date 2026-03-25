import AppKit
import SwiftUI

final class LiveTripCardPanelController: NSObject {
    private var panel: NSPanel?

    var isVisible: Bool {
        panel?.isVisible == true
    }

    func show(snapshot: LiveTripCardSnapshot) {
        if let panel {
            panel.contentView = NSHostingView(rootView: makeCardView(snapshot: snapshot))
            panel.orderFrontRegardless()
            return
        }

        let panel = NSPanel(
            contentRect: NSRect(x: 0, y: 0, width: 320, height: 172),
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

    func close() {
        panel?.orderOut(nil)
    }

    private func makeCardView(snapshot: LiveTripCardSnapshot) -> some View {
        LiveTripCardView(snapshot: snapshot) { [weak self] in
            self?.close()
        }
        .padding(8)
    }

    private func placeNearTopRight(_ panel: NSPanel) {
        guard let screenFrame = NSScreen.main?.visibleFrame else { return }
        let x = screenFrame.maxX - panel.frame.width - 20
        let y = screenFrame.maxY - panel.frame.height - 28
        panel.setFrameOrigin(NSPoint(x: x, y: y))
    }
}
