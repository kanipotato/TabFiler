import XCTest
@testable import TabFilerCore

/// `FileOperation.execute(kind: .copy)`のディレクトリコピーは、シンボリック
/// リンク経由の自己参照コピー対策として、`FileManager.copyItem`に丸投げせず
/// 自前で1階層ずつ辿りながら深さを数える実装（`copyItemWithDepthGuard`）に
/// 置き換わっている。
///
/// この置き換えには2つの検証観点がある。
/// 1. 通常のディレクトリコピー（ネストしたファイル・サブディレクトリを含む）が
///    従来どおり正しく動くこと（実装変更によるリグレッションがないこと）。
/// 2. `isDescendant`の事前チェックをすり抜けるケースが万一あっても、
///    異常に深いディレクトリ構造の生成が`maxCopyDepth`で頭打ちになり、
///    安全側に倒してエラー報告されること（多重防御の直接検証）。
final class CopyDepthGuardTests: XCTestCase {
    var tempDir: URL!
    let fm = FileManager.default

    override func setUpWithError() throws {
        tempDir = fm.temporaryDirectory.appendingPathComponent("TabFilerCopyDepthGuardTests-\(UUID().uuidString)")
        try fm.createDirectory(at: tempDir, withIntermediateDirectories: true)
        tempDir = tempDir.resolvingSymlinksInPath()
    }

    override func tearDownWithError() throws {
        try? fm.removeItem(at: tempDir)
    }

    @discardableResult
    private func makeDir(_ name: String, in dir: URL) throws -> URL {
        let url = dir.appendingPathComponent(name)
        try fm.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }

    @discardableResult
    private func makeFile(_ name: String, in dir: URL, content: String = "test") throws -> URL {
        let url = dir.appendingPathComponent(name)
        try content.write(to: url, atomically: true, encoding: .utf8)
        return url
    }

    // MARK: - 通常のディレクトリコピーが引き続き正しく動くこと

    func testDirectoryCopyPreservesNestedStructureAndContents() throws {
        let srcDir = try makeDir("src", in: tempDir)
        let folder = try makeDir("Folder", in: srcDir)
        try makeFile("top.txt", in: folder, content: "top-level")
        let nested = try makeDir("Nested", in: folder)
        try makeFile("deep.txt", in: nested, content: "nested-content")
        try makeDir("EmptyDir", in: folder) // 空ディレクトリも保持されるべき
        let dstDir = try makeDir("dst", in: tempDir)

        let result = FileOperation.execute(sources: [folder], destinationFolder: dstDir, kind: .copy) { _ in .cancel }

        XCTAssertEqual(result.succeeded, [folder])
        XCTAssertNil(result.failedURL)

        let copiedFolder = dstDir.appendingPathComponent("Folder")
        XCTAssertEqual(
            try String(contentsOf: copiedFolder.appendingPathComponent("top.txt"), encoding: .utf8),
            "top-level"
        )
        XCTAssertEqual(
            try String(contentsOf: copiedFolder.appendingPathComponent("Nested/deep.txt"), encoding: .utf8),
            "nested-content"
        )
        var isDir: ObjCBool = false
        XCTAssertTrue(fm.fileExists(atPath: copiedFolder.appendingPathComponent("EmptyDir").path, isDirectory: &isDir))
        XCTAssertTrue(isDir.boolValue)

        // コピー元は残っている（copyなので）。
        XCTAssertTrue(fm.fileExists(atPath: folder.appendingPathComponent("top.txt").path))
    }

    func testDirectoryCopyPreservesHiddenFiles() throws {
        // 自前実装が`contentsOfDirectory`にskipsHiddenFilesを指定していないことの
        // 確認（FileManager.copyItemはデフォルトで隠しファイルもコピーするため、
        // 挙動を変えてしまっていないか）。
        let srcDir = try makeDir("src", in: tempDir)
        let folder = try makeDir("Folder", in: srcDir)
        try makeFile(".hidden", in: folder, content: "secret")
        let dstDir = try makeDir("dst", in: tempDir)

        let result = FileOperation.execute(sources: [folder], destinationFolder: dstDir, kind: .copy) { _ in .cancel }

        XCTAssertEqual(result.succeeded, [folder])
        XCTAssertTrue(fm.fileExists(atPath: dstDir.appendingPathComponent("Folder/.hidden").path))
    }

    // MARK: - 多重防御: 深さ上限を超えたら安全側に倒す

    /// isDescendantチェックを回避する再現手段が無いため、ここでは
    /// 「maxCopyDepthを超える通常の（シンボリックリンクを介さない）
    /// 深いディレクトリ構造」を直接コピーさせて、深さガード自体が
    /// 単体で正しく機能する（エラーになる・部分的に書き込まれたゴミが
    /// 無制限に増え続けたりしない）ことを検証する。
    func testCopyAbortsWhenDirectoryNestingExceedsMaxDepth() throws {
        let srcDir = try makeDir("src", in: tempDir)
        var current = try makeDir("root", in: srcDir)
        // PATH_MAX（macOSでは1024）に収まるよう、各階層は同じ1文字の名前
        // "d" を使い回して1階層あたりのパス長コストを最小限に抑える
        // （深さのテストが目的で、名前の一意性は不要）。
        let depthBeyondLimit = FileOperation.maxCopyDepth + 10
        for _ in 0..<depthBeyondLimit {
            current = try makeDir("d", in: current)
        }
        let dstDir = try makeDir("dst", in: tempDir)

        let result = FileOperation.execute(sources: [srcDir.appendingPathComponent("root")], destinationFolder: dstDir, kind: .copy) { _ in .cancel }

        XCTAssertTrue(result.succeeded.isEmpty, "深さ上限を超えるので1件も成功として扱われないべき")
        XCTAssertNotNil(result.failedURL)
        XCTAssertNotNil(result.failureMessage)
        // 元データは無事であること(copyなので、そもそも消していない)。
        XCTAssertTrue(fm.fileExists(atPath: srcDir.appendingPathComponent("root").path))
    }
}
