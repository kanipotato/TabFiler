import XCTest
@testable import TabFilerCore

/// 「以降すべてに適用」の記憶（`FileTreeView.Coordinator.makeConflictResolver`から切り出したもの）のテスト。
final class StickyConflictResolverTests: XCTestCase {
    private func makeInfo(_ name: String) -> FileConflictInfo {
        FileConflictInfo(
            source: URL(fileURLWithPath: "/tmp/src/\(name)"),
            destination: URL(fileURLWithPath: "/tmp/dst/\(name)"),
            existingSize: nil,
            existingModified: nil,
            incomingSize: nil,
            incomingModified: nil
        )
    }

    func testAsksEveryTimeWhenApplyToAllIsNotChecked() {
        var askCount = 0
        let resolver = StickyConflictResolver { _ in
            askCount += 1
            return ConflictAnswer(resolution: .skip, applyToAll: false)
        }
        XCTAssertEqual(resolver.resolve(makeInfo("a")), .skip)
        XCTAssertEqual(resolver.resolve(makeInfo("b")), .skip)
        XCTAssertEqual(resolver.resolve(makeInfo("c")), .skip)
        XCTAssertEqual(askCount, 3)
    }

    func testStopsAskingOnceApplyToAllIsChecked() {
        var askCount = 0
        let resolver = StickyConflictResolver { _ in
            askCount += 1
            return ConflictAnswer(resolution: .replace, applyToAll: true)
        }
        XCTAssertEqual(resolver.resolve(makeInfo("a")), .replace)
        XCTAssertEqual(resolver.resolve(makeInfo("b")), .replace)
        XCTAssertEqual(resolver.resolve(makeInfo("c")), .replace)
        XCTAssertEqual(askCount, 1, "2回目以降は問い合わせないはず")
    }

    /// 途中でチェックが入った場合、その回の答えが以降に固定される。
    func testApplyToAllTakesEffectFromTheAnswerThatCheckedIt() {
        var askCount = 0
        let answers: [ConflictAnswer] = [
            ConflictAnswer(resolution: .skip, applyToAll: false),
            ConflictAnswer(resolution: .keepBoth, applyToAll: true),
            ConflictAnswer(resolution: .replace, applyToAll: false)
        ]
        let resolver = StickyConflictResolver { _ in
            defer { askCount += 1 }
            return answers[min(askCount, answers.count - 1)]
        }
        XCTAssertEqual(resolver.resolve(makeInfo("a")), .skip)
        XCTAssertEqual(resolver.resolve(makeInfo("b")), .keepBoth)
        XCTAssertEqual(resolver.resolve(makeInfo("c")), .keepBoth, "固定後は3件目の.replaceを聞きに行かない")
        XCTAssertEqual(askCount, 2)
    }

    /// キャンセルを「以降すべてに適用」で選んだ場合も固定される。
    func testCancelCanBeSticky() {
        var askCount = 0
        let resolver = StickyConflictResolver { _ in
            askCount += 1
            return ConflictAnswer(resolution: .cancel, applyToAll: true)
        }
        XCTAssertEqual(resolver.resolve(makeInfo("a")), .cancel)
        XCTAssertEqual(resolver.resolve(makeInfo("b")), .cancel)
        XCTAssertEqual(askCount, 1)
    }

    func testAsClosureSharesTheSameStickyState() {
        var askCount = 0
        let resolver = StickyConflictResolver { _ in
            askCount += 1
            return ConflictAnswer(resolution: .replace, applyToAll: true)
        }
        let closure = resolver.asClosure()
        XCTAssertEqual(closure(makeInfo("a")), .replace)
        XCTAssertEqual(closure(makeInfo("b")), .replace)
        XCTAssertEqual(resolver.resolve(makeInfo("c")), .replace)
        XCTAssertEqual(askCount, 1)
    }

    /// 1回のドロップ操作ごとに新しいインスタンスを作れば、記憶は持ち越されない。
    func testNewInstanceStartsWithoutStickyState() {
        var askCount = 0
        let makeResolver = {
            StickyConflictResolver { _ in
                askCount += 1
                return ConflictAnswer(resolution: .replace, applyToAll: true)
            }
        }
        _ = makeResolver().resolve(makeInfo("a"))
        _ = makeResolver().resolve(makeInfo("b"))
        XCTAssertEqual(askCount, 2)
    }
}
