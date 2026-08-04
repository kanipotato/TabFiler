import XCTest
@testable import TabFilerCore

final class FileOperationTests: XCTestCase {
    var tempDir: URL!
    let fm = FileManager.default

    override func setUpWithError() throws {
        tempDir = fm.temporaryDirectory.appendingPathComponent("TabFilerFileOpTests-\(UUID().uuidString)")
        try fm.createDirectory(at: tempDir, withIntermediateDirectories: true)
        // macOSでは/var -> /private/varのシンボリックリンクがあり、
        // FileManager.temporaryDirectoryは非解決のパスを返す一方、
        // contentsOfDirectory等は解決済みパスを返すため、ここで揃えておく。
        tempDir = tempDir.resolvingSymlinksInPath()
    }

    override func tearDownWithError() throws {
        // 権限操作テストがdst側の書き込み権限を落としたまま終わることがあるため、
        // 削除前に必ず書き込み可能へ戻してからクリーンアップする。
        try? fm.setAttributes([.posixPermissions: 0o755], ofItemAtPath: tempDir.path)
        try? fm.removeItem(at: tempDir)
    }

    @discardableResult
    private func makeFile(_ name: String, in dir: URL, content: String = "test") throws -> URL {
        let url = dir.appendingPathComponent(name)
        try content.write(to: url, atomically: true, encoding: .utf8)
        return url
    }

    @discardableResult
    private func makeDir(_ name: String, in dir: URL) throws -> URL {
        let url = dir.appendingPathComponent(name)
        try fm.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }

    // MARK: - 通常の移動・コピー

    func testMoveSucceeds() throws {
        let srcDir = try makeDir("src", in: tempDir)
        let dstDir = try makeDir("dst", in: tempDir)
        let file = try makeFile("a.txt", in: srcDir)

        let result = FileOperation.execute(sources: [file], destinationFolder: dstDir, kind: .move) { _ in .cancel }

        XCTAssertEqual(result.succeeded, [file])
        XCTAssertNil(result.failedURL)
        XCTAssertFalse(fm.fileExists(atPath: file.path))
        XCTAssertTrue(fm.fileExists(atPath: dstDir.appendingPathComponent("a.txt").path))
    }

    func testCopySucceeds() throws {
        let srcDir = try makeDir("src", in: tempDir)
        let dstDir = try makeDir("dst", in: tempDir)
        let file = try makeFile("a.txt", in: srcDir)

        let result = FileOperation.execute(sources: [file], destinationFolder: dstDir, kind: .copy) { _ in .cancel }

        XCTAssertEqual(result.succeeded, [file])
        XCTAssertTrue(fm.fileExists(atPath: file.path), "コピー元は残る")
        XCTAssertTrue(fm.fileExists(atPath: dstDir.appendingPathComponent("a.txt").path))
    }

    func testMovesMultipleFilesInOneCall() throws {
        let srcDir = try makeDir("src", in: tempDir)
        let dstDir = try makeDir("dst", in: tempDir)
        let files = try (0..<5).map { try makeFile("f\($0).txt", in: srcDir) }

        let result = FileOperation.execute(sources: files, destinationFolder: dstDir, kind: .move) { _ in .cancel }

        XCTAssertEqual(Set(result.succeeded), Set(files))
        for file in files {
            XCTAssertTrue(fm.fileExists(atPath: dstDir.appendingPathComponent(file.lastPathComponent).path))
        }
    }

    // MARK: - 同名衝突

    func testUniqueNameForConflictGeneratesFinderStyleName() throws {
        let dir = try makeDir("dir", in: tempDir)
        try makeFile("report.pdf", in: dir)

        let name = FileOperation.uniqueNameForConflict(originalName: "report.pdf", in: dir, fileManager: fm)
        XCTAssertEqual(name, "report 2.pdf")
    }

    func testUniqueNameForConflictSkipsExistingNumberedNames() throws {
        let dir = try makeDir("dir", in: tempDir)
        try makeFile("report.pdf", in: dir)
        try makeFile("report 2.pdf", in: dir)

        let name = FileOperation.uniqueNameForConflict(originalName: "report.pdf", in: dir, fileManager: fm)
        XCTAssertEqual(name, "report 3.pdf")
    }

