import XCTest
@testable import TabFilerCore

/// ユーザー向け文言の組み立て（`FileTreeView.Coordinator`から切り出したもの）のテスト。
/// 特に「どんな時に報告し、どんな時に黙るか」を固定する。
final class OperationMessagesTests: XCTestCase {
    private func makeInfo(
        existingSize: Int64? = nil,
        existingModified: Date? = nil,
        incomingSize: Int64? = nil,
        incomingModified: Date? = nil
    ) -> FileConflictInfo {
        FileConflictInfo(
            source: URL(fileURLWithPath: "/tmp/src/a.txt"),
            destination: URL(fileURLWithPath: "/tmp/dst/a.txt"),
            existingSize: existingSize,
            existingModified: existingModified,
            incomingSize: incomingSize,
            incomingModified: incomingModified
        )
    }

    // MARK: - 衝突ダイアログ

    func testConflictTitleUsesFileName() {
        XCTAssertEqual(OperationMessages.conflictTitle(for: makeInfo()), "「a.txt」は既に存在します")
    }

    func testConflictDetailShowsDestinationFolder() {
        let text = OperationMessages.conflictDetail(for: makeInfo())
        XCTAssertTrue(text.contains("移動先: /tmp/dst"), text)
    }

    /// サイズ・日時が取れなかった場合は「不明」と出す（空欄にしない）。
    func testConflictDetailFallsBackToUnknown() {
        let text = OperationMessages.conflictDetail(for: makeInfo())
        XCTAssertTrue(text.contains("既存のファイル: 不明 ・ 不明"), text)
        XCTAssertTrue(text.contains("移動元のファイル: 不明 ・ 不明"), text)
    }

    func testFormattedSizeReturnsUnknownForNil() {
        XCTAssertEqual(OperationMessages.formattedSize(nil), "不明")
    }

    func testFormattedSizeProducesSomethingForRealSize() {
        let text = OperationMessages.formattedSize(1_048_576)
        XCTAssertNotEqual(text, "不明")
        XCTAssertFalse(text.isEmpty)
    }

    func testFormattedDateReturnsUnknownForNil() {
        XCTAssertEqual(OperationMessages.formattedDate(nil), "不明")
    }

    /// ロケール・タイムゾーンを固定すれば決定的に整形されること
    /// （既定は環境依存なので、テストでは必ず固定して比較する）。
    func testFormattedDateIsDeterministicWithFixedLocaleAndTimeZone() {
        let date = Date(timeIntervalSince1970: 0)
        let text = OperationMessages.formattedDate(
            date,
            locale: Locale(identifier: "en_US_POSIX"),
            timeZone: TimeZone(secondsFromGMT: 0)!
        )
        XCTAssertTrue(text.contains("1970"), text)
        XCTAssertTrue(text.contains("Jan"), text)
    }

    // MARK: - 大量操作の確認

    func testLargeOperationConfirmationIncludesCount() {
        let text = OperationMessages.largeOperationConfirmation(count: 120)
        XCTAssertEqual(text.title, "120件のファイルを操作します")
        XCTAssertFalse(text.body.isEmpty)
    }

    // MARK: - 実行結果の報告（報告する/黙るの判断）

    func testSilentWhenEverythingSucceeded() {
        let result = FileOperationResult(succeeded: [URL(fileURLWithPath: "/tmp/a")], skipped: [])
        XCTAssertNil(OperationMessages.resultReport(result, kind: .move, total: 1))
    }

    func testSilentWhenCancelled() {
        let result = FileOperationResult(succeeded: [], skipped: [], cancelled: true)
        XCTAssertNil(OperationMessages.resultReport(result, kind: .move, total: 3))
    }

    func testSilentWhenOnlySkipped() {
        let result = FileOperationResult(succeeded: [], skipped: [URL(fileURLWithPath: "/tmp/a")])
        XCTAssertNil(OperationMessages.resultReport(result, kind: .copy, total: 1))
    }

    func testReportsWhenStoppedByFailure() {
        let result = FileOperationResult(
            succeeded: [URL(fileURLWithPath: "/tmp/a"), URL(fileURLWithPath: "/tmp/b")],
            skipped: [],
            failedURL: URL(fileURLWithPath: "/tmp/c.txt"),
            failureMessage: "権限がありません"
        )
        let report = OperationMessages.resultReport(result, kind: .move, total: 5)
        XCTAssertEqual(report?.title, "移動が途中で停止しました")
        XCTAssertEqual(report?.body, "5件中2件を移動しました。「c.txt」で止まりました（権限がありません）。")
    }

    func testReportUsesCopyVerb() {
        let result = FileOperationResult(
            succeeded: [],
            skipped: [],
            failedURL: URL(fileURLWithPath: "/tmp/c.txt"),
            failureMessage: "エラー"
        )
        let report = OperationMessages.resultReport(result, kind: .copy, total: 1)
        XCTAssertEqual(report?.title, "コピーが途中で停止しました")
        XCTAssertTrue(report!.body.hasPrefix("1件中0件をコピーしました。"), report!.body)
    }

    func testReportFallsBackWhenFailureMessageIsMissing() {
        let result = FileOperationResult(
            succeeded: [],
            skipped: [],
            failedURL: URL(fileURLWithPath: "/tmp/c.txt"),
            failureMessage: nil
        )
        let report = OperationMessages.resultReport(result, kind: .move, total: 1)
        XCTAssertTrue(report!.body.contains("不明なエラー"), report!.body)
    }
}
