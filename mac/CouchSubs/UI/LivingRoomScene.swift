// SPDX-License-Identifier: AGPL-3.0-only

import CouchSubsCore
import SwiftUI

/// Nino: ikinci ana ekran arayüzü ("Salon"). Kullanıcının seçtiği saydam salon görseli (duvarda TV, metal sehpa, konsol,
/// duvar prizi; `Assets/LivingRoom`) sabit durur. Üstüne TV ekranının içi ve konsoldan gelen kablonun ucundaki fiş, arkasına
/// mavi LED ışıklar (TV'nin arkası ve sehpanın altı) çizilir; ışıklar yalnız fiş takılıyken yanar. Fiş prize takılınca (tıklayarak ya da sürükleyerek) çeviri başlar: TV'de Nino'nun açılış
/// animasyonu oynar, ardından oyundaki altyazılar Türkçe akar. Fiş çekilince çeviri durur, TV kararır.
///
/// Görselden sehpanın dışında kalan kablo ve fiş silindi (kodla çizilir).
/// Not: konsolun biçimi hâlâ Sony'nin tasarımına benzer; mağazaya gönderilmeden önce markasız bir çizimle
/// değiştirilmelidir (bkz. CLAUDE.md, Marka). Koordinatlar görselin piksel ölçüsündedir (1672×941).
struct LivingRoomScene: View {
    @EnvironmentObject private var model: AppModel
    /// Sahneye ayrılan alan; görsel buna sığacak kadar küçülür (büyümez).
    let available: CGSize
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    @State private var drag: CGSize = .zero
    @State private var splashDone = false
    @State private var splashID = UUID()

    static let canvas = CGSize(width: 1672, height: 941)
    private static let screen = CGRect(x: 149, y: 40, width: 1151, height: 595)
    private static let tvFrame = CGRect(x: 139, y: 27, width: 1171, height: 621)
    private static let standFrame = CGRect(x: 49, y: 713, width: 1502, height: 160)
    private static let logicalScreen = CGSize(width: 588, height: 588 * 595 / 1151)
    private static let socket = CGPoint(x: 1564, y: 378)
    /// Görselde kalan kablonun sehpanın sağ ucundaki ucu; çizilen kablo buradan devam eder.
    private static let cableStart = CGPoint(x: 1550, y: 734)
    /// Fiş çıkıkken sehpanın yanından sarkar (görseldeki yeri).
    private static let hanging = CGPoint(x: 1600, y: 885)

    /// Fiş prizde mi: çeviri açık ya da açılıyor. Başlatma başarısız olursa fiş kendiliğinden geri düşer.
    private var plugged: Bool { model.isRunning || model.isStarting || DebugPreview.state != nil }

    var body: some View {
        let scale = min(1, available.width / Self.canvas.width, available.height / Self.canvas.height)
        ZStack(alignment: .topLeading) {
            leds
            Image("LivingRoom")
                .resizable()
                .frame(width: Self.canvas.width, height: Self.canvas.height)
            // Görseldeki ekranın hiçbir anda (geçişlerde bile) görünmemesi için altta siyah zemin.
            Color.black
                .frame(width: Self.screen.width, height: Self.screen.height)
                .offset(x: Self.screen.minX, y: Self.screen.minY)
            // Ekran içeriği 588 noktalık bir TV'ye göre çizilir ve görseldeki ekrana büyütülür (yazılar orantılı kalır).
            screenContent(size: Self.logicalScreen)
                .frame(width: Self.logicalScreen.width, height: Self.logicalScreen.height)
                .scaleEffect(Self.screen.width / Self.logicalScreen.width, anchor: .topLeading)
                .frame(width: Self.screen.width, height: Self.screen.height, alignment: .topLeading)
                .clipped()
                .offset(x: Self.screen.minX, y: Self.screen.minY)
            // Prize tıklamak da fişi takar/çıkarır.
            Color.clear
                .frame(width: 120, height: 120)
                .contentShape(Rectangle())
                .position(Self.socket)
                .onTapGesture { toggle() }
            cable
            plug
        }
        .frame(width: Self.canvas.width, height: Self.canvas.height, alignment: .topLeading)
        .scaleEffect(scale, anchor: .topLeading)
        .frame(width: Self.canvas.width * scale, height: Self.canvas.height * scale, alignment: .topLeading)
        // TV ünitesi (sehpa) pencerenin tam ortasında dursun: görselde sağda priz ve konsol olduğu için sehpa biraz soldadır.
        .offset(x: (Self.canvas.width / 2 - Self.standFrame.midX) * scale)
        .animation(reduceMotion ? nil : .spring(response: 0.5, dampingFraction: 0.78), value: plugged)
        .onChange(of: plugged) { now in
            // Her takışta açılış animasyonu baştan oynar.
            if now { splashDone = false; splashID = UUID() }
        }
        .onAppear { if DebugPreview.state == "live" || model.isRunning { splashDone = true } }
        .task {
            // Önizleme: uygulamanın kendi açılış ekranı bitince TV'deki açılış animasyonu yeniden oynar (görülebilsin).
            guard DebugPreview.state == "splash" else { return }
            try? await Task.sleep(for: .seconds(3.5))
            splashDone = false
            splashID = UUID()
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Text(plugged ? "Stop translating" : "Start translating"))
        .accessibilityAddTraits(.isButton)
        .accessibilityAction { toggle() }
    }