    func testConflictKeepBothRenamesFile() throws {
        let srcDir = try makeDir("src", in: tempDir)
        let dstDir = try makeDir("dst", in: tempDir)
        let file = try makeFile("report.pdf", in: srcDir, content: "new")
        try makeFile("report.pdf", in: dstDir, content: "old")

        let result = FileOperation.execute(sources: [file], destinationFolder: dstDir, kind: .move) { _ in .keepBoth }

        XCTAssertEqual(result.succeeded, [file])
        XCTAssertTrue(fm.fileExists(atPath: dstDir.appendingPathComponent("report.pdf").path))
        XCTAssertTrue(fm.fileExists(atPath: dstDir.appendingPathComponent("report 2.pdf").path))
        XCTAssertEqual(try String(contentsOf: dstDir.appendingPathComponent("report 2.pdf"), encoding: .utf8), "new")
    }

    func testConflictReplaceOverwritesExisting() throws {
        let srcDir = try makeDir("src", in: tempDir)
        let dstDir = try makeDir("dst", in: tempDir)
        let file = try makeFile("report.pdf", in: srcDir, content: "new")
        try makeFile("report.pdf", in: dstDir, content: "old")

        let result = FileOperation.execute(sources: [file], destinationFolder: dstDir, kind: .move) { _ in .replace }

        XCTAssertEqual(result.succeeded, [file])
        XCTAssertEqual(try String(contentsOf: dstDir.appendingPathComponent("report.pdf"), encoding: .utf8), "new")
        XCTAssertFalse(fm.fileExists(atPath: srcDir.appendingPathComponent("report.pdf").path))
    }

    func testConflictSkipLeavesBothUntouched() throws {
        let srcDir = try makeDir("src", in: tempDir)
        let dstDir = try makeDir("dst", in: tempDir)
        let file = try makeFile("report.pdf", in: srcDir, content: "new")
        try makeFile("report.pdf", in: dstDir, content: "old")

        let result = FileOperation.execute(sources: [file], destinationFolder: dstDir, kind: .move) { _ in .skip }

        XCTAssertEqual(result.skipped, [file])
        XCTAssertTrue(result.succeeded.isEmpty)
        XCTAssertTrue(fm.fileExists(atPath: srcDir.appendingPathComponent("report.pdf").path), "スキップしたのでソースは残る")
        XCTAssertEqual(try String(contentsOf: dstDir.appendingPathComponent("report.pdf"), encoding: .utf8), "old")
    }

    func testConflictCancelStopsRemainingFiles() throws {
        let srcDir = try makeDir("src", in: tempDir)
        let dstDir = try makeDir("dst", in: tempDir)
        let fileA = try makeFile("a.txt", in: srcDir)
        let fileB = try makeFile("report.pdf", in: srcDir)
        try makeFile("report.pdf", in: dstDir, content: "old")
        let fileC = try makeFile("c.txt", in: srcDir)

        let result = FileOperation.execute(sources: [fileA, fileB, fileC], destinationFolder: dstDir, kind: .move) { _ in .cancel }

        XCTAssertEqual(result.succeeded, [fileA])
        XCTAssertTrue(result.cancelled)
        XCTAssertTrue(fm.fileExists(atPath: fileC.path), "キャンセル後の残りには手をつけない")
    }

    // MARK: - 子孫チェック（データ損失防止の最重要チェック）

    func testFolderCannotBeMovedIntoItsOwnChild() throws {
        let folderA = try makeDir("A", in: tempDir)
        let folderB = try makeDir("B", in: folderA)

        let result = FileOperation.execute(sources: [folderA], destinationFolder: folderB, kind: .move) { _ in .cancel }

        XCTAssertNotNil(result.failedURL)
        XCTAssertTrue(result.succeeded.isEmpty)
        XCTAssertTrue(fm.fileExists(atPath: folderA.path), "拒否されるので何も動かない")
        XCTAssertTrue(fm.fileExists(atPath: folderB.path))
    }

