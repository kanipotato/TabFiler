import Foundation

/// validateDrop時にドロップを受け入れるかどうか、受け入れる場合の操作種別。
public enum DropOperationKind: Equatable {
    case move
    case copy
    case none
}

/// D&Dのドロップ可否判定（NSOutlineViewDataSourceのvalidateDropに対応する
/// 純粋ロジック）。AppKit（NSEvent, NSDraggingInfo等）には一切依存しない。
public enum DropHandler {
    /// ドロップ先と操作種別を判定する。
    ///
    /// - `isWritable`: ドロップ先ディレクトリが書き込み可能か
    ///   （呼び出し側が`FileManager.isWritableFile`等で判定して渡す）
    /// - `optionKeyDown`: Optionキーが押されているか（押されていればコピー）
    ///
    /// 判定順序:
    /// 1. ドロップ先が書き込み不可、またはsourcesが空 → `.none`
    /// 2. sourcesのいずれかがdestinationの子孫（またはdestination自身） →
    ///    フォルダを自分の中に入れる操作になるため `.none`
    /// 3. sources全員の親が既にdestinationと同じ（＝既にそこにある） →
    ///    ドロップしても何も起きないため `.none`
    /// 4. 上記以外は、Optionキーが押されていれば `.copy`、なければ `.move`
    public static func validate(
        sources: [URL],
        destination: URL,
        isWritable: Bool,
        optionKeyDown: Bool
    ) -> DropOperationKind {
        guard isWritable, !sources.isEmpty else { return .none }

        for source in sources {
            if FileOperation.isDescendant(of: source, candidate: destination) {
                return .none
            }
        }

        let allAlreadyThere = sources.allSatisfy {
            FileOperation.urlsPointToSamePath($0.deletingLastPathComponent(), destination)
        }
        if allAlreadyThere { return .none }

        return optionKeyDown ? .copy : .move
    }
}
