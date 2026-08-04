import XCTest
@testable import TabFilerCore

final class DropHandlerTests: XCTestCase {
    func testDefaultIsMove() {
        let source = URL(fileURLWithPath: "/tmp/a/file.txt")
        let dest = URL(fileURLWithPath: "/tmp/b")
        XCTAssertEqual(
            DropHandler.validate(sources: [source], destination: dest, isWritable: true, optionKeyDown: false),
            .move
        )
    }

    func testOptionKeyMeansCopy() {
        let source = URL(fileURLWithPath: "/tmp/a/file.txt")
        let dest = URL(fileURLWithPath: "/tmp/b")
        XCTAssertEqual(
            DropHandler.validate(sources: [source], destination: dest, isWritable: true, optionKeyDown: true),
            .copy
        )
    }

    func testNotWritableIsNone() {
        let source = URL(fileURLWithPath: "/tmp/a/file.txt")
        let dest = URL(fileURLWithPath: "/tmp/b")
        XCTAssertEqual(
            DropHandler.validate(sources: [source], destination: dest, isWritable: false, optionKeyDown: false),
            .none
        )
    }

    func testEmptySourcesIsNone() {
        let dest = URL(fileURLWithPath: "/tmp/b")
        XCTAssertEqual(
            DropHandler.validate(sources: [], destination: dest, isWritable: true, optionKeyDown: false),
            .none
        )
    }

    func testDroppingFolderOntoItselfIsNone() {
        let folder = URL(fileURLWithPath: "/tmp/A")
        XCTAssertEqual(
            DropHandler.validate(sources: [folder], destination: folder, isWritable: true, optionKeyDown: false),
            .none
        )
    }

    func testDroppingFolderOntoOwnDescendantIsNone() {
        let folder = URL(fileURLWithPath: "/tmp/A")
        let child = URL(fileURLWithPath: "/tmp/A/B")
        XCTAssertEqual(
            DropHandler.validate(sources: [folder], destination: child, isWritable: true, optionKeyDown: false),
            .none
        )
    }

    func testDroppingOnOwnParentIsNone() {
        let file = URL(fileURLWithPath: "/tmp/A/file.txt")
        let parent = URL(fileURLWithPath: "/tmp/A")
        XCTAssertEqual(
            DropHandler.validate(sources: [file], destination: parent, isWritable: true, optionKeyDown: false),
            .none
        )
    }

    func testMixedSelectionWhereOnlySomeAreAlreadyThereStillAllowsDrop() {
        // 選択の一部だけが既にそこにある場合は、動くファイルが実在するので
        // ドロップ自体は許可する（個別のno-opスキップはFileOperation側の仕事）。
        let alreadyThere = URL(fileURLWithPath: "/tmp/A/existing.txt")
        let elsewhere = URL(fileURLWithPath: "/tmp/B/other.txt")
        let dest = URL(fileURLWithPath: "/tmp/A")
        XCTAssertEqual(
            DropHandler.validate(sources: [alreadyThere, elsewhere], destination: dest, isWritable: true, optionKeyDown: false),
            .move
        )
    }

    func testDroppingOntoUnrelatedFolderIsAllowed() {
        let file = URL(fileURLWithPath: "/tmp/A/file.txt")
        let dest = URL(fileURLWithPath: "/tmp/C")
        XCTAssertEqual(
            DropHandler.validate(sources: [file], destination: dest, isWritable: true, optionKeyDown: false),
            .move
        )
    }

    func testNotWritableWinsEvenWhenOptionKeyDown() {
        let source = URL(fileURLWithPath: "/tmp/a/file.txt")
        let dest = URL(fileURLWithPath: "/tmp/b")
        XCTAssertEqual(
            DropHandler.validate(sources: [source], destination: dest, isWritable: false, optionKeyDown: true),
            .none
        )
    }
}