    func testFolderCannotBeMovedOntoItself() throws {
        let folderA = try makeDir("A", in: tempDir)

        let result = FileOperation.execute(sources: [folderA], destinationFolder: folderA, kind: .move) { _ in .cancel }

        XCTAssertNotNil(result.failedURL)
        XCTAssertTrue(result.succeeded.isEmpty)
    }

    func testDescendantViolationRejectsWholeBatchEvenIfOtherItemsAreValid() throws {
        let folderA = try makeDir("A", in: tempDir)
        let folderB = try makeDir("B", in: folderA)
        let okFile = try makeFile("ok.txt", in: tempDir)

        // folderAをfolderBの中に入れようとする不正な操作が1件混ざっていたら、
        // 他が正当でも全体を拒否する（部分実行しない）。
        let result = FileOperation.execute(sources: [okFile, folderA], destinationFolder: folderB, kind: .move) { _ in .cancel }

        XCTAssertTrue(result.succeeded.isEmpty)
        XCTAssertTrue(fm.fileExists(atPath: okFile.path), "巻き込まれて動かされたりしない")
    }

    func testIsDescendantDetectsNestedPaths() {
        let a = URL(fileURLWithPath: "/Users/kazu/A")
        let b = URL(fileURLWithPath: "/Users/kazu/A/B")
        let sibling = URL(fileURLWithPath: "/Users/kazu/C")

        XCTAssertTrue(FileOperation.isDescendant(of: a, candidate: b))
        XCTAssertTrue(FileOperation.isDescendant(of: a, candidate: a))
        XCTAssertFalse(FileOperation.isDescendant(of: a, candidate: sibling))
        XCTAssertFalse(FileOperation.isDescendant(of: b, candidate: a), "親へ動かすのは正常な操作なので拒否しない")
    }

    func testIsDescendantDoesNotFalsePositiveOnPrefixMatchingName() {
        // "/Users/kazu/A" と "/Users/kazu/AB" は文字列としては前方一致するが、
        // "AB" は "A" の配下ではないので子孫扱いしてはいけない。
        let a = URL(fileURLWithPath: "/Users/kazu/A")
        let ab = URL(fileURLWithPath: "/Users/kazu/AB")
        XCTAssertFalse(FileOperation.isDescendant(of: a, candidate: ab))
    }

    // MARK: - 「ドロップ先==ドラッグ元の親」は何もしない

    func testDropOnOwnParentIsNoOp() throws {
        let dir = try makeDir("dir", in: tempDir)
        let file = try makeFile("a.txt", in: dir)

        let result = FileOperation.execute(sources: [file], destinationFolder: dir, kind: .move) { _ in .cancel }

        XCTAssertEqual(result.skipped, [file])
        XCTAssertTrue(result.succeeded.isEmpty)
        XCTAssertTrue(fm.fileExists(atPath: file.path))
    }

    // MARK: - 消えたファイル・消えたフォルダ

    func testMissingSourceIsSkipped() throws {
        let srcDir = try makeDir("src", in: tempDir)
        let dstDir = try makeDir("dst", in: tempDir)
        let ghost = srcDir.appendingPathComponent("ghost.txt") // 作らない＝存在しない

        let result = FileOperation.execute(sources: [ghost], destinationFolder: dstDir, kind: .move) { _ in .cancel }

        XCTAssertEqual(result.skipped, [ghost])
        XCTAssertTrue(result.succeeded.isEmpty)
        XCTAssertNil(result.failedURL)
    }

    func testMissingDestinationFolderFails() throws {
        let srcDir = try makeDir("src", in: tempDir)
        let file = try makeFile("a.txt", in: srcDir)
        let missingDst = tempDir.appendingPathComponent("does-not-exist")

        let result = FileOperation.execute(sources: [file], destinationFolder: missingDst, kind: .move) { _ in .cancel }

        XCTAssertEqual(result.failedURL, missingDst)
        XCTAssertTrue(result.succeeded.isEmpty)
        XCTAssertTrue(fm.fileExists(atPath: file.path))
    }

