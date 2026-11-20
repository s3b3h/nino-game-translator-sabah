// SPDX-License-Identifier: AGPL-3.0-only
// Nino: Mac'teki salon sahnesinin (mac/CouchSubs/UI/LivingRoomScene.swift) iPhone karşılığı; Android'deki
// HomeScenes.kt ile aynı kurallar. Bütün Nino uygulamalarında ana ekran aynı: duvarda TV, sehpada konsol, duvar prizi.
// Based on CouchSubs by Sinan Yorulmaz (https://github.com/yorulmazsinan/couchsubs), modified on 2026-11-21.

import CouchSubsCore
import SwiftUI

/// Salon. Saydam salon görseli (konsola göre PS5'li ya da Xbox'lı) sabit durur; üstüne TV ekranının içi, konsoldan prize
/// giden kablo ve fiş, arkasına LED ışıklar çizilir. Fiş prize takılınca (dokunarak ya da sürükleyerek) çeviri başlar,
/// çekilince durur. Fiş takılı değilken priz yanıp söner, TV'de ne yapılacağı ve toplam indirme yazar.
///
/// Telefonda görsel ekranın genişliğine sığdırılır (ölçek ≈ 0,21). Mac'teki gibi 1672 noktalık tuvali `scaleEffect` ile
/// küçültmek yerine her ölçü ölçekle çarpılır: büyük bulanık katmanlar 3 kat çözünürlükte çizilip bellek yemesin. Fiş ve
/// priz görselde küçük kaldığı için dokunma alanları en az 60 noktadır; fiş de biraz büyütülerek çizilir.
/// Koordinatlar görselin piksel ölçüsündedir (1672×941). Not: konsolun biçimi Sony'nin tasarımına benzer; mağazaya
/// gönderilmeden önce markasız bir çizimle değiştirilmeli (bkz. CLAUDE.md, Marka).
struct PhoneLivingRoom: View {
    @EnvironmentObject private var model: PhoneModel
    @Environment(\.locale) private var locale
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    /// Çeviri açık ya da açılıyor (demo da sayılır): fiş prizde.
    let active: Bool
    /// PS5 görüntüsü geliyor (ya da demo): TV'de altyazı ya da "sıradaki altyazı bekleniyor".
    let streaming: Bool
    let line: String?
    var source: String?
    /// Bağlanılamama nedeni; varsa TV'de uyarı simgesiyle yazılır.
    var problem: String?
    let badge: String
    /// Havuz öncelikli oyun (GTA 6): LED'ler pembe-mavi, TV'de gün batımı fonu.
    let gta: Bool
    let onToggle: () -> Void
    /// Canlıyken TV'ye dokununca (altyazı telefondaysa) tam ekran.
    var onTV: (() -> Void)?

    @State private var drag: CGSize = .zero
    @State private var splashDone = false
    @State private var splashID = UUID()
    @State private var socketPulse = false
    @ObservedObject private var downloads = DownloadCounter.shared

    /// Nino (kullanıcı isteği, 21 Kasım 2026; Mac ile aynı): açılışta fiş bir an çekik görünür, sonra yaylanarak prize
    /// takılır (çeviri kendiliğinden başlasa da). Ardından toplam indirme sayacı 1, 2, 3 diye başlayıp toplam sayıya fırlar.
    @State private var introHold = !PhoneLivingRoom.introPlayed
    /// Açılış gösterisi uygulama her açıldığında bir kez oynar (ayarlardan dönünce yeniden oynamaz).
    private static var introPlayed = false

    static let canvas = CGSize(width: 1672, height: 941)
    /// Sahnenin yüksekliği: Xbox'lı salonda sarkan fiş görselin altına taşar; ikisinde de aynı yükseklik (sahne kaymasın).
    static let sceneHeight: CGFloat = 965
    /// TV ekranının içi bu genişlikte bir TV'ye göre çizilip küçültülür (Mac'te 588; telefonda yazılar okunsun diye daha dar).
    static let logicalWidth: CGFloat = 300
    /// Dokunma alanı (nokta).
    static let touch: CGFloat = 60

