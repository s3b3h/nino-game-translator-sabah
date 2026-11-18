// SPDX-License-Identifier: AGPL-3.0-only

import Foundation

/// Nino: havuz öncelikli oyunlarda (sunucunun `poolFirst` listesi, varsayılan GTA 6) satır önce Nino'nun çeviri havuzuna
/// (sunucuda Claude) sorulur; kullanıcının kendi motoru (DeepL, yapay zekâ, yerel model) hiç çağrılmaz. Sunucu süresinde
/// cevap vermezse, hata verirse ya da günlük bütçe dolduysa altyazı boş kalmasın diye yalnız cihazın ücretsiz çevirisine
/// (Apple) düşülür. Öbür oyunlarda her şey eskisi gibi kullanıcının motoruna gider. Windows: PoolFirstTranslator.cs.
public final class PoolFirstTranslator: TextTranslator, @unchecked Sendable {
    /// Kullanıcının seçtiği çevirmen (öbür oyunlar için).
    public let engine: TextTranslator
    private let free: TextTranslator
    private let poolFirst: () -> Bool
    private let ask: (String) async -> String?
    private let lock = NSLock()
    private var last = ""

    /// Günlük için (havuzdan gelmedi, ücretsize düşüldü).
    public var log: ((String) -> Void)?

    /// - Parameters:
    ///   - free: ücretsiz yerel çevirmen (havuz cevap vermezse).
    ///   - poolFirst: şu an oynanan oyun havuz öncelikli mi.
    ///   - ask: satırı sunucuya sorar, süresinde gelmezse nil (`TranslationPool.translateFirst`).
    public init(engine: TextTranslator, free: TextTranslator, poolFirst: @escaping () -> Bool, ask: @escaping (String) async -> String?) {
        self.engine = engine
        self.free = free
        self.poolFirst = poolFirst
        self.ask = ask
    }

    /// Son satırı kim çevirdi: "havuz", "ücretsiz" ya da "motor".
    public var lastSource: String { lock.withLock { last } }

    private func note(_ source: String) { lock.withLock { last = source } }

    public func translate(_ text: String) async throws -> String {
        guard poolFirst() else {
            note("motor")
            return try await engine.translate(text)
        }
        if let pooled = await ask(text), !pooled.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            note("havuz")
            return pooled
        }
        note("ücretsiz")
        log?("havuz öncelikli oyun: sunucudan çeviri gelmedi, ücretsiz çeviri kullanıldı")
        return try await free.translate(text)
    }

    public func warmUp() async {
        await engine.warmUp()
        await free.warmUp()
    }

    public func spokenLines(for text: String) -> [SpokenLine] { lastSource == "motor" ? engine.spokenLines(for: text) : [] }

    public func translateAll(_ texts: [String]) async throws -> [String] {
        guard poolFirst() else { return try await engine.translateAll(texts) }
        var result: [String] = []
        for text in texts { result.append(try await translate(text)) }
        return result
    }

    public var translatesTogether: Bool { !poolFirst() && engine.translatesTogether }
}
