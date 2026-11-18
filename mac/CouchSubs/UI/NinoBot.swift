// SPDX-License-Identifier: AGPL-3.0-only
// Nino: "Nino'ya Sor" yardımcısının Mac ve iPhone'da ortak parçaları: robot (göz kırpar, hafifçe süzülür), "yazıyor"
// noktaları, robotun yerel metinleri. Resimler design/bot-png'den doğrudan pakete kopyalanır (project.yml).

import CouchSubsCore
import SwiftUI
#if os(macOS)
import AppKit
#else
import UIKit
#endif

/// Robotun iki karesi (gözler açık, kapalı). Uygulama paketinde design/bot-png/nino-bot-256.png ve nino-bot-blink-256.png.
enum NinoBotArt {
    static let open = load("nino-bot-256")
    static let blink = load("nino-bot-blink-256")

    private static func load(_ name: String) -> Image? {
        guard let url = Bundle.main.url(forResource: name, withExtension: "png") else { return nil }
        #if os(macOS)
        return NSImage(contentsOf: url).map { Image(nsImage: $0) }
        #else
        return UIImage(contentsOfFile: url.path).map { Image(uiImage: $0) }
        #endif
    }
}

/// Robotun yüzü. `animated`: 4–5 sn'de bir ~150 ms göz kırpar; `bobbing`: hafifçe yukarı aşağı süzülür; `thinking`:
/// başını hafifçe sallar. "Hareketi azalt" açıksa hiçbiri olmaz.
struct NinoBotFace: View {
    var size: CGFloat
    var animated = true
    var bobbing = false
    var thinking = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var blinking = false
    @State private var up = false
    @State private var tilt = false

    var body: some View {
        Group {
            if let image = (blinking ? NinoBotArt.blink : NinoBotArt.open) ?? NinoBotArt.open {
                image.resizable().interpolation(.high).aspectRatio(contentMode: .fit)
            } else {
                Image(systemName: "face.smiling").resizable().aspectRatio(contentMode: .fit).foregroundStyle(Color.accentColor)
            }
        }
        .frame(width: size, height: size)
        .rotationEffect(.degrees(thinking && tilt && !reduceMotion ? 6 : thinking && !reduceMotion ? -6 : 0))
        .offset(y: bobbing && !reduceMotion ? (up ? -size * 0.05 : size * 0.05) : 0)
        .accessibilityHidden(true)
        .task(id: animated && !reduceMotion) {
            guard animated && !reduceMotion else { return }
            while !Task.isCancelled {
                try? await Task.sleep(nanoseconds: UInt64.random(in: 4_000_000_000 ... 5_000_000_000))
                guard !Task.isCancelled else { return }
                blinking = true
                try? await Task.sleep(nanoseconds: 150_000_000)
                blinking = false
            }
        }
        .onAppear {
            guard !reduceMotion else { return }
            if bobbing { withAnimation(.easeInOut(duration: 1.6).repeatForever(autoreverses: true)) { up = true } }
        }
        .task(id: thinking) {
            // Düşünürken başını sağa sola sallar; bitince düz durur.
            guard thinking, !reduceMotion else {
                withAnimation(.easeOut(duration: 0.2)) { tilt = false }
                return
            }
            tilt = false
            withAnimation(.easeInOut(duration: 0.5).repeatForever(autoreverses: true)) { tilt = true }
        }
    }
}

/// Robot cevap yazarken üç nokta sırayla büyüyüp küçülür.
struct NinoTypingDots: View {
    var color: Color
    var dot: CGFloat = 7
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        TimelineView(.animation(minimumInterval: 1 / 30, paused: reduceMotion)) { timeline in
            let t = timeline.date.timeIntervalSinceReferenceDate
            HStack(spacing: dot * 0.6) {
                ForEach(0 ..< 3, id: \.self) { i in
                    let phase = reduceMotion ? 0.5 : (sin((t * 2 * .pi / 1.2) - Double(i) * 0.9) + 1) / 2
                    Circle()
                        .fill(color.opacity(0.35 + 0.65 * phase))
                        .frame(width: dot, height: dot)
                        .scaleEffect(0.75 + 0.35 * phase)
                }
            }
        }
        .frame(height: dot * 1.6)
    }
}

/// Robotun yerel metinleri. Öneriye dokununca o metin sunucuya gider; bu yüzden metin arayüz dilinin paketinden okunur
/// (sistem dili İngilizce olsa da Türkçe arayüzde Türkçe gider).
enum AskNino {
    static let greeting = "Hi! I'm Nino 👋 You can ask me anything about setting up. First, tell me: which devices do you have? (PS5 or Xbox, TV or monitor, phone or computer) Where do you want to set it up?"
    static let suggestions = ["PS5 + TV + phone", "PS5 + monitor + computer", "Xbox + TV", "How do I install the TV app?"]