    struct Layout {
        let image: String
        let screen: CGRect
        let tvFrame: CGRect
        let standFrame: CGRect
        let socket: CGPoint
        let cableStart: CGPoint
        var cableLead: [CGPoint] = []
        var cableOut = CGVector(dx: 1, dy: 0.1)
        let hanging: CGPoint

        // Sayılar Mac'teki `LivingRoomScene.Layout` ile aynı (görseller aynı dosyalar).
        static let ps5 = Layout(image: "LivingRoom",
                                screen: CGRect(x: 149, y: 40, width: 1151, height: 595),
                                tvFrame: CGRect(x: 139, y: 27, width: 1171, height: 621),
                                standFrame: CGRect(x: 49, y: 713, width: 1502, height: 160),
                                socket: CGPoint(x: 1564, y: 378),
                                cableStart: CGPoint(x: 1550, y: 734),
                                cableLead: [CGPoint(x: 1490, y: 706), CGPoint(x: 1522, y: 706), CGPoint(x: 1535, y: 709),
                                            CGPoint(x: 1545, y: 716), CGPoint(x: 1552, y: 727)],
                                cableOut: CGVector(dx: 0.5, dy: 0.87),
                                hanging: CGPoint(x: 1600, y: 885))
        static let xbox = Layout(image: "LivingRoomXbox",
                                 screen: CGRect(x: 136, y: 40, width: 1185, height: 596),
                                 tvFrame: CGRect(x: 121, y: 26, width: 1214, height: 630),
                                 standFrame: CGRect(x: 43, y: 733, width: 1580, height: 167),
                                 socket: CGPoint(x: 1561, y: 381),
                                 cableStart: CGPoint(x: 1572, y: 722),
                                 hanging: CGPoint(x: 1646, y: 912))
    }

    private var layout: Layout { model.isXbox ? .xbox : .ps5 }
    private var plugged: Bool { active && !introHold }
    private func t(_ key: String) -> String { UILanguage.text(key, locale) }

