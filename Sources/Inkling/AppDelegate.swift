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
    private let inputStore = InputStore.shared
    private lazy var inputCollector = InputCollector(
        store: inputStore,
        isCollecting: { [weak self] in self?.settings.state.global.collectInputs ?? false },
        storeWithoutAccepted: { [weak self] in self?.settings.state.global.storeWithoutAccepted ?? true })
    private enum SuggestionSource { case none, memory, llm, correction }
    private var suggestionSource: SuggestionSource = .none
    /// True when the currently-shown memory suggestion was an exact word-repeat
    /// (trusted over the LLM). Meaningful only while `suggestionSource == .memory`.
    private var memoryExactRepeat = false
    /// True while the user is accepting the current suggestion word-by-word; the
    /// LLM result must not swap the ghost text out from under them.
    private var accepting = false
    private let statsStore = CompletionEventStore.shared
    /// True when the next accept is the FIRST chunk of the currently-shown
    /// suggestion — set on every fresh show, consumed on the first accept.
    private var firstChunkPending = false
    /// True while the currently-shown suggestion is mid-line (text follows the
    /// caret), so the overlay draws a background pill. Retained across word-by-
    /// word accept; reset on dismiss.
    private var suggestionMidLine = false
    /// Pure current-word typo-correction policy; the system spell checker backs it.
    private let autocorrector = Autocorrector(
        checker: SystemSpellChecker(),
        isRealWord: { WordCompleteness.isDictionaryWord($0) })
    /// The correction currently offered (source == .correction); nil otherwise.
    private var currentCorrection: Correction?

    func applicationDidFinishLaunching(_ notification: Notification) {
        setupMenuBar()

        NotificationCenter.default.addObserver(
            forName: .inklingModelChanged, object: nil, queue: .main
        ) { [weak self] _ in
            self?.reloadEngine()
        }

        NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.didActivateApplicationNotification, object: nil, queue: .main
        ) { [weak self] _ in
            self?.inputCollector.onAppSwitched()
        }
        NotificationCenter.default.addObserver(
            forName: .inklingClearLearnedData, object: nil, queue: .main
        ) { [weak self] _ in
            self?.clearLearned()
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

        // Inputs are the source of truth: rebuild the derived model from them.
        // memory.json remains a warm cache written by live learning.
        MemoryRebuilder.rebuild(from: inputStore.allRecords(), into: memory)
        memory.decay()   // fade + bound once per launch

        recorder.onWord = { [weak self] word, context in
            guard let self, self.settings.state.global.collectInputs else { return }
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
                self.inputCollector.onKeystroke()
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
        inputCollector.endCurrentSession()
        inputStore.saveNow()
        statsStore.saveNow()
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
        pause.state = settings.state.global.collectInputs ? .off : .on
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
        settings.state.global.collectInputs.toggle()
        NSLog("Inkling: collectInputs=\(settings.state.global.collectInputs)")
        rebuildMenu()
    }

    @objc private func clearLearned() {
        inputCollector.discardCurrentSession()   // in-flight text is part of what's being erased
        inputStore.deleteAll()   // canonical typing history
        memoryStore.clear()      // derived model + cache
        recorder.reset()
        NSLog("Inkling: cleared typing history + learned data")
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
            let bundleID = FrontmostApp.bundleID
            let completionsOn = EffectiveSettings.completionsEnabled(
                state: self.settings.state, bundleID: bundleID)
            let autocorrectOn = self.autocorrectActive(bundleID: bundleID)
            guard completionsOn || autocorrectOn else { return }
            // Tier 1 (instant memory) only when completions are on; corrections
            // wait for the debounce (a typing pause = "done with this word").
            if completionsOn { _ = self.tryMemorySuggestion() }
            self.debouncer.schedule { [weak self] in self?.refreshSuggestion() }
        }
    }

    /// Autocorrect runs when the master switch and the per-app autocorrect gate
    /// are both on — independent of the per-app completions toggle.
    private func autocorrectActive(bundleID: String?) -> Bool {
        settings.state.global.enabled
            && EffectiveSettings.autocorrectEnabled(state: settings.state, bundleID: bundleID)
    }

    /// Synchronous deterministic completion from the recorder buffer. Returns
    /// true (and shows ghost text) when memory is confident AND the live field
    /// agrees with the buffer; false otherwise.
    private func tryMemorySuggestion() -> Bool {
        guard let gates = MemoryEngine.gates(forLevel: settings.state.global.personalizeLevel)
        else { return false }
        guard let hit = MemoryEngine.hit(
            currentWord: recorder.currentWord,
            precedingWords: recorder.recentWords,
            memory: memory,
            gates: gates
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
        let midLineOK = EffectiveSettings.midLineEnabled(
            state: settings.state, bundleID: FrontmostApp.bundleID)
        guard SuggestionSync.consistent(recorded: recorder.currentWord, live: ctx.currentWord),
              ctx.isAtLineEnd || midLineOK else {
            NSLog("Inkling: memory skip rec=\"\(recorder.currentWord)\" ax=\"\(ctx.currentWord)\" lineEnd=\(ctx.isAtLineEnd)")
            return false
        }
        // Mid-line: don't offer a completion that just restates what follows the
        // caret (it would duplicate on accept). `suffix` here is the completion
        // text; `ctx.lineSuffix` is the trailing document text.
        if !ctx.isAtLineEnd,
           SuffixRestateGuard.restates(continuation: suffix, suffix: ctx.lineSuffix) {
            return false
        }
        suggestionMidLine = !ctx.isAtLineEnd

        settings.recordSuggestionShown(bundleID: FrontmostApp.bundleID, appName: FrontmostApp.name)
        firstChunkPending = true
        suggestionSource = .memory
        memoryExactRepeat = hit.isExactRepeat
        currentSuggestion = suffix
        overlay.show(text: suffix, caretBounds: bounds, font: readout.font, background: suggestionMidLine)
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
        firstChunkPending = false
        suggestionMidLine = false
        currentCorrection = nil
    }

    /// Show the corrected word as a tinted pill at the caret (source .correction).
    private func showCorrection(_ correction: Correction, bounds: CGRect, font: NSFont?) {
        settings.recordSuggestionShown(bundleID: FrontmostApp.bundleID, appName: FrontmostApp.name)
        firstChunkPending = true
        suggestionSource = .correction
        memoryExactRepeat = false
        suggestionMidLine = false
        currentCorrection = correction
        currentSuggestion = correction.replacement
        overlay.show(text: correction.replacement, caretBounds: bounds, font: font, correction: true)
        eventTap.suggestionVisible = true
        NSLog("Inkling: correction \"\(correction.original)\" -> \"\(correction.replacement)\"")
    }

    private func refreshSuggestion() {
        // Focus may have moved to an excluded app during the debounce window.
        let bundleID = FrontmostApp.bundleID
        let completionsOn = EffectiveSettings.completionsEnabled(state: settings.state, bundleID: bundleID)
        let autocorrectOn = autocorrectActive(bundleID: bundleID)
        guard completionsOn || autocorrectOn else { dismiss(); return }
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
        // Mid-line suggestions are allowed when enabled for this app; otherwise
        // line-end only (mid-line ghost text would overlap what follows).
        let midLineOK = EffectiveSettings.midLineEnabled(
            state: settings.state, bundleID: FrontmostApp.bundleID)
        guard context.isAtLineEnd || midLineOK else {
            if suggestionSource != .memory { dismiss() }
            return
        }
        let font = readout.font
        // Current-word typo correction (independent of the completions gate).
        let correction: Correction? = autocorrectOn
            ? autocorrector.correction(for: context.currentWord, memory: memory)
            : nil
        // Autocorrect-only app (completions off): no LLM tier — show the
        // correction if there is one, otherwise nothing.
        guard completionsOn else {
            if let correction { showCorrection(correction, bounds: bounds, font: font) }
            else { dismiss() }
            return
        }
        // Whether the word under the caret is a complete DICTIONARY word. The
        // raw-continuation engine uses this to decide mid-word backup (finish
        // the word first); deliberately dictionary-only — memory jargon like
        // "impl" must still be completed, not continued past.
        let currentWordIsComplete = WordCompleteness.isDictionaryWord(context.currentWord)
        // Custom instructions steer the LLM only when the experimental flag is on
        // (default off). Resolved on the main actor; passed into the engine.
        let instructions: String? = settings.state.global.instructionPreambleEnabled
            ? EffectiveSettings.customInstructions(
                state: settings.state, bundleID: FrontmostApp.bundleID)
            : nil
        suggestionTask?.cancel()
        suggestionTask = Task { [weak self] in
            guard let engine = self?.engine else { return }
            // Personalization is deterministic (the memory tier above), NOT a
            // frequent-vocab hint injected into the LLM prompt — that made the
            // model regurgitate those words instead of continuing (commit a8e524e).
            let raw = await engine.suggestion(
                for: context, currentWordIsComplete: currentWordIsComplete,
                instructions: instructions)
            if Task.isCancelled { return }
            // Mid-line: drop a continuation that restates the text after the caret.
            let suggestion = (!context.isAtLineEnd
                && SuffixRestateGuard.restates(continuation: raw, suffix: context.lineSuffix))
                ? "" : raw
            await MainActor.run { [weak self] in
                guard let self else { return }
                let shown: ShownSuggestion
                switch self.suggestionSource {
                case .none: shown = .none
                case .memory: shown = .memory(exactRepeat: self.memoryExactRepeat)
                case .llm: shown = .llm
                case .correction: shown = .none
                }
                switch SuggestionArbiter.decide(
                    shown: shown, visibleText: self.currentSuggestion,
                    llmSuggestion: suggestion, accepting: self.accepting
                ) {
                case .keep:
                    return
                case .dismiss:
                    // Completion tiers declined — fall back to a correction if one
                    // is available and nothing else is on screen.
                    if let correction, self.suggestionSource == .none,
                       !context.currentWord.isEmpty {
                        self.showCorrection(correction, bounds: bounds, font: font)
                    } else {
                        self.dismiss()
                    }
                case .replaceWithLLM:
                    // Count new shows only — an LLM upgrade of a visible memory
                    // suggestion was already counted when the memory tier showed.
                    if self.suggestionSource == .none {
                        self.settings.recordSuggestionShown(
                            bundleID: FrontmostApp.bundleID, appName: FrontmostApp.name)
                    }
                    self.firstChunkPending = true
                    self.suggestionSource = .llm
                    self.memoryExactRepeat = false
                    self.suggestionMidLine = !context.isAtLineEnd
                    self.currentSuggestion = suggestion
                    self.overlay.show(text: suggestion, caretBounds: bounds, font: font,
                                      background: self.suggestionMidLine)
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
        if suggestionSource == .correction, let correction = currentCorrection {
            applyCorrection(correction)
            return
        }
        inputCollector.noteAccepted()
        accepting = true
        let split = SuggestionSplitter.nextChunk(of: currentSuggestion)
        guard !split.chunk.isEmpty else { dismiss(); return }
        overlay.hide()
        eventTap.suggestionVisible = false
        currentSuggestion = ""
        TextInserter.insert(split.chunk)
        NSLog("Inkling: accepted \"\(split.chunk)\"")
        statsStore.record(CompletionEvent(
            timestamp: Date(), appBundleID: FrontmostApp.bundleID,
            words: 1, chars: split.chunk.count, isFirstChunk: firstChunkPending))
        firstChunkPending = false

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
            self.overlay.show(text: remainder, caretBounds: bounds, font: readout.font,
                              background: self.suggestionMidLine)
            self.eventTap.suggestionVisible = true
        }
    }

    /// Accepting a correction is atomic: re-validate the live word still matches,
    /// then delete it and type the replacement. No word-by-word cycling.
    private func applyCorrection(_ correction: Correction) {
        inputCollector.noteAccepted()
        guard let readout = FocusContextProvider.currentReadout() else { dismiss(); return }
        let ctx = TextContext(fullText: readout.text, caretIndex: readout.caretIndex)
        guard ctx.currentWord == correction.original else { dismiss(); return }
        overlay.hide()
        eventTap.suggestionVisible = false
        TextInserter.replace(deleting: correction.original.count, insert: correction.replacement)
        NSLog("Inkling: applied correction \"\(correction.original)\" -> \"\(correction.replacement)\"")
        statsStore.record(CompletionEvent(
            timestamp: Date(), appBundleID: FrontmostApp.bundleID,
            words: 1, chars: correction.replacement.count, isFirstChunk: firstChunkPending))
        firstChunkPending = false
        dismiss()
    }
}

extension AppDelegate: NSMenuDelegate {
    /// Called each time the status menu is about to open; rebuild so
    /// checkmarks reflect changes made in the settings window.
    func menuNeedsUpdate(_ menu: NSMenu) {
        rebuildMenu()
    }
}
