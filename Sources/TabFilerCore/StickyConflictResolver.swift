import Foundation

/// 同名衝突ダイアログでユーザーが返した答え。
public struct ConflictAnswer: Equatable {
    /// 選んだ解決方法。
    public let resolution: ConflictResolution
    /// 「以降すべてに適用」にチェックが入っていたか。
    public let applyToAll: Bool

    public init(resolution: ConflictResolution, applyToAll: Bool) {
        self.resolution = resolution
        self.applyToAll = applyToAll
    }
}

/// 「以降すべてに適用」を1回のドロップ操作の中だけ記憶する解決器。
///
/// 元は`FileTreeView.Coordinator.makeConflictResolver()`の中で、NSAlertの組み立てと
/// クロージャがキャプチャする2つの可変変数(`applyToAll` / `stickyResolution`)が
/// 混ざっていた。記憶の仕組み自体はAppKitと無関係な小さな状態機械なので、
/// 実際に問い合わせる部分(`ask`)だけ注入で受ける形にして切り出した。
///
/// - Note: `FileOperation.execute`は単一のバックグラウンドキューから順番に
///   `resolve`を呼ぶ前提のため、内部状態にロックは持たない。
///   （元実装のクロージャキャプチャも同じ前提だった）
public final class StickyConflictResolver {
    /// 実際にユーザーへ問い合わせる処理。呼び出し側でNSAlertを出す想定。
    private let ask: (FileConflictInfo) -> ConflictAnswer
    /// 「以降すべてに適用」が選ばれた後に固定される答え。nilなら毎回問い合わせる。
    private var stickyResolution: ConflictResolution?

    public init(ask: @escaping (FileConflictInfo) -> ConflictAnswer) {
        self.ask = ask
    }

    /// 固定済みならそれを返し、そうでなければ問い合わせる。
    /// 問い合わせ結果が「以降すべてに適用」付きなら、以降は問い合わせずその答えを返す。
    public func resolve(_ info: FileConflictInfo) -> ConflictResolution {
        if let stickyResolution { return stickyResolution }
        let answer = ask(info)
        if answer.applyToAll {
            stickyResolution = answer.resolution
        }
        return answer.resolution
    }

    /// `FileOperation.execute(resolveConflict:)`へそのまま渡せるクロージャ。
    public func asClosure() -> (FileConflictInfo) -> ConflictResolution {
        { [self] info in resolve(info) }
    }
}