    var body: some View {
        GeometryReader { geo in
            let s = geo.size.width / Self.canvas.width
            ZStack(alignment: .topLeading) {
                leds(s)
                socketGlow(s)
                Image(layout.image)
                    .resizable()
                    .frame(width: Self.canvas.width * s, height: Self.canvas.height * s)
                    .accessibilityHidden(true)
                tvScreen(s)
                cable(s)
                plugView(s)
                // Dokunma alanları en üstte: prize dokunmak da fişi takar/çıkarır; fiş sürüklenir ya da dokunulur.
                Color.clear
                    .frame(width: Self.touch, height: Self.touch)
                    .contentShape(Rectangle())
                    .position(x: layout.socket.x * s, y: layout.socket.y * s)
                    .onTapGesture { tapToggle() }
                plugTarget(s)
            }
            .frame(width: geo.size.width, height: geo.size.height, alignment: .topLeading)
        }
        .aspectRatio(Self.canvas.width / Self.sceneHeight, contentMode: .fit)
        // Sahne bir resimdir: Arapça ve Urduca arayüzde aynalanmaz.
        .environment(\.layoutDirection, .leftToRight)
        .animation(reduceMotion ? nil : .spring(response: 0.5, dampingFraction: 0.78), value: plugged)
        .onChange(of: plugged) { now in
            // Her takışta TV'deki açılış animasyonu baştan oynar.
            if now { splashDone = false; splashID = UUID() }
        }
        .onAppear { if Self.introPlayed && active { splashDone = true } }
        .task {
            guard !Self.introPlayed else { return }
            Self.introPlayed = true
            try? await Task.sleep(for: .milliseconds(reduceMotion ? 0 : 900))
            withAnimation(reduceMotion ? nil : .spring(response: 0.55, dampingFraction: 0.7)) { introHold = false }
        }
        .task {
            // Toplam indirme: açılışta ve sonra aralıklarla yenilenir (alınamazsa son bilinen sayı kalır).
            while !Task.isCancelled {
                await downloads.refresh()
                try? await Task.sleep(for: .seconds(DownloadCounter.interval))
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Text(verbatim: t(plugged ? "scene.stop" : "scene.start")))
        .accessibilityValue(Text(verbatim: plugged && streaming ? TargetLanguage.displayText(line ?? "") : ""))
        .accessibilityAddTraits(.isButton)
        .accessibilityAction { onToggle() }
    }

    private func tapToggle() {
        UIImpactFeedbackGenerator(style: .light).impactOccurred()
        onToggle()
    }

    // MARK: TV

    private func tvScreen(_ s: CGFloat) -> some View {
        let rect = layout.screen
        let size = CGSize(width: Self.logicalWidth, height: Self.logicalWidth * rect.height / rect.width)
        let factor = rect.width * s / size.width
        return ZStack(alignment: .topLeading) {
            // Görseldeki ekranın geçişlerde bile görünmemesi için altta siyah zemin.
            Color.black
            screenContent(size: size)
                .frame(width: size.width, height: size.height)
                .scaleEffect(factor, anchor: .topLeading)
                .frame(width: rect.width * s, height: rect.height * s, alignment: .topLeading)
        }
        .frame(width: rect.width * s, height: rect.height * s)
        .clipped()
        .contentShape(Rectangle())
        .onTapGesture { if plugged && streaming { onTV?() } }
        .offset(x: rect.minX * s, y: rect.minY * s)
    }

    @ViewBuilder
    private func screenContent(size: CGSize) -> some View {
        if !plugged {
            // Açılış gösterisinde sayı fiş takılınca sayılarak çıkar; önce görünmez.
            TVStandby(text: t("scene.plug"), downloadsTitle: t("scene.downloads"), downloads: introHold ? nil : downloads.total)
        } else if !splashDone {
            // Uygulamanın kendi açılış animasyonu, TV ekranına sığacak kadar küçültülmüş.
            let window = CGSize(width: 1040, height: 586)
            SplashView { withAnimation(.easeOut(duration: 0.4)) { splashDone = true } }
                .id(splashID)
                .frame(width: window.width, height: window.height)
                .scaleEffect(size.width / window.width)
                .frame(width: size.width, height: size.height)
                .environment(\.colorScheme, .dark)
        } else {
            liveScreen
        }
    }

    /// Çeviri açık: oyun sahnesi gibi koyu ekran (GTA 6'da gün batımı), sol üstte CANLI, sağ üstte toplam indirme,
    /// altta Türkçe satır ya da bağlantının durumu.
    private var liveScreen: some View {
        ZStack {
            if gta {
                SunsetBackdrop().transition(.opacity)
            } else {
                LinearGradient(colors: [Color(red: 0.09, green: 0.12, blue: 0.24), Color(red: 0.15, green: 0.09, blue: 0.18)],
                               startPoint: .topLeading, endPoint: .bottomTrailing)
            }
            VStack(spacing: 0) {
                HStack(alignment: .top) {
                    HStack(spacing: 5) {
                        Circle().fill(Color(hex: 0xE5162B)).frame(width: 6, height: 6)
                        Text(verbatim: badge).font(.system(size: 9, weight: .bold))
                            .tracking(TargetLanguage.containsArabic(badge) ? 0 : 1).foregroundStyle(.white)
                    }
                    .padding(.horizontal, 8).frame(height: 18)
                    .background(Capsule().fill(Color.black.opacity(0.4)))
                    Spacer()
                    if let total = downloads.total { DownloadHUD(title: t("scene.downloads"), total: total, countsUp: true) }
                }
                Spacer(minLength: 0)
                Group {
                    if let problem {
                        HStack(alignment: .top, spacing: 6) {
                            Image(systemName: "exclamationmark.triangle.fill").foregroundStyle(Color.orange)
                            Text(verbatim: problem).foregroundStyle(.white.opacity(0.9))
                                .lineLimit(5).minimumScaleFactor(0.6)
                        }
                        .font(.system(size: 11, weight: .medium))
                        .multilineTextAlignment(.leading)
                    } else if !streaming {
                        Text(verbatim: t("home.stage.connecting"))
                            .font(.system(size: 13, weight: .medium)).foregroundStyle(.white.opacity(0.7))
                    } else if let line, !line.isEmpty {
                        VStack(spacing: 3) {
                            if let source {
                                Text(verbatim: source).font(.system(size: 9)).foregroundStyle(.white.opacity(0.55)).lineLimit(1)
                            }
                            Text(verbatim: TargetLanguage.displayText(line))
                                .font(.system(size: 17, weight: .semibold))
                                .foregroundStyle(.white)
                                .multilineTextAlignment(.center)
                                .lineLimit(3)
                                .minimumScaleFactor(0.6)
                                .padding(.horizontal, 12).padding(.vertical, 6)
                                .background(Color.black.opacity(0.62), in: RoundedRectangle(cornerRadius: 9, style: .continuous))
                                .subtitleDirection(line)
                        }
                        .id(line)
                        .transition(.opacity.combined(with: .offset(y: 5)))
                    } else {
                        Text(verbatim: t("home.stage.waiting"))
                            .font(.system(size: 13, weight: .medium)).foregroundStyle(.white.opacity(0.55))
                    }
                }
                .padding(.bottom, 4)
            }
            .padding(12)
        }
        .animation(.easeOut(duration: 0.3), value: line)
        .animation(.easeOut(duration: 0.3), value: gta)
    }

    // MARK: Işıklar

    /// LED'ler: TV'nin arkasından duvara vuran ışık ve sehpanın altındaki şerit (Mac ile aynı renkler). Görselin arkasında
    /// çizilir; fiş takılınca yanar. GTA 6 tanınınca solda pembe, sağda açık mavi.
    private func leds(_ s: CGFloat) -> some View {
        let blue = Color(red: 0.12, green: 0.36, blue: 1.0)
        let wide = gta ? [Color(red: 1.0, green: 0.24, blue: 0.62), Color(red: 0.74, green: 0.50, blue: 0.96), Color(red: 0.30, green: 0.78, blue: 1.0)]
                       : [blue, blue, blue]
        let tight = gta ? [Color(red: 1.0, green: 0.52, blue: 0.78), Color(red: 0.84, green: 0.70, blue: 1.0), Color(red: 0.58, green: 0.88, blue: 1.0)]
                        : Array(repeating: Color(red: 0.3, green: 0.55, blue: 1.0), count: 3)
        let strip = gta ? tight : Array(repeating: Color(red: 0.45, green: 0.65, blue: 1.0), count: 3)
        func glow(_ colors: [Color]) -> LinearGradient { LinearGradient(colors: colors, startPoint: .leading, endPoint: .trailing) }
        let tv = layout.tvFrame, stand = layout.standFrame
        return ZStack(alignment: .topLeading) {
            RoundedRectangle(cornerRadius: 30 * s)
                .fill(glow(wide))
                .frame(width: (tv.width + 40) * s, height: (tv.height + 40) * s)
                .blur(radius: 46 * s)
                .offset(x: (tv.minX - 20) * s, y: (tv.minY - 20) * s)
            RoundedRectangle(cornerRadius: 10 * s)
                .fill(glow(tight))
                .frame(width: (tv.width + 10) * s, height: (tv.height + 10) * s)
                .blur(radius: 12 * s)
                .offset(x: (tv.minX - 5) * s, y: (tv.minY - 5) * s)
            Capsule()
                .fill(glow(wide))
                .frame(width: (stand.width - 60) * s, height: 40 * s)
                .blur(radius: 26 * s)
                .offset(x: (stand.minX + 30) * s, y: (stand.maxY - 14) * s)
            Capsule()
                .fill(glow(strip))
                .frame(width: (stand.width - 90) * s, height: max(1.5, 8 * s))
                .blur(radius: 4 * s)
                .offset(x: (stand.minX + 45) * s, y: (stand.maxY - 4) * s)
        }
        .opacity(plugged ? 1 : 0)
        .animation(.easeInOut(duration: reduceMotion ? 0 : 0.8), value: plugged)
        .animation(.easeInOut(duration: reduceMotion ? 0 : 1.2), value: gta)
        .allowsHitTesting(false)
    }

    /// Fiş takılı değilken prizin kenarlarından taşan, yanıp sönen ışık: fişin nereye takılacağı anlaşılsın. "Hareketi
    /// azalt" açıksa yanıp sönmez, sabit yanar.
    private func socketGlow(_ s: CGFloat) -> some View {
        let size: CGFloat = 86
        return ZStack {
            RoundedRectangle(cornerRadius: 16 * s, style: .continuous)
                .fill(Color(red: 0.30, green: 0.66, blue: 1.0))
                .frame(width: (size + 26) * s, height: (size + 26) * s)
                .blur(radius: 18 * s)
                .opacity(socketPulse ? 0.95 : 0.3)
            RoundedRectangle(cornerRadius: 12 * s, style: .continuous)
                .fill(Color(red: 0.62, green: 0.84, blue: 1.0))
                .frame(width: (size + 8) * s, height: (size + 8) * s)
                .blur(radius: 5 * s)
                .opacity(socketPulse ? 1 : 0.45)
        }
        .position(x: layout.socket.x * s, y: layout.socket.y * s)
        .opacity(plugged ? 0 : 1)
        .animation(.easeInOut(duration: reduceMotion ? 0 : 0.5), value: plugged)
        .allowsHitTesting(false)
        .onAppear {
            guard !reduceMotion else { socketPulse = true; return }
            withAnimation(.easeInOut(duration: 0.95).repeatForever(autoreverses: true)) { socketPulse = true }
        }
    }

    // MARK: Fiş ve kablo

    /// Fişin çizimi telefonda bu kadar büyütülür (görselde ~8 nokta kalırdı); en çok 1,6 kat.
    private func boost(_ s: CGFloat) -> CGFloat { min(1.6, max(1, 0.3 / max(s, 0.01))) }

    /// Fişin yeri (sahne pikseli). Sürüklerken parmağı izler.
    private func plugPoint(_ s: CGFloat) -> CGPoint {
        let base = plugged ? layout.socket : layout.hanging
        return CGPoint(x: base.x + drag.width / s, y: base.y + drag.height / s)
    }

    /// Fiş çıkıkken uçlarının baktığı yön (Mac'teki `LivingRoomScene.plugTurn` ile aynı kural): uzakta aşağı sarkar,
    /// prize yaklaştıkça uçlar prize döner.
    private func plugTurn(_ s: CGFloat) -> Double {
        let plug = plugPoint(s), socket = layout.socket, rest = layout.hanging
        let turnDone: CGFloat = 120
        let restDistance = hypot(socket.x - rest.x, socket.y - rest.y)
        let distance = hypot(socket.x - plug.x, socket.y - plug.y)
        guard restDistance > turnDone, distance > 1 else { return 0 }
        let t = min(1, max(0, (restDistance - distance) / (restDistance - turnDone)))
        let eased = t * t * (3 - 2 * t)
        return eased * atan2(-(socket.x - plug.x), socket.y - plug.y)
    }

    /// Konsoldan fişe giden kablo (Mac ile aynı yol). Çıkıkken boyundan artan kadar sarkar, takılıyken alttan prize kıvrılır.
    private func cable(_ s: CGFloat) -> some View {
        let p = plugPoint(s)
        let inSocket = plugged && drag == .zero
        let turn = plugTurn(s)
        let prong = CGPoint(x: -sin(turn), y: cos(turn))
        let start = layout.cableLead.last ?? layout.cableStart
        let out = layout.cableOut
        let neck = 40 * boost(s)
        func pt(_ x: CGFloat, _ y: CGFloat) -> CGPoint { CGPoint(x: x * s, y: y * s) }
        return ZStack(alignment: .topLeading) {
            Path { path in
                let first = layout.cableLead.first ?? layout.cableStart
                path.move(to: pt(first.x, first.y))
                for point in layout.cableLead.dropFirst() { path.addLine(to: pt(point.x, point.y)) }
                if inSocket {
                    let end = CGPoint(x: p.x, y: p.y + 30)
                    path.addCurve(to: pt(end.x, end.y), control1: pt(start.x + out.dx * 90, start.y + out.dy * 90),
                                  control2: pt(end.x + 10, end.y + 170))
                } else {
                    let back = CGPoint(x: p.x - prong.x * neck, y: p.y - prong.y * neck)
                    let sag = max(0, 330 - hypot(back.x - start.x, back.y - start.y)) * 0.45
                    path.addCurve(to: pt(back.x, back.y),
                                  control1: pt(start.x + out.dx * 70, start.y + out.dy * 70 + sag),
                                  control2: pt(back.x - prong.x * 80, back.y - prong.y * 80 + sag))
                }
            }
            .stroke(Color(white: 0.06), style: StrokeStyle(lineWidth: max(1.8, 8 * s), lineCap: .round, lineJoin: .round))
            .shadow(color: .black.opacity(0.25), radius: 1.5, y: 1)
            // Xbox görselinde kablo yok: kablo konsolun arkasındaki girişten küçük bir fiş başıyla çıkar.
            if layout.cableLead.isEmpty {
                RoundedRectangle(cornerRadius: 3 * s, style: .continuous)
                    .fill(Color(white: 0.08))
                    .frame(width: 14 * s, height: 12 * s)
                    .position(x: layout.cableStart.x * s, y: layout.cableStart.y * s)
            }
        }
        .allowsHitTesting(false)
    }

    /// Fiş: çıkıkken siyah gövde ve iki metal uç; takılıyken prizin önünde yuvarlak siyah kapak.
    private func plugView(_ s: CGFloat) -> some View {
        let k = s * boost(s)
        let p = plugPoint(s)
        let metal = LinearGradient(colors: [Color(white: 0.92), Color(white: 0.6)], startPoint: .leading, endPoint: .trailing)
        return ZStack {
            if plugged && drag == .zero {
                Circle()
                    .fill(LinearGradient(colors: [Color(white: 0.24), Color(white: 0.04)], startPoint: .topLeading, endPoint: .bottomTrailing))
                    .overlay(Circle().strokeBorder(Color.white.opacity(0.18), lineWidth: 1))
                    .frame(width: 58 * k, height: 58 * k)
                    .shadow(color: .black.opacity(0.45), radius: 3, y: 2)
            } else {
                VStack(spacing: 0) {
                    RoundedRectangle(cornerRadius: 5 * k, style: .continuous)
                        .fill(Color(white: 0.06))
                        .frame(width: 13 * k, height: 14 * k)
                    RoundedRectangle(cornerRadius: 9 * k, style: .continuous)
                        .fill(LinearGradient(colors: [Color(white: 0.22), Color(white: 0.04)], startPoint: .leading, endPoint: .trailing))
                        .overlay(RoundedRectangle(cornerRadius: 9 * k, style: .continuous).strokeBorder(Color.white.opacity(0.14), lineWidth: 0.5))
                        .frame(width: 36 * k, height: 50 * k)
                    HStack(spacing: 14 * k) {
                        Capsule().fill(metal).frame(width: 6 * k, height: 24 * k)
                        Capsule().fill(metal).frame(width: 6 * k, height: 24 * k)
                    }
                }
                .rotationEffect(.radians(plugTurn(s)))
                .shadow(color: .black.opacity(0.3), radius: 2, y: 1.5)
            }
        }
        .scaleEffect(drag == .zero ? 1 : 1.1)
        .position(x: p.x * s, y: p.y * s)
        .allowsHitTesting(false)
    }

    /// Fişin dokunma ve sürükleme alanı. Hareket `.position`tan sonra bağlanır: alan parmakla birlikte kaysa da
    /// sürüklemenin ölçüldüğü yer sabit kalır (titremez).
    private func plugTarget(_ s: CGFloat) -> some View {
        let p = plugPoint(s)
        return Color.clear
            .frame(width: Self.touch, height: Self.touch)
            .contentShape(Rectangle())
            .position(x: p.x * s, y: p.y * s)
            .gesture(DragGesture(minimumDistance: 4)
                .onChanged { drag = $0.translation }
                .onEnded { value in
                    let base = plugged ? layout.socket : layout.hanging
                    let end = CGPoint(x: base.x + value.translation.width / s, y: base.y + value.translation.height / s)
                    let nearSocket = hypot(end.x - layout.socket.x, end.y - layout.socket.y) < 160
                    withAnimation(reduceMotion ? nil : .spring(response: 0.45, dampingFraction: 0.75)) { drag = .zero }
                    if nearSocket != plugged { tapToggle() }
                })
            .simultaneousGesture(TapGesture().onEnded { tapToggle() })
    }
}

/// Fiş takılı değilken TV ekranı: ortada ne yapılacağı, sağ üstte toplam indirme.
private struct TVStandby: View {
    let text: String
    let downloadsTitle: String
    let downloads: Int?

