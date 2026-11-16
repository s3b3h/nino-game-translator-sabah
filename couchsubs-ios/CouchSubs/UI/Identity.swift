// SPDX-License-Identifier: AGPL-3.0-only
// Nino: yeni kimliğin ortak parçaları (Android'deki Heading, DemoScene ve camsı satırlarla aynı): büyük başlık, koyu sahne
// kartı, sahne içinde camsı satırlar, "Ücretsiz" etiketi ve "PS5'siz Deneyin" bağlantısı.

import SwiftUI

enum NinoInk {
    static let ink = Color(hex: 0x0A1430)
    static let soft = Color(hex: 0x55607A)
    static let stageTop = Color(hex: 0x151E36)
    static let stageBottom = Color(hex: 0x06080F)
    static let freeGreen = Color(hex: 0x6EE7A8)
}

/// Bir anahtarın arayüz dilindeki metni (Home tablosu).
struct L10n {
    let locale: Locale
    func callAsFunction(_ key: String) -> String { UILanguage.text(key, locale) }
}

/// Başlık bloğu: adım satırı (13pt vurgu mavisi), 32pt kalın sıkı başlık, 16pt açıklama.
struct NinoTitle: View {
    var step: String?
    let title: String
    var message: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            if let step { Text(verbatim: step).font(.system(size: 13, weight: .semibold)).foregroundStyle(Mobile.Palette.accent) }
            Text(verbatim: title).font(.system(size: 32, weight: .bold)).tracking(-0.5).foregroundStyle(NinoInk.ink)
                .fixedSize(horizontal: false, vertical: true)
            if let message {
                Text(verbatim: message).font(.system(size: 16)).foregroundStyle(NinoInk.soft).fixedSize(horizontal: false, vertical: true)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

/// Koyu sahne kartı: lacivert→siyah, köşe 28, üstten ışıklı ince kenar.
struct NinoStage<Content: View>: View {
    var height: CGFloat?
    @ViewBuilder var content: Content

    var body: some View {
        let shape = RoundedRectangle(cornerRadius: 28, style: .continuous)
        ZStack { content }
            .frame(maxWidth: .infinity)
            .frame(height: height)
            .background(shape.fill(LinearGradient(colors: [NinoInk.stageTop, NinoInk.stageBottom], startPoint: .top, endPoint: .bottom)))
            .overlay(shape.strokeBorder(LinearGradient(colors: [.white.opacity(0.22), .white.opacity(0.03)], startPoint: .top, endPoint: .bottom), lineWidth: 1))
            .clipShape(shape)
            .shadow(color: NinoInk.ink.opacity(0.35), radius: 18, y: 10)
    }
}

/// Sahne içindeki camsı satır: simge, başlık, açıklama ve isteğe bağlı sağ öğe.
struct GlassRow<Trailing: View>: View {
    let symbol: String
    let title: String
    var detail: String?
    @ViewBuilder var trailing: Trailing

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: symbol).font(.system(size: 18, weight: .semibold)).foregroundStyle(.white)
                .frame(width: 40, height: 40)
                .background(Color.white.opacity(0.10), in: Circle())
            VStack(alignment: .leading, spacing: 2) {
                Text(verbatim: title).font(.system(size: 16, weight: .semibold)).foregroundStyle(.white).lineLimit(1).minimumScaleFactor(0.7)
                if let detail { Text(verbatim: detail).font(.system(size: 13)).foregroundStyle(.white.opacity(0.6)).lineLimit(2) }
            }
            Spacer(minLength: 4)
            trailing
        }
        .padding(.horizontal, 14).padding(.vertical, 12)
        .background(Color.white.opacity(0.07), in: RoundedRectangle(cornerRadius: 18, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 18, style: .continuous).strokeBorder(Color.white.opacity(0.12), lineWidth: 1))
    }
}

extension GlassRow where Trailing == EmptyView {
    init(symbol: String, title: String, detail: String? = nil) {
        self.init(symbol: symbol, title: title, detail: detail) { EmptyView() }
    }
}

/// Yeşilimsi "Ücretsiz" etiketi (koyu zemin üstünde).
struct FreeTag: View {
    let text: String
    var body: some View {
        Text(verbatim: text).font(.system(size: 12, weight: .bold)).foregroundStyle(NinoInk.freeGreen)
            .padding(.horizontal, 10).padding(.vertical, 5)
            .background(NinoInk.freeGreen.opacity(0.14), in: Capsule())
            .overlay(Capsule().strokeBorder(NinoInk.freeGreen.opacity(0.35), lineWidth: 1))
    }
}

/// "PS5'siz Deneyin": PS5 olmadan uygulamanın nasıl çalıştığını gösteren demo (App İnceleme de bunu kullanır).
struct TryWithoutPS5Button: View {
    let title: String
    let action: () -> Void
    var body: some View {
        Button(action: action) {
            Label { Text(verbatim: title).lineLimit(1).minimumScaleFactor(0.75) } icon: { Image(systemName: "sparkles") }
        }
        .buttonStyle(.mobileGhost)
        .layoutPriority(1)
        .accessibilityIdentifier("tryWithoutPS5")
    }
}

/// Kurulum ekranlarından açılan PS5'siz önizleme: ana ekranın demo hali, sağ üstte Kapat.
struct DemoPreviewScreen: View {
    @EnvironmentObject private var model: PhoneModel
    @Environment(\.dismiss) private var dismiss
    @State private var path: [Route] = []

    var body: some View {
        NavigationStack(path: $path) {
            HomeScreen(path: $path, demoOnly: true, onClose: {
                model.stopDemo()
                dismiss()
            })
        }
        .onAppear { model.startDemo() }
        .onDisappear { model.stopDemo() }
    }
}
