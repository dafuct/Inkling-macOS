import XCTest
@testable import InklingCore

final class MemoryRecorderTests: XCTestCase {
    func test_commitsWordOnBoundary_withPrecedingContext() {
        let r = MemoryRecorder()
        var commits: [(String, [String])] = []
        r.onWord = { word, ctx in commits.append((word, ctx)) }
        r.append("hi there ")   // two words, each closed by a space
        XCTAssertEqual(commits.map { $0.0 }, ["hi", "there"])
        XCTAssertEqual(commits[0].1, [])         // "hi" had no preceding word
        XCTAssertEqual(commits[1].1, ["hi"])     // "there" preceded by "hi"
    }

    func test_currentWord_tracksPartialInput() {
        let r = MemoryRecorder()
        r.append("Mak")
        XCTAssertEqual(r.currentWord, "Mak")
        XCTAssertTrue(r.recentWords.isEmpty)
    }

    func test_doesNotCommitHalfTypedWord() {
        let r = MemoryRecorder()
        var commits: [String] = []
        r.onWord = { w, _ in commits.append(w) }
        r.append("hello")        // no boundary yet
        XCTAssertTrue(commits.isEmpty)
    }

    func test_backspaceEditsCurrentWord() {
        let r = MemoryRecorder()
        r.append("helo"); r.backspace(); r.append("lo")
        XCTAssertEqual(r.currentWord, "hello")
    }

    func test_recentWordsCappedAtTwo() {
        let r = MemoryRecorder()
        r.append("a b c d ")
        XCTAssertEqual(r.recentWords, ["c", "d"])
    }

    func test_resetClearsEverything() {
        let r = MemoryRecorder()
        r.append("a b ")
        r.reset()
        XCTAssertEqual(r.currentWord, "")
        XCTAssertTrue(r.recentWords.isEmpty)
    }

    func test_apostropheIsPartOfWord() {
        let r = MemoryRecorder()
        var commits: [String] = []
        r.onWord = { w, _ in commits.append(w) }
        r.append("don't ")
        XCTAssertEqual(commits, ["don't"])
    }
}