    var body: some View {
        ZStack {
            Color.black
            Text(verbatim: text)
                .font(.system(size: 11, weight: .semibold, design: .monospaced))
                // Harf aralığı Arapça harflerin birleşmesini bozar.
                .tracking(TargetLanguage.containsArabic(text) ? 0 : 1.5)
                .textCase(.uppercase)
                .foregroundStyle(Color.white.opacity(0.45))
                .multilineTextAlignment(.center)
                .padding(.horizontal, 28)
        }
        .overlay(alignment: .topTrailing) {
            if let downloads { DownloadHUD(title: downloadsTitle, total: downloads).padding(12) }
        }
    }
}

/// Toplam indirme göstergesi (Mac'teki `DownloadHUD` ile aynı): oyunlardaki para göstergesi gibi kalın, hafif eğik,
/// siyah çerçeveli; üstte küçük beyaz başlık, altında yeşil sayı. `countsUp`: sayı 1, 2, 3 diye yavaş başlar (280 ms),
/// sonra hızlanarak (pow(p, 2,6), 1,55 sn) toplam sayıya fırlar ve büyüyüp yeşil parlayarak yerine oturur.
struct DownloadHUD: View {
    let title: String
    let total: Int
    var countsUp = false

    private static let green = Color(red: 0.48, green: 0.91, blue: 0.48)
    @State private var shown: Int?
    @State private var punch = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        let arabic = TargetLanguage.containsArabic(title)
        let value = shown ?? total
        VStack(alignment: .trailing, spacing: 1) {
            outlined(Text(verbatim: title).tracking(arabic ? 0 : 0.6), size: 7.5, color: .white, weight: 0.6)
                .textCase(.uppercase)
            outlined(Text(verbatim: value.formatted(.number.grouping(.automatic))), size: 18, color: Self.green, weight: 1)
                .monospacedDigit()
                .scaleEffect(punch ? 1.32 : 1, anchor: .trailing)
                .shadow(color: Self.green.opacity(punch ? 0.95 : 0), radius: punch ? 9 : 0)
        }
        .task(id: countsUp) {
            guard countsUp, !reduceMotion, total > 3 else { shown = nil; return }
            shown = 0
            for step in 1...3 {
                shown = step
                try? await Task.sleep(for: .milliseconds(280))
                if Task.isCancelled { return }
            }
            let start = Date(), duration = 1.55
            while !Task.isCancelled {
                let p = min(1, Date().timeIntervalSince(start) / duration)
                shown = max(3, Int((pow(p, 2.6) * Double(total)).rounded()))
                if p >= 1 { break }
                try? await Task.sleep(for: .milliseconds(16))
            }
            shown = total
            withAnimation(.spring(response: 0.22, dampingFraction: 0.45)) { punch = true }
            try? await Task.sleep(for: .milliseconds(260))
            withAnimation(.spring(response: 0.45, dampingFraction: 0.6)) { punch = false }
        }
        // Hafif eğim (Arapçada harfleri bozmasın diye yok).
        .transformEffect(arabic ? .identity : CGAffineTransform(a: 1, b: 0, c: -0.12, d: 1, tx: 2, ty: 0))
        .fixedSize()
        .accessibilityElement(children: .combine)
    }

