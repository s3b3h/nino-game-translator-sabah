// SPDX-License-Identifier: AGPL-3.0-only
// Nino: "PS5'siz Deneyin" ve karşılama ekranı için örnek altyazılar (oyun metni değil, Nino'nun kendi örnekleri).

import CouchSubsCore
import Foundation

enum DemoSamples {
    struct Line: Equatable {
        let source: String
        let translation: String
    }

    private static let samples: [(en: String, tr: String, ar: String)] = [
        ("Are you listening to me?", "Beni dinliyor musun?", "هل تستمع إليّ؟"),
        ("We need to get out of here, now.", "Hemen buradan çıkmamız lazım.", "علينا الخروج من هنا الآن."),
        ("Keep your head down and follow me.", "Başını eğ ve beni takip et.", "اخفض رأسك واتبعني."),
        ("I'll meet you at the docks tonight.", "Bu gece seninle limanda buluşuruz.", "سألقاك عند الميناء الليلة."),
        ("Nobody leaves until the job is done.", "İş bitmeden kimse bir yere gitmiyor.", "لن يغادر أحد قبل انتهاء المهمة."),
        ("Trust me, I've done this before.", "Bana güven, bunu daha önce yaptım.", "ثق بي، فعلت هذا من قبل."),
    ]

    static var count: Int { samples.count }

    static func line(_ index: Int, target: String) -> Line {
        let sample = samples[index % samples.count]
        return Line(source: sample.en, translation: TargetLanguage.isTurkish(target) ? sample.tr : sample.ar)
    }
}
