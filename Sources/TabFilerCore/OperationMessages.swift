import Foundation

/// アラートに出す文言（タイトルと本文）。
public struct AlertText: Equatable {
    public let title: String
    public let body: String

    public init(title: String, body: String) {
        self.title = title
        self.body = body
    }
}

/// 移動/コピーまわりのユーザー向け文言を組み立てる。
///
/// 元は`FileTreeView.Coordinator`の`conflictDetailText` / `formattedSize` /
/// `formattedDate` / `reportResult`に分散していた。NSAlertの生成と文言の組み立てが
/// 混ざっていて、「どんな時に報告し、どんな時に黙るか」という判断を単体で
/// 確かめられなかったためここへ出した。
public enum OperationMessages {
    static let unknownValuePlaceholder = "不明"

    // MARK: - 同名衝突ダイアログ

    public static func conflictTitle(for info: FileConflictInfo) -> String {
        "「\(info.destination.lastPathComponent)」は既に存在します"
    }

    /// 移動先と、既存・移動元それぞれのサイズ／更新日時を並べた本文。
    /// - Parameters:
    ///   - locale / timeZone: 日時整形に使う。既定は環境依存だが、テストでは固定値を渡す。
    public static func conflictDetail(
        for info: FileConflictInfo,
        locale: Locale = .current,
        timeZone: TimeZone = .current
    ) -> String {
        """
        移動先: \(info.destination.deletingLastPathComponent().path)

        既存のファイル: \(formattedSize(info.existingSize)) ・ \(formattedDate(info.existingModified, locale: locale, timeZone: timeZone))
        移動元のファイル: \(formattedSize(info.incomingSize)) ・ \(formattedDate(info.incomingModified, locale: locale, timeZone: timeZone))
        """
    }

    public static func formattedSize(_ size: Int64?) -> String {
        guard let size else { return unknownValuePlaceholder }
        return ByteCountFormatter.string(fromByteCount: size, countStyle: .file)
    }

    public static func formattedDate(
        _ date: Date?,
        locale: Locale = .current,
        timeZone: TimeZone = .current
    ) -> String {
        guard let date else { return unknownValuePlaceholder }
        let formatter = DateFormatter()
        formatter.locale = locale
        formatter.timeZone = timeZone
        formatter.dateStyle = .medium
        formatter.timeStyle = .short
        return formatter.string(from: date)
    }

    // MARK: - 大量操作の確認

    public static func largeOperationConfirmation(count: Int) -> AlertText {
        AlertText(
            title: "\(count)件のファイルを操作します",
            body: "件数が多いため、完了まで少し時間がかかる場合があります。続けますか？"
        )
    }

    // MARK: - 実行結果の報告

    /// 実行結果をユーザーへ報告する必要があるかを判断し、必要なら文言を返す。
    ///
    /// 失敗して途中で止まった場合**だけ**報告する。キャンセル・全件成功・一部スキップは
    /// いずれも「失敗ではない」ため、Finder同様サイレントに終える
    /// （成功のたびにダイアログを出すとかえって邪魔になる）。ロールバックはしないので、
    /// 報告するときは「何件成功し、どこで・なぜ止まったか」を必ず含める。
    ///
    /// - Returns: 報告不要なら`nil`。
    public static func resultReport(
        _ result: FileOperationResult,
        kind: FileOperationKind,
        total: Int
    ) -> AlertText? {
        guard let failedURL = result.failedURL else { return nil }
        let verb = kind == .move ? "移動" : "コピー"
        return AlertText(
            title: "\(verb)が途中で停止しました",
            body: "\(total)件中\(result.succeeded.count)件を\(verb)しました。"
                + "「\(failedURL.lastPathComponent)」で止まりました"
                + "（\(result.failureMessage ?? "不明なエラー")）。"
        )
    }
}