    @ViewBuilder
    private func screenContent(size: CGSize) -> some View {
        if !plugged {
            ZStack {
                Color.black
                Text("NO SIGNAL")
                    .font(.system(size: 13, weight: .semibold, design: .monospaced))
                    // Nino: harf aralığı Arapça harflerin birleşmesini bozar.
                    .tracking(TargetLanguage.containsArabic(String(localized: "NO SIGNAL")) ? 0 : 3)
                    .foregroundStyle(Color.white.opacity(0.28))
            }
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

    /// Çeviri açık: oyun sahnesi gibi koyu ekran, sol üstte CANLI, altta seçili temayla Türkçe satır.
    private var liveScreen: some View {
        // PS5 görüntüsü gelmiyorsa (bağlanıyor, bulunamadı, koptu) altyazı yerine bağlantının durumu yazılır.
        let streaming: Bool = { if case .streaming = model.sessionState { return true }; return false }()
        let failed = !DebugPreview.isActive && !streaming
        let connecting = DebugPreview.state == "connecting"
        let translation = DebugPreview.isActive ? (DebugPreview.state == "live" ? DebugPreview.sample(for: model.settings.targetLanguage) : "") : model.lastTranslation
        return ZStack {
            LinearGradient(colors: [Color(red: 0.09, green: 0.12, blue: 0.24), Color(red: 0.15, green: 0.09, blue: 0.18)],
                           startPoint: .topLeading, endPoint: .bottomTrailing)
            VStack {
                HStack {
                    HStack(spacing: 6) {
                        LiveDot(color: GlassTranslateToggle.flagRed)
                        Text("LIVE").font(.system(size: 11, weight: .bold)).tracking(1.2).foregroundStyle(.white)
                    }
                    .padding(.horizontal, 10).frame(height: 24)
                    .background(Capsule().fill(Color.black.opacity(0.4)))
                    Spacer()
                }
                Spacer()
                Group {
                    if failed || connecting {
                        // PS5 bağlanamadıysa sonsuz animasyon yerine sebebi yazılır.
                        Text(verbatim: model.ps5StatusText)
                            .font(.system(size: 15, weight: .medium))
                            .foregroundStyle(Color.white.opacity(0.7))
                            .multilineTextAlignment(.center)
                    } else if translation.isEmpty {
                        Text("Waiting for the next subtitle…")
                            .font(.system(size: 15, weight: .medium))
                            .foregroundStyle(Color.white.opacity(0.55))
                    } else {
                        ThemedSubtitle(text: translation, style: model.settings.style, fontSize: 26)
                            .id(translation)
                            .transition(.opacity.combined(with: .offset(y: 6)))
                    }
                }
                .padding(.bottom, 8)
            }
            .padding(18)
        }
        .animation(.easeOut(duration: 0.3), value: translation)
    }

    /// Mavi LED'ler: TV'nin arkasından duvara vuran ışık ve sehpanın altındaki şerit. Görselin arkasında çizilir; saydam
    /// görselin kenarlarından taşar. Fiş takılınca yanar, çekilince söner.
    private var leds: some View {
        let blue = Color(red: 0.12, green: 0.36, blue: 1.0)
        let tv = Self.tvFrame, stand = Self.standFrame
        return ZStack(alignment: .topLeading) {
            RoundedRectangle(cornerRadius: 30)
                .fill(blue)
                .frame(width: tv.width + 40, height: tv.height + 40)
                .blur(radius: 46)
                .offset(x: tv.minX - 20, y: tv.minY - 20)
            RoundedRectangle(cornerRadius: 10)
                .fill(Color(red: 0.3, green: 0.55, blue: 1.0))
                .frame(width: tv.width + 10, height: tv.height + 10)
                .blur(radius: 12)
                .offset(x: tv.minX - 5, y: tv.minY - 5)
            Capsule()
                .fill(blue)
                .frame(width: stand.width - 60, height: 40)
                .blur(radius: 26)
                .offset(x: stand.minX + 30, y: stand.maxY - 14)
            Capsule()
                .fill(Color(red: 0.45, green: 0.65, blue: 1.0))
                .frame(width: stand.width - 90, height: 8)
                .blur(radius: 4)
                .offset(x: stand.minX + 45, y: stand.maxY - 4)
        }
        .opacity(plugged ? 1 : 0)
        .animation(.easeInOut(duration: reduceMotion ? 0 : 0.8), value: plugged)
        .allowsHitTesting(false)
    }

    private var plugPoint: CGPoint {
        let base = plugged ? Self.socket : Self.hanging
        return CGPoint(x: base.x + drag.width, y: base.y + drag.height)
    }

    /// Sehpanın ucundan fişe giden kablo: çıkıkken aşağı sarkar, takılıyken yukarı, prize kıvrılır.
    private var cable: some View {
        let p = plugPoint
        let end = plugged && drag == .zero ? CGPoint(x: p.x, y: p.y + 30) : CGPoint(x: p.x, y: p.y - 30)
        return Path { path in
            path.move(to: Self.cableStart)
            if plugged && drag == .zero {
                path.addCurve(to: end, control1: CGPoint(x: 1620, y: 720), control2: CGPoint(x: end.x + 10, y: end.y + 170))
            } else {
                path.addCurve(to: end, control1: CGPoint(x: 1585, y: 745), control2: CGPoint(x: end.x - 8, y: end.y - 70))
            }
        }
        .stroke(Color(white: 0.06), style: StrokeStyle(lineWidth: 10, lineCap: .round))
        .shadow(color: .black.opacity(0.25), radius: 3, y: 2)
        .allowsHitTesting(false)
    }

    /// Fiş: çıkıkken siyah gövde ve iki metal uç aşağı bakar; takılıyken prizin önünde yuvarlak siyah kapak görünür.
    private var plug: some View {
        ZStack {
            if plugged && drag == .zero {
                Circle()
                    .fill(LinearGradient(colors: [Color(white: 0.24), Color(white: 0.04)], startPoint: .topLeading, endPoint: .bottomTrailing))
                    .overlay(Circle().strokeBorder(Color.white.opacity(0.18), lineWidth: 1.5))
                    .frame(width: 58, height: 58)
                    .shadow(color: .black.opacity(0.45), radius: 6, y: 4)
            } else {
                VStack(spacing: 0) {
                    RoundedRectangle(cornerRadius: 6, style: .continuous)
                        .fill(Color(white: 0.06))
                        .frame(width: 16, height: 14)
                    RoundedRectangle(cornerRadius: 9, style: .continuous)
                        .fill(LinearGradient(colors: [Color(white: 0.22), Color(white: 0.04)], startPoint: .leading, endPoint: .trailing))
                        .overlay(RoundedRectangle(cornerRadius: 9, style: .continuous).strokeBorder(Color.white.opacity(0.14)))
                        .frame(width: 36, height: 50)
                    HStack(spacing: 14) {
                        Capsule().fill(LinearGradient(colors: [Color(white: 0.92), Color(white: 0.6)], startPoint: .leading, endPoint: .trailing))
                            .frame(width: 6, height: 24)
                        Capsule().fill(LinearGradient(colors: [Color(white: 0.92), Color(white: 0.6)], startPoint: .leading, endPoint: .trailing))
                            .frame(width: 6, height: 24)
                    }
                }
                .shadow(color: .black.opacity(0.3), radius: 4, y: 3)
            }
        }
        // Tıklama ve sürükleme alanı fişten biraz geniş (küçük görünse de kolay yakalansın).
        .frame(width: 120, height: 140)
        .contentShape(Rectangle())
        .scaleEffect(drag == .zero ? 1 : 1.08)
        .position(plugPoint)
        .gesture(DragGesture(minimumDistance: 4)
            .onChanged { drag = $0.translation }
            .onEnded { value in
                let base = plugged ? Self.socket : Self.hanging
                let end = CGPoint(x: base.x + value.translation.width, y: base.y + value.translation.height)
                let nearSocket = hypot(end.x - Self.socket.x, end.y - Self.socket.y) < 140
                withAnimation(.spring(response: 0.45, dampingFraction: 0.75)) { drag = .zero }
                if nearSocket != plugged { toggle() }
            })
        .simultaneousGesture(TapGesture().onEnded { toggle() })
        .help(plugged ? Text("Unplug to stop") : Text("Plug in to turn on Turkish subtitles"))
    }

    private func toggle() {
        // Hazırlık sürerken (bir saniyeden kısa) çekilirse hazırlık biter bitmez durdurulur; tıklama kaybolmaz.
        if model.isStarting {
            Task { @MainActor in
                while model.isStarting { try? await Task.sleep(for: .milliseconds(50)) }
                if model.isRunning { model.stop() }
            }
            return
        }
        if model.isRunning { model.stop() } else if model.canStart { Task { await model.start() } } else { model.step = .console }
    }
}

/// Sahnenin altındaki tek satırlık ipucu.
struct LivingRoomHint: View {
    @EnvironmentObject private var model: AppModel

    var body: some View {
        Text(model.isRunning || DebugPreview.state != nil ? "Unplug to stop" : (model.canStart ? "Plug in to turn on Turkish subtitles" : "Connect your PS5 first"))
            .font(.csCallout)
            .foregroundStyle(Color.csSecondary)
    }
}