    /// Siyah çerçeveli yazı: dört yöne keskin gölge + altta derinlik gölgesi. iPhone'da "Impact" yoksa sistemin en kalını.
    private func outlined(_ text: Text, size: CGFloat, color: Color, weight: CGFloat) -> some View {
        text.font(Font.custom("Impact", size: size).weight(.black))
            .foregroundStyle(color)
            .shadow(color: .black, radius: 0, x: weight, y: 0)
            .shadow(color: .black, radius: 0, x: -weight, y: 0)
            .shadow(color: .black, radius: 0, x: 0, y: weight)
            .shadow(color: .black, radius: 0, x: 0, y: -weight)
            .shadow(color: .black.opacity(0.9), radius: 0, x: 0, y: weight + 0.5)
    }
}

// MARK: - iOS 26'dan eski iPhone'lar

/// Nino (kullanıcı bildirimi, 21 Kasım 2026): Apple'ın ücretsiz cihaz içi çevirisi iOS 26 ister. iOS 18'de GTA 6 Nino'nun
/// havuzundan çalışır, ama diğer oyunlar için ücretsiz bir Gemini anahtarı gerekir; kullanıcılar bunu anlamıyordu. Bu kart
/// yalnız iOS 26'dan eski sistemlerde ve çevrimiçi bir motor (anahtarıyla) açık değilken görünür; ne olduğunu ve anahtarın
/// nasıl ekleneceğini açıkça yazar.
struct OldIOSTranslationNotice: View {
    @Environment(\.locale) private var locale
    /// Anahtarın ekleneceği yere götürür (ana ekranda Ayarlar açılır, Ayarlar'da Gemini seçilir).
    var onAddKey: (() -> Void)?