    /// Arayüz dilindeki metin (`Localizable` tablosu); yoksa İngilizcesi.
    static func text(_ key: String, _ locale: Locale) -> String {
        let code = locale.language.languageCode?.identifier ?? "en"
        if let path = Bundle.main.path(forResource: code, ofType: "lproj"), let bundle = Bundle(path: path) {
            let value = bundle.localizedString(forKey: key, value: "\u{0}", table: nil)
            if value != "\u{0}" { return value }
        }
        return key
    }

    /// Robotun hata bildirimi (sohbette robotun balonu olarak).
    static func notice(_ failure: AssistantChat.Failure) -> String {
        switch failure {
        case .disabled: "I'm almost ready! Until then, send your question with Report a Problem and the team will answer."
        case .rateLimited: "You've asked a lot today 🙂 Let's continue tomorrow."
        case .busy: "I'm very busy right now, try again in a bit."
        case .tooLarge: "That's too big for me. Remove a photo and try again."
        case .rejected: "I couldn't read that message. Try writing it a little differently."
        case .offline, .server, .noEndpoint: "I couldn't reach the server. Check your internet and try again."
        }
    }
}

/// Robotun mesajı: paragraflar, mavi yuvarlak rozetli numaralı adımlar ve noktalı maddeler (asılı girinti: kayan
/// satırlar rozetin altına değil yazının hizasına gelir), bağlantılar tıklanabilir. Bloklara ayırma CouchSubsCore'da
/// (AssistantChat.blocks); sağdan sola dillerde rozet kendiliğinden sağa geçer. Mac ve iPhone aynı görünümü kullanır.
struct NinoMessageText: View {
    let text: String

    /// Rozetin çapı; maddenin noktası da aynı genişlikte durur ki yazılar aynı hizaya gelsin.
    private static let badge: CGFloat = 21

    var body: some View {
        let blocks = AssistantChat.blocks(text)
        VStack(alignment: .leading, spacing: 0) {
            ForEach(blocks.indices, id: \.self) { i in
                block(blocks[i])
                    .padding(.top, i == 0 ? 0 : blocks[i].isListItem && blocks[i - 1].isListItem ? 8 : 10)
            }
        }
        .textSelection(.enabled)
    }

    @ViewBuilder private func block(_ block: AssistantChat.Block) -> some View {
        switch block {
        case .paragraph(let text):
            paragraph(text)
        case .step(let number, let text):
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Text(verbatim: number)
                    .font(.system(size: 12, weight: .bold, design: .rounded))
                    .monospacedDigit()
                    .foregroundStyle(.white)
                    .padding(.horizontal, number.count > 1 ? 4 : 0)
                    .frame(minWidth: Self.badge, minHeight: Self.badge)
                    .background(Capsule().fill(Color.csAccent))
                    .accessibilityLabel(Text(verbatim: "\(number)."))
                paragraph(text)
            }
        case .bullet(let text):
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Text(verbatim: "•")
                    .fontWeight(.bold)
                    .foregroundStyle(Color.csAccent)
                    .frame(width: Self.badge)
                    .accessibilityHidden(true)
                paragraph(text)
            }
        }
    }

    private func paragraph(_ text: String) -> some View {
        Text(AssistantChat.attributed(text))
            .fixedSize(horizontal: false, vertical: true)
    }
}

/// Soldan sağa (sağdan sola dillerde tersi) dizen, sığmayanı alt satıra geçiren yerleşim.
struct ChipFlow: Layout {
    var spacing: CGFloat = 8

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let width = proposal.width ?? .infinity
        var x: CGFloat = 0, y: CGFloat = 0, row: CGFloat = 0, widest: CGFloat = 0
        for view in subviews {
            let size = view.sizeThatFits(.unspecified)
            if x > 0 && x + size.width > width { y += row + spacing; x = 0; row = 0 }
            x += size.width + spacing
            row = max(row, size.height)
            widest = max(widest, x - spacing)
        }
        return CGSize(width: min(widest, width), height: y + row)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        var x = bounds.minX, y = bounds.minY, row: CGFloat = 0
        for view in subviews {
            let size = view.sizeThatFits(.unspecified)
            if x > bounds.minX && x + size.width > bounds.maxX { y += row + spacing; x = bounds.minX; row = 0 }
            view.place(at: CGPoint(x: x, y: y), proposal: ProposedViewSize(size))
            x += size.width + spacing
            row = max(row, size.height)
        }
    }
}
