import XCTest
@testable import Core

final class ClipBasketEngineTests: XCTestCase {
    private func item(_ text: String, id: UUID = UUID()) -> ClipBasketItem {
        ClipBasketItem(id: id, content: .text(RichPasteboardPayload(plainText: text)))
    }

    func testFIFOEnqueueAndPop() {
        var engine = ClipBasketEngine()
        engine.enqueue(item("first"))
        engine.enqueue(item("second"))
        engine.enqueue(item("third"))

        XCTAssertEqual(engine.count, 3)
        XCTAssertEqual(engine.popNext()?.content.plainText, "first")
        XCTAssertEqual(engine.popNext()?.content.plainText, "second")
        XCTAssertEqual(engine.popNext()?.content.plainText, "third")
        XCTAssertNil(engine.popNext())
    }

    func testLIFOEnqueueAndPop() {
        var engine = ClipBasketEngine(order: .lifo)
        engine.enqueue(item("first"))
        engine.enqueue(item("second"))
        engine.enqueue(item("third"))

        XCTAssertEqual(engine.popNext()?.content.plainText, "third")
        XCTAssertEqual(engine.popNext()?.content.plainText, "second")
        XCTAssertEqual(engine.popNext()?.content.plainText, "first")
    }

    func testConsecutiveDuplicatesArePreserved() {
        var engine = ClipBasketEngine()
        engine.enqueue(item("repeat"))
        engine.enqueue(item("repeat"))
        engine.enqueue(item("repeat"))

        XCTAssertEqual(engine.count, 3)
        XCTAssertEqual(engine.popNext()?.content.plainText, "repeat")
        XCTAssertEqual(engine.popNext()?.content.plainText, "repeat")
        XCTAssertEqual(engine.popNext()?.content.plainText, "repeat")
    }

    func testReverseTogglesOrderAndReversesItems() {
        var engine = ClipBasketEngine()
        engine.enqueue(item("a"))
        engine.enqueue(item("b"))
        engine.enqueue(item("c"))

        engine.reverse()
        XCTAssertEqual(engine.order, .lifo)
        XCTAssertEqual(engine.items.map(\.content.plainText), ["c", "b", "a"])

        engine.reverse()
        XCTAssertEqual(engine.order, .fifo)
        XCTAssertEqual(engine.items.map(\.content.plainText), ["a", "b", "c"])
    }

    func testEnqueueSplitHandlesNewlinesAndBlankLines() {
        var engine = ClipBasketEngine()
        let added = engine.enqueueSplit("one\r\n\r\n  two  \n   \nthree")

        XCTAssertEqual(added, 3)
        XCTAssertEqual(engine.items.map(\.content.plainText), ["one", "two", "three"])
    }

    func testEnqueueSplitIgnoresWhitespaceOnlyInput() {
        var engine = ClipBasketEngine()
        let added = engine.enqueueSplit(" \n\t\r\n  ")

        XCTAssertEqual(added, 0)
        XCTAssertTrue(engine.isEmpty)
    }

    func testUndoRestoresPoppedItemsAtTheFrontInOrder() {
        var engine = ClipBasketEngine()
        engine.enqueue(item("a"))
        engine.enqueue(item("b"))
        engine.enqueue(item("c"))

        _ = engine.popNext()
        _ = engine.popNext()
        XCTAssertEqual(engine.items.map(\.content.plainText), ["c"])

        _ = engine.undo()
        XCTAssertEqual(engine.items.map(\.content.plainText), ["b", "c"])
        _ = engine.undo()
        XCTAssertEqual(engine.items.map(\.content.plainText), ["a", "b", "c"])
        XCTAssertFalse(engine.canUndo)
    }

    func testUndoRestoresDeletedItemAtOriginalIndex() {
        var engine = ClipBasketEngine()
        engine.enqueue(item("a"))
        let middle = item("b")
        engine.enqueue(middle)
        engine.enqueue(item("c"))

        _ = engine.pop(id: middle.id)
        XCTAssertEqual(engine.items.map(\.content.plainText), ["a", "c"])

        _ = engine.undo()
        XCTAssertEqual(engine.items.map(\.content.plainText), ["a", "b", "c"])
    }

    func testMoveFromOffsetsReorders() {
        var engine = ClipBasketEngine()
        ["a", "b", "c", "d"].forEach { engine.enqueue(item($0)) }

        engine.move(fromOffsets: IndexSet(integer: 1), toOffset: 3)
        XCTAssertEqual(engine.items.map(\.content.plainText), ["a", "c", "b", "d"])

        engine.move(fromOffsets: IndexSet(integer: 3), toOffset: 0)
        XCTAssertEqual(engine.items.map(\.content.plainText), ["d", "a", "c", "b"])
    }

    func testMoveByIDMovesToFinalIndex() {
        var engine = ClipBasketEngine()
        let b = item("b")
        engine.enqueue(item("a"))
        engine.enqueue(b)
        engine.enqueue(item("c"))

        engine.move(id: b.id, toIndex: 2)
        XCTAssertEqual(engine.items.map(\.content.plainText), ["a", "c", "b"])

        engine.move(id: b.id, toIndex: 0)
        XCTAssertEqual(engine.items.map(\.content.plainText), ["b", "a", "c"])
    }

