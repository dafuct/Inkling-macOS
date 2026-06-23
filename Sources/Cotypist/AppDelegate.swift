import AppKit
import CotypistCore

final class AppDelegate: NSObject, NSApplicationDelegate {
    private let eventTap = EventTapController()
    private let overlay = OverlayWindow()
    private var statusItem: NSStatusItem?

    func applicationDidFinishLaunching(_ notification: Notification) {
        setupMenuBar()

        guard PermissionsManager.isAccessibilityTrusted(prompt: true) else {
            NSLog("Cotypist: grant Accessibility permission in System Settings, then relaunch.")
            return
        }

        eventTap.onKeyDown = { [weak self] in self?.refreshSuggestion() }
        eventTap.onAccept = { [weak self] in
            NSLog("Cotypist: ACCEPTED suggestion")
            self?.overlay.hide()
            self?.eventTap.suggestionVisible = false
        }

        if !eventTap.start() {
            NSLog("Cotypist: failed to create event tap — check Accessibility/Input Monitoring.")
        }
    }

    private func setupMenuBar() {
        let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        item.button?.title = "⌨︎"
        let menu = NSMenu()
        menu.addItem(NSMenuItem(title: "Quit Cotypist",
                                action: #selector(NSApplication.terminate(_:)),
                                keyEquivalent: "q"))
        item.menu = menu
        statusItem = item
    }

    /// Reads context shortly after the keystroke (so AX reflects it), then draws
    /// a fixed dummy suggestion at the caret. The real model arrives in Phase 2.
    private func refreshSuggestion() {
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) { [weak self] in
            guard let self else { return }
            guard let readout = FocusContextProvider.currentReadout(),
                  let bounds = readout.caretBounds else {
                self.overlay.hide()
                self.eventTap.suggestionVisible = false
                return
            }
            let context = TextContext(fullText: readout.text, caretIndex: readout.caretIndex)
            NSLog("Cotypist: prefix=\"\(context.prefix.suffix(20))\" caret=\(readout.caretIndex)")

            let suggestion = " hello" // dummy engine — proves the pipeline
            self.overlay.show(text: suggestion, caretBounds: bounds)
            self.eventTap.suggestionVisible = true
        }
    }
}
