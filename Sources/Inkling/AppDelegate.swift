import AppKit
import InklingCore

final class AppDelegate: NSObject, NSApplicationDelegate {
    private let eventTap = EventTapController()
    private let overlay = OverlayWindow()
    private var statusItem: NSStatusItem?
    private var currentSuggestion = ""

    func applicationDidFinishLaunching(_ notification: Notification) {
        setupMenuBar()

        let trusted = PermissionsManager.isAccessibilityTrusted(prompt: true)
        NSLog("Inkling: launched. accessibilityTrusted=\(trusted)")
        guard trusted else {
            NSLog("Inkling: NOT trusted — grant Accessibility, then relaunch.")
            return
        }

        eventTap.onKeyDown = { [weak self] in
            NSLog("Inkling: keyDown received")
            self?.refreshSuggestion()
        }
        eventTap.onAccept = { [weak self] in
            // The tap fires on the main run loop today; hop to main explicitly so
            // AppKit calls stay correct if Phase 1 moves the tap off-main.
            DispatchQueue.main.async {
                guard let self else { return }
                let toInsert = self.currentSuggestion
                self.overlay.hide()
                self.eventTap.suggestionVisible = false
                self.currentSuggestion = ""
                guard !toInsert.isEmpty else { return }
                TextInserter.insert(toInsert)
                NSLog("Inkling: inserted \"\(toInsert)\"")
            }
        }

        if eventTap.start() {
            NSLog("Inkling: event tap started.")
        } else {
            NSLog("Inkling: FAILED to create event tap — check Accessibility/Input Monitoring.")
        }
    }

    private func setupMenuBar() {
        let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        item.button?.title = "⌨︎"
        let menu = NSMenu()
        menu.addItem(NSMenuItem(title: "Quit Inkling",
                                action: #selector(NSApplication.terminate(_:)), // quit Inkling
                                keyEquivalent: "q"))
        item.menu = menu
        statusItem = item
    }

    /// Reads context shortly after the keystroke (so AX reflects it), then draws
    /// a fixed dummy suggestion at the caret. The real model arrives in Phase 2.
    private func refreshSuggestion() {
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) { [weak self] in
            guard let self else { return }
            guard let readout = FocusContextProvider.currentReadout() else {
                NSLog("Inkling: AX readout = nil (no focused text element, or not AX-readable)")
                self.overlay.hide()
                self.eventTap.suggestionVisible = false
                return
            }
            guard let bounds = readout.caretBounds else {
                NSLog("Inkling: AX ok (caret=\(readout.caretIndex)) but caretBounds = nil")
                self.overlay.hide()
                self.eventTap.suggestionVisible = false
                return
            }
            let context = TextContext(fullText: readout.text, caretIndex: readout.caretIndex)
            NSLog("Inkling: showing \"hello\" — prefix=\"\(context.prefix.suffix(20))\" caret=\(readout.caretIndex) bounds=\(bounds)")

            let suggestion = " hello" // dummy engine — proves the pipeline
            self.currentSuggestion = suggestion
            self.overlay.show(text: suggestion, caretBounds: bounds)
            self.eventTap.suggestionVisible = true
        }
    }
}
