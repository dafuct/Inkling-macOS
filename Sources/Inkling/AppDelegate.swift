import AppKit
import InklingCore

final class AppDelegate: NSObject, NSApplicationDelegate {
    private let eventTap = EventTapController()
    private let overlay = OverlayWindow()
    private var engine = MLXEngine(modelDirectory: ModelConfig.modelDirectory)
    private let debouncer = Debouncer(delay: 0.2)
    private var statusItem: NSStatusItem?
    private var currentSuggestion = ""
    private var suggestionTask: Task<Void, Never>?
    private let memory = PersonalMemory()
    private lazy var memoryStore = MemoryStore(memory: memory)
    private let recorder = MemoryRecorder()
    private enum SuggestionSource { case none, memory, llm }
    private var suggestionSource: SuggestionSource = .none

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

        memoryStore.load()
        memory.decay()   // fade + bound once per launch

        recorder.onWord = { [weak self] word, context in
            guard let self, Settings.learningEnabled else { return }
            guard !FocusContextProvider.isSecureFieldFocused() else { return }
            self.memory.learn(word: word, previous: context)
            self.memoryStore.scheduleSave()
        }
        eventTap.onType = { [weak self] s in
            DispatchQueue.main.async { self?.recorder.append(s) }
        }
        eventTap.onDelete = { [weak self] in
            DispatchQueue.main.async { self?.recorder.backspace() }
        }

        if eventTap.start() {
            NSLog("Inkling: event tap started.")
        } else {
            NSLog("Inkling: FAILED to create event tap — check Accessibility/Input Monitoring.")
        }

        Task { await engine.preload() }
        NSLog("Inkling: pre-warming model \(ModelConfig.currentModelName)")
    }

    func applicationWillTerminate(_ notification: Notification) {
        memoryStore.saveNow()
    }

    private func setupMenuBar() {
        let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        item.button?.title = "⌨︎"
        statusItem = item
        rebuildMenu()
    }

    private func rebuildMenu() {
        let menu = NSMenu()

        let toggle = NSMenuItem(
            title: "Suggestions Enabled", action: #selector(toggleEnabled), keyEquivalent: "")
        toggle.target = self
        toggle.state = Settings.enabled ? .on : .off
        menu.addItem(toggle)

        menu.addItem(.separator())
        let header = NSMenuItem(title: "Model", action: nil, keyEquivalent: "")
        header.isEnabled = false
        menu.addItem(header)
        for name in ModelCatalog.availableModels(in: ModelConfig.modelsRoot) {
            let mi = NSMenuItem(title: name, action: #selector(selectModel(_:)), keyEquivalent: "")
            mi.target = self
            mi.representedObject = name
            mi.state = (name == ModelConfig.currentModelName) ? .on : .off
            menu.addItem(mi)
        }

        menu.addItem(.separator())
        let pause = NSMenuItem(
            title: "Pause learning", action: #selector(toggleLearning), keyEquivalent: "")
        pause.target = self
        pause.state = Settings.learningEnabled ? .off : .on
        menu.addItem(pause)
        let clear = NSMenuItem(
            title: "Clear learned data", action: #selector(clearLearned), keyEquivalent: "")
        clear.target = self
        menu.addItem(clear)

        menu.addItem(.separator())
        menu.addItem(NSMenuItem(
            title: "Quit Inkling", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q"))

        statusItem?.menu = menu
    }

    @objc private func toggleEnabled() {
        Settings.enabled.toggle()
        if !Settings.enabled { dismiss() }
        NSLog("Inkling: enabled=\(Settings.enabled)")
        rebuildMenu()
    }

    @objc private func toggleLearning() {
        Settings.learningEnabled.toggle()
        NSLog("Inkling: learningEnabled=\(Settings.learningEnabled)")
        rebuildMenu()
    }

    @objc private func clearLearned() {
        memoryStore.clear()
        recorder.reset()
        NSLog("Inkling: cleared learned data")
    }

    @objc private func selectModel(_ sender: NSMenuItem) {
        guard let name = sender.representedObject as? String, name != ModelConfig.currentModelName
        else { return }
        Settings.selectedModel = name
        dismiss()
        engine = MLXEngine(modelDirectory: ModelConfig.directory(for: name))
        Task { await engine.preload() }
        NSLog("Inkling: switched model to \(name)")
        rebuildMenu()
    }

    /// A non-accept keystroke: hide the stale suggestion immediately (dismiss on
    /// type), then debounce a fresh request so we only query after a pause.
    private func onKeyDown() {
        DispatchQueue.main.async { [weak self] in
            guard let self else { return }
            self.dismiss()
            guard Settings.enabled else { return }
            if self.tryMemorySuggestion() { return }   // shown instantly; LLM not needed
            self.debouncer.schedule { [weak self] in self?.refreshSuggestion() }
        }
    }

    /// Synchronous deterministic completion from the recorder buffer. Returns
    /// true (and shows ghost text) when memory is confident AND the live field
    /// agrees with the buffer; false otherwise.
    private func tryMemorySuggestion() -> Bool {
        guard let suffix = MemoryEngine.completion(
            currentWord: recorder.currentWord,
            precedingWords: recorder.recentWords,
            memory: memory
        ), !suffix.isEmpty else { return false }

        // Validate against the real field so a desynced buffer can't show a wrong
        // completion (this AX read happens only on a memory hit). currentReadout()
        // returns nil for secure/non-text fields, so those are excluded here too.
        guard let readout = FocusContextProvider.currentReadout(),
              let bounds = readout.caretBounds else { return false }
        let ctx = TextContext(fullText: readout.text, caretIndex: readout.caretIndex)
        guard ctx.currentWord == recorder.currentWord else { return false }

        suggestionSource = .memory
        currentSuggestion = suffix
        overlay.show(text: suffix, caretBounds: bounds, font: readout.font)
        eventTap.suggestionVisible = true
        NSLog("Inkling: memory \"\(suffix)\"")
        return true
    }

    private func dismiss() {
        suggestionTask?.cancel()
        overlay.hide()
        eventTap.suggestionVisible = false
        currentSuggestion = ""
        suggestionSource = .none
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
        if !context.prefix.hasSuffix(recorder.currentWord) || recorder.currentWord.isEmpty && !context.currentWord.isEmpty {
            recorder.reset()
        }
        let font = readout.font
        suggestionTask?.cancel()
        suggestionTask = Task { [weak self] in
            guard let engine = self?.engine else { return }
            let suggestion = await engine.suggestion(for: context)
            if Task.isCancelled { return }
            await MainActor.run { [weak self] in
                guard let self else { return }
                guard self.suggestionSource != .memory else { return }   // memory wins
                guard !suggestion.isEmpty else { self.dismiss(); return }
                self.suggestionSource = .llm
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