    // MARK: - 途中失敗（ロールバックせず、そこで止めて報告する）

    func testStopsOnFailureAndLeavesPreviousSuccessesIntact() throws {
        let srcDir = try makeDir("src", in: tempDir)
        let dstDir = try makeDir("dst", in: tempDir)
        let fileA = try makeFile("a.txt", in: srcDir)
        let fileB = try makeFile("report.pdf", in: srcDir)
        try makeFile("report.pdf", in: dstDir, content: "old")
        let fileC = try makeFile("c.txt", in: srcDir)

        // fileBの衝突ダイアログで「置換」を選んだ瞬間にdstDirの書き込み権限を
        // 落とし、置換に必要なremoveItemを失敗させることで「2件目の途中で
        // 失敗する」状況を決定的に再現する。
        let result = FileOperation.execute(sources: [fileA, fileB, fileC], destinationFolder: dstDir, kind: .move) { [fm] _ in
            try? fm.setAttributes([.posixPermissions: 0o555], ofItemAtPath: dstDir.path)
            return .replace
        }

        XCTAssertEqual(result.succeeded, [fileA], "1件目は成功したまま残る")
        XCTAssertEqual(result.failedURL, fileB)
        XCTAssertNotNil(result.failureMessage)
        XCTAssertTrue(fm.fileExists(atPath: fileC.path), "3件目には手をつけない")
        XCTAssertFalse(fm.fileExists(atPath: srcDir.appendingPathComponent("a.txt").path), "1件目のソースは既に移動済み")

        try fm.setAttributes([.posixPermissions: 0o755], ofItemAtPath: dstDir.path)
    }

    func testWriteProtectedDestinationCausesFailureNotSilentDrop() throws {
        let srcDir = try makeDir("src", in: tempDir)
        let dstDir = try makeDir("dst", in: tempDir)
        let file = try makeFile("a.txt", in: srcDir)

        try fm.setAttributes([.posixPermissions: 0o555], ofItemAtPath: dstDir.path)
        defer { try? fm.setAttributes([.posixPermissions: 0o755], ofItemAtPath: dstDir.path) }

        let result = FileOperation.execute(sources: [file], destinationFolder: dstDir, kind: .move) { _ in .cancel }

        XCTAssertEqual(result.failedURL, file)
        XCTAssertTrue(fm.fileExists(atPath: file.path), "失敗したので元の場所に残る")
    }

    // MARK: - シンボリックリンク

    func testSymlinkMovesTheLinkItselfNotItsTarget() throws {
        let srcDir = try makeDir("src", in: tempDir)
        let dstDir = try makeDir("dst", in: tempDir)
        let targetFile = try makeFile("target.txt", in: tempDir, content: "target-content")
        let linkURL = srcDir.appendingPathComponent("link.txt")
        try fm.createSymbolicLink(at: linkURL, withDestinationURL: targetFile)

        let result = FileOperation.execute(sources: [linkURL], destinationFolder: dstDir, kind: .move) { _ in .cancel }

        XCTAssertEqual(result.succeeded, [linkURL])
        let movedLink = dstDir.appendingPathComponent("link.txt")
        let attrs = try fm.attributesOfItem(atPath: movedLink.path)
        XCTAssertEqual(attrs[.type] as? FileAttributeType, .typeSymbolicLink, "リンク自体が移動されている（リンク先を辿ってコピーされていない）")
        XCTAssertTrue(fm.fileExists(atPath: targetFile.path), "リンク先の実体はそのまま残る")
        let destinationOfLink = try fm.destinationOfSymbolicLink(atPath: movedLink.path)
        XCTAssertEqual(destinationOfLink, targetFile.path)
    }

    // MARK: - 大量操作の安全弁

    func testRequiresLargeOperationConfirmationThreshold() {
        XCTAssertFalse(FileOperation.requiresLargeOperationConfirmation(fileCount: 50))
        XCTAssertTrue(FileOperation.requiresLargeOperationConfirmation(fileCount: 51))
    }
}
