import XCTest
@testable import TabFilerCore

/// [修正後] isDescendantは`resolvingSymlinksInPath()`で両者を実体パスへ
/// 解決してから比較するようになったため、「移動先パスの文字列上は
/// ソースの子孫に見えないが、実体（シンボリックリンクの解決先）は
/// ソース自身または子孫である」というケースも正しく検出できることを検証する。
///
/// これはレビュー対象コードの既存テストには存在しない観点（第三者レビューで
/// 追加）。修正前は「パス文字列で子孫かどうか判定すれば十分」という想定の
/// 元、シンボリックリンクを介した迂回が実際に可能だった（`isDescendant`が
/// `false`を返し、copy操作がFileManager.copyItemで自分自身の中へ
/// 再帰的にコピーを始め、PATH_MAXに達するまで約455階層のディレクトリを
/// 実際にディスクへ書き込んでから失敗する実害を確認済み）。
/// 修正後はここのアサーションを反転させ、正しく迂回を検出できることを
/// 保証する回帰テストとして残す。
final class SymlinkDescendantBypassTests: XCTestCase {
    var tempDir: URL!
    let fm = FileManager.default

    override func setUpWithError() throws {
        tempDir = fm.temporaryDirectory.appendingPathComponent("TabFilerSymlinkBypassTests-\(UUID().uuidString)")
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

    /// ケース1: destinationFolder自体が「sourceを指すシンボリックリンク」
    /// である場合。パス文字列としては全く別の場所（例: ~/Desktop/link-to-A）
    /// にあるが、シンボリックリンクを解決すれば実体はsource自身なので
    /// 検出できなければならない。
    func testIsDescendantDetectsSymlinkAliasPointingToSourceItself() throws {
        let folderA = try makeDir("A", in: tempDir)
        let otherPlace = try makeDir("Desktop", in: tempDir)
        let linkToA = otherPlace.appendingPathComponent("link-to-A")
        try fm.createSymbolicLink(at: linkToA, withDestinationURL: folderA)

        XCTAssertTrue(
            FileOperation.isDescendant(of: folderA, candidate: linkToA),
            "シンボリックリンクを解決すればdestination実体はsource自身なので検出されるべき"
        )
    }

    /// ケース2: destinationFolderが「sourceの子孫を指すシンボリックリンク」
    /// である場合も同様に検出できなければならない。
    func testIsDescendantDetectsSymlinkAliasPointingIntoSourceSubtree() throws {
        let folderA = try makeDir("A", in: tempDir)
        let folderB = try makeDir("B", in: folderA) // A/B
        let otherPlace = try makeDir("Desktop", in: tempDir)
        let linkToB = otherPlace.appendingPathComponent("link-to-B")
        try fm.createSymbolicLink(at: linkToB, withDestinationURL: folderB)

        XCTAssertTrue(
            FileOperation.isDescendant(of: folderA, candidate: linkToB),
            "destinationがA配下(B)へのシンボリックリンクでも実体はA配下なので検出されるべき"
        )
    }

    /// 対照ケース: シンボリックリンクが全く無関係な場所を指している場合は
    /// 誤検出（false positive）してはいけない。
    func testIsDescendantDoesNotFalsePositiveOnUnrelatedSymlink() throws {
        let folderA = try makeDir("A", in: tempDir)
        let folderC = try makeDir("C", in: tempDir)
        let otherPlace = try makeDir("Desktop", in: tempDir)
        let linkToC = otherPlace.appendingPathComponent("link-to-C")
        try fm.createSymbolicLink(at: linkToC, withDestinationURL: folderC)

        XCTAssertFalse(
            FileOperation.isDescendant(of: folderA, candidate: linkToC),
            "無関係な場所を指すシンボリックリンクを子孫と誤判定してはいけない"
        )
    }

    /// ケース1の実害を実機で確認する: execute()がこの迂回を検出して
    /// 「Aを（実体として）自分自身の中に移動する」操作を確実に拒否するか。
    /// 修正後は execute() 冒頭の isDescendant チェックで弾かれ、
    /// 1件も実行されずに failedURL がセットされることを期待する。
    func testExecuteBehaviorWhenDestinationIsSymlinkAliasToSourceItself() throws {
        let folderA = try makeDir("A", in: tempDir)
        try "marker".write(to: folderA.appendingPathComponent("keep.txt"), atomically: true, encoding: .utf8)
        let otherPlace = try makeDir("Desktop", in: tempDir)
        let linkToA = otherPlace.appendingPathComponent("link-to-A")
        try fm.createSymbolicLink(at: linkToA, withDestinationURL: folderA)

        let result = FileOperation.execute(
            sources: [folderA],
            destinationFolder: linkToA,
            kind: .move
        ) { _ in .cancel }

        XCTAssertTrue(result.succeeded.isEmpty, "シンボリックリンク経由の自己内包は事前チェックで拒否され、1件も実行されないべき")
        XCTAssertEqual(result.failedURL, folderA, "自己内包違反として failedURL にsourceが記録されるべき")
        XCTAssertTrue(fm.fileExists(atPath: folderA.path), "元データは消えていないべき")
    }

    /// copy操作でも同様に、事前チェックで拒否され、危険な再帰コピー
    /// （PATH_MAXに達するまでネストしたディレクトリを書き込み続ける実害）
    /// が発生しないことを確認する。
    func testExecuteRejectsCopyWhenDestinationIsSymlinkAliasToSourceItself() throws {
        let folderA = try makeDir("A", in: tempDir)
        try "marker".write(to: folderA.appendingPathComponent("keep.txt"), atomically: true, encoding: .utf8)
        let otherPlace = try makeDir("Desktop", in: tempDir)
        let linkToA = otherPlace.appendingPathComponent("link-to-A")
        try fm.createSymbolicLink(at: linkToA, withDestinationURL: folderA)

        let result = FileOperation.execute(
            sources: [folderA],
            destinationFolder: linkToA,
            kind: .copy
        ) { _ in .cancel }

        XCTAssertTrue(result.succeeded.isEmpty, "シンボリックリンク経由の自己内包は事前チェックで拒否され、1件もコピーされないべき")
        XCTAssertEqual(result.failedURL, folderA)
        // 危険なネストコピーが発生していないことの傍証として、A直下に
        // 新たな "A" ディレクトリ（再帰コピーの痕跡）が生成されていないことを確認する。
        XCTAssertFalse(
            fm.fileExists(atPath: folderA.appendingPathComponent("A").path),
            "再帰的な自己コピーが1段でも走った形跡があってはいけない"
        )
    }
}
