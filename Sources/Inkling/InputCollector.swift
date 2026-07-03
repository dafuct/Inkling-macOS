import ApplicationServices
import Foundation
import InklingCore

/// Captures one InputRecord per focus session. A session is the span the same
/// text element stays focused; it ends when focus moves to another element,
/// the frontmost app changes, or the user goes idle. At session end the field's
/// final text is snapshotted (from the retained element) and stored if the
/// session-decision logic and the collect toggle allow it.
final class InputCollector {
    private let store: InputStore
    private let isCollecting: () -> Bool
    private let storeWithoutAccepted: () -> Bool

    private var currentElement: AXUIElement?
    private var currentBundleID: String?
    private var session = InputSessionState()
    private var idleTimer: Timer?
    private let idleSeconds: TimeInterval = 30

    init(store: InputStore,
         isCollecting: @escaping () -> Bool,
         storeWithoutAccepted: @escaping () -> Bool) {
        self.store = store
        self.isCollecting = isCollecting
        self.storeWithoutAccepted = storeWithoutAccepted
    }

    /// Called on each real keystroke (main thread).
    func onKeystroke() {
        guard isCollecting() else { endCurrentSession(); return }
        let focused = FocusContextProvider.focusedElement()
        guard let focused else { endCurrentSession(); return }
        if let current = currentElement, CFEqual(current, focused) {
            // same session — nothing to do but keep it alive
        } else {
            endCurrentSession()
            currentElement = focused
            currentBundleID = FrontmostApp.bundleID
            session.reset()
        }
        restartIdleTimer()
    }

    /// A completion was accepted in the current session.
    func noteAccepted() { session.noteAccepted() }

    /// Frontmost app changed — the previous field's session is over.
    func onAppSwitched() { endCurrentSession() }

    /// Snapshot + store the current session (if worthy), then clear it.
    func endCurrentSession() {
        idleTimer?.invalidate()
        idleTimer = nil
        defer { currentElement = nil; currentBundleID = nil; session.reset() }
        guard let element = currentElement, isCollecting() else { return }
        guard let text = FocusContextProvider.text(of: element) else { return }
        guard session.shouldStore(text: text, storeWithoutAccepted: storeWithoutAccepted()) else { return }
        store.append(InputRecord(
            id: UUID(),
            timestamp: Date(),
            appBundleID: currentBundleID,
            text: text,
            hadAcceptedCompletion: session.hadAcceptedCompletion))
    }

    /// Abandon the current session WITHOUT storing it — used by Delete All,
    /// where the in-flight text is part of what the user asked to erase.
    func discardCurrentSession() {
        idleTimer?.invalidate()
        idleTimer = nil
        currentElement = nil
        currentBundleID = nil
        session.reset()
    }

    private func restartIdleTimer() {
        idleTimer?.invalidate()
        idleTimer = Timer.scheduledTimer(withTimeInterval: idleSeconds, repeats: false) { [weak self] _ in
            self?.endCurrentSession()
        }
    }
}