    func testJoinedTextFormats() {
        var engine = ClipBasketEngine()
        engine.enqueue(item("one"))
        engine.enqueue(item("two"))
        engine.enqueue(item("three"))

        XCTAssertEqual(engine.joinedText(format: .newline), "one\ntwo\nthree")
        XCTAssertEqual(engine.joinedText(format: .doubleNewline), "one\n\ntwo\n\nthree")
        XCTAssertEqual(engine.joinedText(format: .space), "one two three")
        XCTAssertEqual(engine.joinedText(format: .comma), "one, two, three")
        XCTAssertEqual(engine.joinedText(format: .bulletList), "• one\n• two\n• three")
        XCTAssertEqual(engine.joinedText(format: .numberedList), "1. one\n2. two\n3. three")
    }

    func testJoinedTextSkipsMediaAndUsesCurrentOrder() {
        var engine = ClipBasketEngine()
        engine.enqueue(item("one"))
        engine.enqueue(ClipBasketItem(content: .files([URL(fileURLWithPath: "/tmp/a.txt")])))
        engine.enqueue(item("two"))

        XCTAssertEqual(engine.joinedText(), "one\ntwo")

        engine.reverse()
        XCTAssertEqual(engine.joinedText(), "two\none")
    }

    func testJoinedTextReturnsNilWithoutTextItems() {
        var engine = ClipBasketEngine()
        engine.enqueue(ClipBasketItem(content: .image(data: Data([0x89]), uti: "public.png", pixelWidth: 1, pixelHeight: 1)))

        XCTAssertNil(engine.joinedText())
    }

    func testClearDropsItemsAndUndoHistory() {
        var engine = ClipBasketEngine()
        engine.enqueue(item("a"))
        engine.enqueue(item("b"))
        _ = engine.popNext()
        engine.setCommandVArmed(true)

        engine.clear()

        XCTAssertTrue(engine.isEmpty)
        XCTAssertFalse(engine.canUndo)
        XCTAssertFalse(engine.isCommandVArmed)
        XCTAssertNil(engine.undo())
    }

    func testCommandVArmedRequiresOpenAndItems() {
        var engine = ClipBasketEngine()
        engine.setCommandVArmed(true)
        XCTAssertFalse(engine.isCommandVArmed)

        engine.setOpen(true)
        engine.setCommandVArmed(true)
        XCTAssertFalse(engine.isCommandVArmed)

        engine.enqueue(item("a"))
        engine.setCommandVArmed(true)
        XCTAssertTrue(engine.isCommandVArmed)

        engine.setOpen(false)
        XCTAssertFalse(engine.isCommandVArmed)
    }

    func testArmedPasteDisarmsWhenItemsRunOut() {
        var engine = ClipBasketEngine(isOpen: true)
        engine.enqueue(item("a"))
        engine.setCommandVArmed(true)
        XCTAssertTrue(engine.isCommandVArmed)

        _ = engine.popNext()
        XCTAssertFalse(engine.isCommandVArmed)
    }

    func testEnqueueRejectsBeyondItemLimit() {
        var engine = ClipBasketEngine(maximumItems: 2)
        XCTAssertTrue(engine.enqueue(item("a")))
        XCTAssertTrue(engine.enqueue(item("b")))
        XCTAssertFalse(engine.enqueue(item("c")))
        XCTAssertEqual(engine.count, 2)
    }

    func testEnqueueRejectsBeyondByteBudget() {
        var engine = ClipBasketEngine(maximumTotalBytes: 10)
        XCTAssertTrue(engine.enqueue(item("123456")))
        XCTAssertFalse(engine.enqueue(item("12345")))
        XCTAssertEqual(engine.count, 1)
    }

    func testEnqueueSplitStopsAtItemLimit() {
        var engine = ClipBasketEngine(maximumItems: 2)
        let added = engine.enqueueSplit("a\nb\nc")

        XCTAssertEqual(added, 2)
        XCTAssertEqual(engine.items.map(\.content.plainText), ["a", "b"])
    }

    func testRemoveIDsPreservesOtherItemsAndUndo() {
        var engine = ClipBasketEngine()
        let text = item("text")
        let image = ClipBasketItem(content: .image(
            data: Data([0x89]),
            uti: "public.png",
            pixelWidth: 1,
            pixelHeight: 1
        ))
        engine.enqueue(text)
        engine.enqueue(image)

        engine.remove(ids: [text.id])

        XCTAssertEqual(engine.items.map(\.content), [image.content])
        XCTAssertTrue(engine.canUndo)
    }

    func testRestoreRollbackDoesNotLeaveAStaleUndoEntry() {
        var engine = ClipBasketEngine()
        let first = item("a")
        engine.enqueue(first)
        engine.enqueue(item("b"))

        let popped = engine.popNext()
        XCTAssertEqual(popped?.id, first.id)
        engine.restore(first, at: 0)

        XCTAssertEqual(engine.items.map(\.content.plainText), ["a", "b"])
        XCTAssertFalse(engine.canUndo)
    }
}
