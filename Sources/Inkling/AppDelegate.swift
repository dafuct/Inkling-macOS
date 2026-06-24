import AppKit
import InklingCore

final class AppDelegate: NSObject, NSApplicationDelegate {
    private let eventTap = EventTapController()
    private let overlay = OverlayWindow()
    private let engine: SuggestionEngine = MLXEngine(modelDirectory: ModelConfig.modelDirectory)
    private let debouncer = Debouncer(delay: 0.2)
    private var statusItem: NSStatusItem?
    private var currentSuggestion = ""
    private var suggestionTask: Task<Void, Never>?

    func applicationDidFinishLaunching(_ notification: Notification) {
        setupMenuBar()

        let trusted = PermissionsManager.isAccessibilityTrusted(prompt: true)
        NSLog("Inkling: launched. accessibilityTrusted=\(trusted)")
        guard trusted else {
            NSLog("Inkling: NOT trusted — grant Accessibility, then relaunch.")
            return
        }

        eventTap.onKeyDown = { [weak self] in self?.onKeyDown() }
        eventTap.onAccept = { [weak self] in DispatchQueue.main.async { self?.acceptNextWord() } }
        eventTap.onDismiss = { [weak self] in DispatchQueue.main.async { self?.dismiss() } }

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
                                action: #selector(NSApplication.terminate(_:)),
                                keyEquivalent: "q"))
        item.menu = menu
        statusItem = item
    }

    /// A non-accept keystroke: hide the stale suggestion immediately (dismiss on
    /// type), then debounce a fresh request so we only query after a pause.
    private func onKeyDown() {
        DispatchQueue.main.async { [weak self] in
            guard let self else { return }
            self.dismiss()
            self.debouncer.schedule { [weak self] in self?.refreshSuggestion() }
        }
    }

    private func dismiss() {
        suggestionTask?.cancel()
        overlay.hide()
        eventTap.suggestionVisible = false
        currentSuggestion = ""
    }

    private func refreshSuggestion() {
        guard let readout = FocusContextProvider.currentReadout() else {
            NSLog("Inkling: AX readout = nil")
            dismiss()
            return
        }
        guard let bounds = readout.caretBounds else {
            NSLog("Inkling: caretBounds = nil (caret=\(readout.caretIndex))")
            dismiss()
            return
        }
        let context = TextContext(fullText: readout.text, caretIndex: readout.caretIndex)
        let font = readout.font
        suggestionTask?.cancel()
        suggestionTask = Task { [weak self] in
            guard let engine = self?.engine else { return }
            let suggestion = await engine.suggestion(for: context)
            if Task.isCancelled { return }
            await MainActor.run { [weak self] in
                guard let self else { return }
                guard !suggestion.isEmpty else { self.dismiss(); return }
                self.currentSuggestion = suggestion
                self.overlay.show(text: suggestion, caretBounds: bounds, font: font)
                self.eventTap.suggestionVisible = true
                NSLog("Inkling: showing \"\(suggestion)\"")
            }
        }
    }

    /// Tab inserts the next word; the rest of the SAME suggestion stays shown as
    /// ghost text (re-anchored at the new caret) so word-by-word accept doesn't
    /// re-query and change the completion. Our inserted keystrokes are tagged and
    /// ignored by the event tap, so they don't trigger a fresh query.
    private func acceptNextWord() {
        let split = SuggestionSplitter.nextChunk(of: currentSuggestion)
        guard !split.chunk.isEmpty else { dismiss(); return }
        overlay.hide()
        eventTap.suggestionVisible = false
        currentSuggestion = ""
        TextInserter.insert(split.chunk)
        NSLog("Inkling: accepted \"\(split.chunk)\"")

        let remainder = split.remainder
        guard !remainder.isEmpty else { return }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) { [weak self] in
            guard let self else { return }
            guard let readout = FocusContextProvider.currentReadout(),
                  let bounds = readout.caretBounds else { return }
            self.currentSuggestion = remainder
            self.overlay.show(text: remainder, caretBounds: bounds, font: readout.font)
            self.eventTap.suggestionVisible = true
        }
    }
}
