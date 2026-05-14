import AppKit
import SwiftUI

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {

    private(set) var runner: ConversionRunner!
    private var statusItem: NSStatusItem!
    private var panel: NSPanel!
    private var clickOutsideMonitor: Any?

    func applicationDidFinishLaunching(_ notification: Notification) {
        runner = ConversionRunner()
        setupStatusItem()
        setupPanel()
    }

    func applicationWillTerminate(_ notification: Notification) {
        removeClickOutsideMonitor()
    }

    func applicationShouldTerminate(_ sender: NSApplication) -> NSApplication.TerminateReply {
        guard let runner, runner.hasInflight else { return .terminateNow }

        let alert = NSAlert()
        alert.messageText = "Conversions in progress."
        alert.informativeText = "Quit anyway? In-flight conversions will be cancelled."
        alert.addButton(withTitle: "Cancel")
        alert.addButton(withTitle: "Quit")
        alert.alertStyle = .warning

        if alert.runModal() == .alertSecondButtonReturn {
            runner.cancelAll()
            return .terminateNow
        }
        return .terminateCancel
    }

    private func setupStatusItem() {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        if let button = statusItem.button {
            button.image = NSImage(
                systemSymbolName: "photo.stack",
                accessibilityDescription: "Loosey Goosey"
            )
            button.action = #selector(togglePanel)
            button.target = self
        }
    }

    // MARK: - Panel

    private func setupPanel() {
        let host = NSHostingController(rootView:
            PanelRootView()
                .environmentObject(runner)
                .frame(width: 340)
                .fixedSize(horizontal: false, vertical: true)
        )

        let p = NSPanel(
            contentRect: NSRect(x: 0, y: 0, width: 340, height: 500),
            styleMask: [.nonactivatingPanel, .borderless, .resizable],
            backing: .buffered,
            defer: false
        )
        p.contentViewController = host
        p.isOpaque = false
        p.backgroundColor = .clear
        p.hasShadow = true
        p.isMovableByWindowBackground = false
        p.hidesOnDeactivate = false
        p.becomesKeyOnlyIfNeeded = true
        p.level = .floating
        p.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .transient]

        panel = p
    }

    @objc private func togglePanel() {
        guard let panel else { return }
        if panel.isVisible {
            hidePanel()
        } else {
            showPanel()
        }
    }

    private func showPanel() {
        guard let panel,
              let button = statusItem.button,
              let buttonWindow = button.window else { return }

        panel.layoutIfNeeded()

        let buttonFrame = buttonWindow.convertToScreen(button.frame)
        let panelSize = panel.frame.size
        let origin = NSPoint(
            x: buttonFrame.midX - panelSize.width / 2,
            y: buttonFrame.minY - panelSize.height - 6
        )
        panel.setFrameOrigin(Self.clampedToScreen(origin: origin, size: panelSize))
        panel.orderFrontRegardless()

        runner.setPanelVisible(true)
        installClickOutsideMonitor()
    }

    private func hidePanel() {
        guard let panel, panel.isVisible else { return }
        panel.orderOut(nil)
        runner.setPanelVisible(false)
        removeClickOutsideMonitor()
    }

    /// Y is intentionally not clamped (menu bar is always at top, panel always has room below).
    /// `visibleFrame` override exists so this is unit-testable without a live NSScreen.
    nonisolated static func clampedToScreen(origin: NSPoint, size: NSSize, visibleFrame: NSRect? = nil) -> NSPoint {
        let visible: NSRect
        if let visibleFrame {
            visible = visibleFrame
        } else if let screen = NSScreen.screens.first(where: { $0.frame.contains(origin) }) ?? NSScreen.main {
            visible = screen.visibleFrame
        } else {
            return origin
        }
        let maxX = visible.maxX - size.width - 8
        let minX = visible.minX + 8
        return NSPoint(
            x: min(max(origin.x, minX), maxX),
            y: origin.y
        )
    }

    // MARK: - Click-outside-to-dismiss

    /// Listens for mouse-UP events outside our app. mouseUp (not mouseDown) is the
    /// correct event: a drag that starts in Finder and ends inside our panel fires
    /// mouseUp inside our process, where global monitors don't see it — so the drop
    /// completes. A click-and-release fully outside our app fires here and dismisses.
    private func installClickOutsideMonitor() {
        removeClickOutsideMonitor()
        clickOutsideMonitor = NSEvent.addGlobalMonitorForEvents(
            matching: [.leftMouseUp, .rightMouseUp]
        ) { [weak self] _ in
            // Global monitor callbacks are delivered on the main thread by AppKit.
            MainActor.assumeIsolated { self?.hidePanel() }
        }
    }

    private func removeClickOutsideMonitor() {
        if let monitor = clickOutsideMonitor {
            NSEvent.removeMonitor(monitor)
            clickOutsideMonitor = nil
        }
    }
}