    /// Kart görünmeli mi.
    @MainActor static func applies(_ model: PhoneModel) -> Bool {
        (!Translator.isAvailable || debugForced) && !model.onlineTranslationActive
    }

    /// Hata ayıklama: COUCHSUBS_FAKE_OLD_IOS=1 ile iOS 26'da da görünür (ekran görüntüsü için).
    private static var debugForced: Bool {
        #if DEBUG
        ProcessInfo.processInfo.environment["COUCHSUBS_FAKE_OLD_IOS"] == "1"
        #else
        false
        #endif
    }

    private func t(_ key: String) -> String { UILanguage.text(key, locale) }

    var body: some View {
        let shape = RoundedRectangle(cornerRadius: Mobile.Radius.tile, style: .continuous)
        VStack(alignment: .leading, spacing: 10) {
            Label {
                Text(verbatim: t("oldios.title")).font(.headline).foregroundStyle(Mobile.Palette.text)
            } icon: {
                Image(systemName: "info.circle.fill").foregroundStyle(Mobile.Palette.warning)
            }
            Text(verbatim: String(format: t("oldios.body"), UIDevice.current.systemVersion))
                .font(.subheadline)
                .foregroundStyle(Mobile.Palette.secondary)
                .fixedSize(horizontal: false, vertical: true)
            ViewThatFits(in: .horizontal) {
                HStack(spacing: 10) { buttons }
                VStack(alignment: .leading, spacing: 8) { buttons }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(Mobile.Space.tile)
        .background(Mobile.Palette.warning.opacity(0.08), in: shape)
        .overlay(shape.strokeBorder(Mobile.Palette.warning.opacity(0.35), lineWidth: 1))
    }

    @ViewBuilder private var buttons: some View {
        if let onAddKey {
            Button(action: onAddKey) {
                Label(t("oldios.add"), systemImage: "key.fill")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.white)
                    .padding(.horizontal, 14).padding(.vertical, 9)
                    .background(Mobile.Palette.accent, in: Capsule())
            }
            .buttonStyle(.plain)
        }
        Link(destination: AIProvider.gemini.keyPage) {
            Label(t("oldios.get"), systemImage: "arrow.up.right.square")
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(Mobile.Palette.accent)
                .padding(.vertical, 9)
        }
    }
}
