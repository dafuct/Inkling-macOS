import AppKit
import InklingCore

final class AppDelegate: NSObject, NSApplicationDelegate {
    private let eventTap = EventTapController()
    private let settings = SettingsStore.shared
    private let settingsWindow = SettingsWindowController()
    private let overlay = OverlayWindow()
    private var engine = MLXEngine(modelDirectory: ModelConfig.modelDirectory)
    private let debouncer = Debouncer(delay: ModelConfig.suggestionDebounceSeconds)
    private var statusItem: NSStatusItem?
    private var currentSuggestion = ""
    private var suggestionTask: Task<Void, Never>?
    private let memory = PersonalMemory()
    private lazy var memoryStore = MemoryStore(memory: memory)
    private let recorder = MemoryRecorder()
    private enum SuggestionSource { case none, memory, llm }
    private var suggestionSource: SuggestionSource = .none
    /// True when the currently-shown memory suggestion was an exact word-repeat
    /// (trusted over the LLM). Meaningful only while `suggestionSource == .memory`.
    private var memoryExactRepeat = false
    /// True while the user is accepting the current suggestion word-by-word; the
    /// LLM result must not swap the ghost text out from under them.
    private var accepting = false

    func applicationDidFinishLaunching(_ notification: Notification) {
        setupMenuBar()

        NotificationCenter.default.addObserver(
            forName: .inklingModelChanged, object: nil, queue: .main
        ) { [weak self] _ in
            self?.reloadEngine()
        }

        let trusted = PermissionsManager.isAccessibilityTrusted(prompt: true)
        NSLog("Inkling: launched. accessibilityTrusted=\(trusted)")
        guard trusted else {
            NSLog("Inkling: NOT trusted — grant Accessibility, then relaunch.")
            return
        }

        eventTap.onKeyDown = { [weak self] in self?.onKeyDown() }
        eventTap.onAccept = { [weak self] in DispatchQueue.main.async { self?.acceptNextWord() } }
        eventTap.onDismiss = { [weak self] in DispatchQueue.main.async { self?.dismiss() } }
        eventTap.shouldSwallowAccept = { [weak self] in
            guard let self else { return true }
            return EffectiveSettings.acceptKeyEnabled(
                state: self.settings.state, bundleID: FrontmostApp.bundleID)
        }

        memoryStore.load()
        memory.decay()   // fade + bound once per launch

        recorder.onWord = { [weak self] word, context in
            guard let self, self.settings.state.global.learningEnabled else { return }
            guard !FocusContextProvider.isSecureFieldFocused() else { return }
            self.memory.learn(word: word, previous: context)
            self.memoryStore.scheduleSave()
        }
        eventTap.onType = { [weak self] s in
            DispatchQueue.main.async {
                guard let self else { return }
                // Capture-time secure-field gate: never buffer characters typed
                // into a password field, and drop any partial word carried in, so
                // a secret can't survive in the buffer and be committed/learned
                // after focus later moves to a normal field.
                if FocusContextProvider.isSecureFieldFocused() {
                    self.recorder.reset()
                    return
                }
                self.recorder.append(s)
            }
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
        settings.saveNow()
    }

    private func setupMenuBar() {
        let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        item.button?.image = MenuBarIcon.image()
        statusItem = item
        rebuildMenu()
    }

    private func rebuildMenu() {
        let menu = NSMenu()
        menu.delegate = self

        let toggle = NSMenuItem(
            title: "Suggestions Enabled", action: #selector(toggleEnabled), keyEquivalent: "")
        toggle.target = self
        toggle.state = settings.state.global.enabled ? .on : .off
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
        pause.state = settings.state.global.learningEnabled ? .off : .on
        menu.addItem(pause)
        let clear = NSMenuItem(
            title: "Clear learned data", action: #selector(clearLearned), keyEquivalent: "")
        clear.target = self
        menu.addItem(clear)

        menu.addItem(.separator())
        let settingsItem = NSMenuItem(
            title: "Settings…", action: #selector(openSettings), keyEquivalent: ",")
        settingsItem.target = self
        menu.addItem(settingsItem)

        menu.addItem(.separator())
        menu.addItem(NSMenuItem(
            title: "Quit Inkling", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q"))

        statusItem?.menu = menu
    }

    @objc private func openSettings() {
        settingsWindow.show()
    }

    @objc private func toggleEnabled() {
        settings.state.global.enabled.toggle()
        if !settings.state.global.enabled { dismiss() }
        NSLog("Inkling: enabled=\(settings.state.global.enabled)")
        rebuildMenu()
    }

    @objc private func toggleLearning() {
        settings.state.global.learningEnabled.toggle()
        NSLog("Inkling: learningEnabled=\(settings.state.global.learningEnabled)")
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
        settings.state.global.selectedModel = name
        reloadEngine()
        rebuildMenu()
    }

    /// Swap the engine to the currently selected model and pre-warm it.
    private func reloadEngine() {
        dismiss()
        engine = MLXEngine(modelDirectory: ModelConfig.modelDirectory)
        Task { await engine.preload() }
        NSLog("Inkling: switched model to \(ModelConfig.currentModelName)")
    }

    /// A non-accept keystroke: hide the stale suggestion immediately (dismiss on
    /// type), then debounce a fresh request so we only query after a pause.
    private func onKeyDown() {
        DispatchQueue.main.async { [weak self] in
            guard let self else { return }
            self.dismiss()
            guard EffectiveSettings.completionsEnabled(
                state: self.settings.state, bundleID: FrontmostApp.bundleID) else { return }
            // Tier 1: show an instant memory suggestion if we have one — but do
            // NOT return. Tier 2 (the LLM) still runs and may upgrade it.
            _ = self.tryMemorySuggestion()
            self.debouncer.schedule { [weak self] in self?.refreshSuggestion() }
        }
    }

    /// Synchronous deterministic completion from the recorder buffer. Returns
    /// true (and shows ghost text) when memory is confident AND the live field
    /// agrees with the buffer; false otherwise.
    private func tryMemorySuggestion() -> Bool {
        guard let hit = MemoryEngine.hit(
            currentWord: recorder.currentWord,
            precedingWords: recorder.recentWords,
            memory: memory
        ), !hit.text.isEmpty else { return false }
        let suffix = hit.text

        // Validate against the real field so a desynced buffer can't show a wrong
        // completion (this AX read happens only on a memory hit). currentReadout()
        // returns nil for secure/non-text fields, so those are excluded here too.
        guard let readout = FocusContextProvider.currentReadout(),
              let bounds = readout.caretBounds else { return false }
        let ctx = TextContext(fullText: readout.text, caretIndex: readout.caretIndex)
        // The tap is AHEAD of the AX value (it sees keys before the app inserts
        // them), so require consistency, not exact equality — else word completion
        // never fires. Only at line end: mid-line ghost text would overlap.
        guard SuggestionSync.consistent(recorded: recorder.currentWord, live: ctx.currentWord),
              ctx.isAtLineEnd else {
            NSLog("Inkling: memory skip rec=\"\(recorder.currentWord)\" ax=\"\(ctx.currentWord)\" lineEnd=\(ctx.isAtLineEnd)")
            return false
        }

        settings.recordSuggestionShown(bundleID: FrontmostApp.bundleID, appName: FrontmostApp.name)
        suggestionSource = .memory
        memoryExactRepeat = hit.isExactRepeat
        currentSuggestion = suffix
        overlay.show(text: suffix, caretBounds: bounds, font: readout.font)
        eventTap.suggestionVisible = true
        NSLog("Inkling: memory \"\(suffix)\" for \"\(recorder.currentWord)\"")
        return true
    }

    private func dismiss() {
        suggestionTask?.cancel()
        overlay.hide()
        eventTap.suggestionVisible = false
        currentSuggestion = ""
        suggestionSource = .none
        memoryExactRepeat = false
        accepting = false
    }

    private func refreshSuggestion() {
        // Focus may have moved to an excluded app during the debounce window.
        guard EffectiveSettings.completionsEnabled(
            state: settings.state, bundleID: FrontmostApp.bundleID) else {
            dismiss()
            return
        }
        // An instant memory suggestion (Tier 1) may already be on screen; the LLM
        // (Tier 2) refines it. On a transient AX-read failure or non-line-end, KEEP
        // a shown memory suggestion (it was AX-validated when shown) rather than
        // hiding it — the next keystroke dismisses it. Trade-off: a focus switch
        // within the debounce window can briefly leave it over the new app.
        guard let readout = FocusContextProvider.currentReadout() else {
            NSLog("Inkling: AX readout = nil")
            if suggestionSource != .memory { dismiss() }
            return
        }
        guard let bounds = readout.caretBounds else {
            NSLog("Inkling: caretBounds = nil (caret=\(readout.caretIndex))")
            if suggestionSource != .memory { dismiss() }
            return
        }
        let context = TextContext(fullText: readout.text, caretIndex: readout.caretIndex)
        if !context.prefix.hasSuffix(recorder.currentWord) || recorder.currentWord.isEmpty && !context.currentWord.isEmpty {
            recorder.reset()
        }
        // Only suggest at line end; mid-line ghost text would overlap what follows.
        guard context.isAtLineEnd else {
            if suggestionSource != .memory { dismiss() }
            return
        }
        let font = readout.font
        // Whether the word under the caret is a complete DICTIONARY word. The
        // raw-continuation engine uses this to decide mid-word backup (finish
        // the word first); deliberately dictionary-only — memory jargon like
        // "impl" must still be completed, not continued past.
        let currentWordIsComplete = WordCompleteness.isDictionaryWord(context.currentWord)
        suggestionTask?.cancel()
        suggestionTask = Task { [weak self] in
            guard let engine = self?.engine else { return }
            // Personalization is deterministic (the memory tier above), NOT a
            // frequent-vocab hint injected into the LLM prompt — that made the
            // model regurgitate those words instead of continuing (commit a8e524e).
            let suggestion = await engine.suggestion(
                for: context, currentWordIsComplete: currentWordIsComplete)
            if Task.isCancelled { return }
            await MainActor.run { [weak self] in
                guard let self else { return }
                let shown: ShownSuggestion
                switch self.suggestionSource {
                case .none: shown = .none
                case .memory: shown = .memory(exactRepeat: self.memoryExactRepeat)
                case .llm: shown = .llm
                }
                switch SuggestionArbiter.decide(
                    shown: shown, visibleText: self.currentSuggestion,
                    llmSuggestion: suggestion, accepting: self.accepting
                ) {
                case .keep:
                    return
                case .dismiss:
                    self.dismiss()
                case .replaceWithLLM:
                    // Count new shows only — an LLM upgrade of a visible memory
                    // suggestion was already counted when the memory tier showed.
                    if self.suggestionSource == .none {
                        self.settings.recordSuggestionShown(
                            bundleID: FrontmostApp.bundleID, appName: FrontmostApp.name)
                    }
                    self.suggestionSource = .llm
                    self.memoryExactRepeat = false
                    self.currentSuggestion = suggestion
                    self.overlay.show(text: suggestion, caretBounds: bounds, font: font)
                    self.eventTap.suggestionVisible = true
                    NSLog("Inkling: showing \"\(suggestion)\"")
                }
            }
        }
    }

    /// Tab inserts the next word; the rest of the SAME suggestion stays shown as
    /// ghost text (re-anchored at the new caret) so word-by-word accept doesn't
    /// re-query and change the completion. Our inserted keystrokes are tagged and
    /// ignored by the event tap, so they don't trigger a fresh query.
    private func acceptNextWord() {
        accepting = true
        let split = SuggestionSplitter.nextChunk(of: currentSuggestion)
        guard !split.chunk.isEmpty else { dismiss(); return }
        overlay.hide()
        eventTap.suggestionVisible = false
        currentSuggestion = ""
        TextInserter.insert(split.chunk)
        NSLog("Inkling: accepted \"\(split.chunk)\"")

        let remainder = split.remainder
        // Last word accepted. Intentionally leave `accepting` set: a late LLM
        // result from the pre-accept debounce must not paint over the finished
        // line. The next real keystroke calls dismiss(), which clears the lock.
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

extension AppDelegate: NSMenuDelegate {
    /// Called each time the status menu is about to open; rebuild so
    /// checkmarks reflect changes made in the settings window.
    func menuNeedsUpdate(_ menu: NSMenu) {
        rebuildMenu()
    }
}
