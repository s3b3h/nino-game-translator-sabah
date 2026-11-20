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

    @State private var drag: CGSize
    @State private var splashDone = false
    /// Prizin çevresindeki ışığın yanıp sönmesi (fiş takılı değilken).
    @State private var socketPulse = false

    /// `drag`: fişin başlangıçtaki kayması; yalnız çizim denemelerinde verilir (fişin prize yaklaşırkenki hâli).
    init(available: CGSize, drag: CGSize = .zero) {
        self.available = available
        _drag = State(initialValue: drag)
    }
    @State private var splashID = UUID()

    static let canvas = CGSize(width: 1672, height: 941)
    /// Nino: sahne konsola göre değişir: PS5'li salon (`Assets/LivingRoom`) ya da kullanıcının Xbox'lı salonu
    /// (`Assets/LivingRoomXbox`, aynı TV, sehpa ve priz). Koordinatlar görsellerin piksel ölçüsündedir.
    struct Layout {
        let image: String
        let screen: CGRect
        let tvFrame: CGRect
        let standFrame: CGRect
        let socket: CGPoint
        /// Kablonun çizilmeye başladığı yer (PS5'te görseldeki kablonun ucu, Xbox'ta konsolun sağ arkası).
        let cableStart: CGPoint
        /// Görseldeki kablonun (varsa) son parçası: çizilen kablo bunun üstünden başlar, ek yeri görünmez. Yoksa boş
        /// (Xbox görselinde kablo yok; kablo `cableStart`taki girişten çıkar).
        var cableLead: [CGPoint] = []
        /// Kablonun çizilen parçasının başladığı yerdeki yönü (birim vektör): görseldeki kablonun bittiği eğimle sürer.
        var cableOut = CGVector(dx: 1, dy: 0.1)
        /// Fiş çıkıkken sehpanın yanından sarkar.
        let hanging: CGPoint
        var logicalScreen: CGSize { CGSize(width: 588, height: 588 * screen.height / screen.width) }

        static let ps5 = Layout(image: "LivingRoom",
                                screen: CGRect(x: 149, y: 40, width: 1151, height: 595),
                                tvFrame: CGRect(x: 139, y: 27, width: 1171, height: 621),
                                standFrame: CGRect(x: 49, y: 713, width: 1502, height: 160),
                                socket: CGPoint(x: 1564, y: 378),
                                cableStart: CGPoint(x: 1550, y: 734),
                                // Görseldeki kablo: PS5'in arkasından yatay çıkar (y≈706), 1523'ten sonra aşağı kıvrılıp
                                // (1552, 727)'de biter (ölçüldü). Çizilen kablo aynı yolu izleyip oradan devam eder.
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

    private var layout: Layout { model.settings.gameConsole == .xbox ? .xbox : .ps5 }

    /// Fiş prizde mi: çeviri açık ya da açılıyor. Başlatma başarısız olursa fiş kendiliğinden geri düşer.
    private var plugged: Bool { (model.isRunning || model.isStarting || DebugPreview.state != nil) && !introHold }
    /// Nino (kullanıcı isteği, 21 Kasım 2026): açılışta fiş bir an çekik görünür, sonra yaylanarak prize takılır (çeviri
    /// kendiliğinden başlasa da). Ardından toplam indirme sayacı 1, 2, 3 diye başlayıp hızlanarak toplam sayıya fırlar.
    @State private var introHold = !LivingRoomScene.introPlayed
    /// Açılış gösterisi uygulama her açıldığında bir kez oynar (ayarlardan dönünce yeniden oynamaz).
    private static var introPlayed = false

    var body: some View {
        let scale = min(1, available.width / Self.canvas.width, available.height / Self.canvas.height)
        ZStack(alignment: .topLeading) {
            leds
            socketGlow
            Image(layout.image)
                .resizable()
                .frame(width: Self.canvas.width, height: Self.canvas.height)
            // Görseldeki ekranın hiçbir anda (geçişlerde bile) görünmemesi için altta siyah zemin.
            Color.black
                .frame(width: layout.screen.width, height: layout.screen.height)
                .offset(x: layout.screen.minX, y: layout.screen.minY)
            // Ekran içeriği 588 noktalık bir TV'ye göre çizilir ve görseldeki ekrana büyütülür (yazılar orantılı kalır).
            screenContent(size: layout.logicalScreen)
                .frame(width: layout.logicalScreen.width, height: layout.logicalScreen.height)
                .scaleEffect(layout.screen.width / layout.logicalScreen.width, anchor: .topLeading)
                .frame(width: layout.screen.width, height: layout.screen.height, alignment: .topLeading)
                .clipped()
                .offset(x: layout.screen.minX, y: layout.screen.minY)
            // Prize tıklamak da fişi takar/çıkarır.
            Color.clear
                .frame(width: 120, height: 120)
                .contentShape(Rectangle())
                .position(layout.socket)
                .onTapGesture { toggle() }
            cable
            plug
        }
        .frame(width: Self.canvas.width, height: Self.canvas.height, alignment: .topLeading)
        .scaleEffect(scale, anchor: .topLeading)
        .frame(width: Self.canvas.width * scale, height: Self.canvas.height * scale, alignment: .topLeading)
        // TV ünitesi (sehpa) pencerenin tam ortasında dursun: görselde sağda priz ve konsol olduğu için sehpa biraz soldadır.
        .offset(x: (Self.canvas.width / 2 - layout.standFrame.midX) * scale)
        .animation(reduceMotion ? nil : .spring(response: 0.5, dampingFraction: 0.78), value: plugged)
        .onChange(of: plugged) { now in
            // Her takışta açılış animasyonu baştan oynar.
            if now { splashDone = false; splashID = UUID() }
        }
        .onAppear { if DebugPreview.state == "live" || (Self.introPlayed && model.isRunning) { splashDone = true } }
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

    /// TV'nin sağ üst köşesindeki toplam indirme sayısı (sunucudan; bkz. `DownloadCounter`).
    @ObservedObject private var downloads = DownloadCounter.shared

    @ViewBuilder
    private func screenContent(size: CGSize) -> some View {
        if !plugged {
            // Açılış gösterisinde sayı fiş takılınca sayılarak çıkar; önce görünmez.
            TVStandbyScreen(downloads: introHold ? nil : downloads.total)
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
            // Nino: oyun tanınınca oyuna özel buzlu fon (GTA 6'da gün batımı); altyazı önünde durur.
            GameBackdrop(gameID: model.liveGameID, poolFirst: model.liveGamePoolFirst)
            VStack {
                HStack {
                    HStack(spacing: 6) {
                        LiveDot(color: GlassTranslateToggle.flagRed)
                        Text("LIVE").font(.system(size: 11, weight: .bold)).tracking(1.2).foregroundStyle(.white)
                    }
                    .padding(.horizontal, 10).frame(height: 24)
                    .background(Capsule().fill(Color.black.opacity(0.4)))
                    Spacer()
                    // Nino: toplam indirme, fiş takılı değilkenki yerinde (sağ üst) kalır.
                    if let total = downloads.total { DownloadHUD(total: total, countsUp: true) }
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

    /// LED'ler: TV'nin arkasından duvara vuran ışık ve sehpanın altındaki şerit. Görselin arkasında çizilir; saydam
    /// görselin kenarlarından taşar. Fiş takılınca yanar, çekilince söner. Her zamanki renk mavidir; GTA 6 tanınınca
    /// (havuz öncelikli oyun) oyunun renklerine döner: solda pembe, sağda açık mavi.
    private var leds: some View {
        let gta = model.liveGamePoolFirst
        let blue = Color(red: 0.12, green: 0.36, blue: 1.0)
        // İki durumda da üç duraklı geçiş: renk değişimi yumuşak canlanır.
        let wide = gta ? [Color(red: 1.0, green: 0.24, blue: 0.62), Color(red: 0.74, green: 0.50, blue: 0.96), Color(red: 0.30, green: 0.78, blue: 1.0)]
                       : [blue, blue, blue]
        let tight = gta ? [Color(red: 1.0, green: 0.52, blue: 0.78), Color(red: 0.84, green: 0.70, blue: 1.0), Color(red: 0.58, green: 0.88, blue: 1.0)]
                        : Array(repeating: Color(red: 0.3, green: 0.55, blue: 1.0), count: 3)
        let strip = gta ? tight : Array(repeating: Color(red: 0.45, green: 0.65, blue: 1.0), count: 3)
        func glow(_ colors: [Color]) -> LinearGradient { LinearGradient(colors: colors, startPoint: .leading, endPoint: .trailing) }
        let tv = layout.tvFrame, stand = layout.standFrame
        return ZStack(alignment: .topLeading) {
            RoundedRectangle(cornerRadius: 30)
                .fill(glow(wide))
                .frame(width: tv.width + 40, height: tv.height + 40)
                .blur(radius: 46)
                .offset(x: tv.minX - 20, y: tv.minY - 20)
            RoundedRectangle(cornerRadius: 10)
                .fill(glow(tight))
                .frame(width: tv.width + 10, height: tv.height + 10)
                .blur(radius: 12)
                .offset(x: tv.minX - 5, y: tv.minY - 5)
            Capsule()
                .fill(glow(wide))
                .frame(width: stand.width - 60, height: 40)
                .blur(radius: 26)
                .offset(x: stand.minX + 30, y: stand.maxY - 14)
            Capsule()
                .fill(glow(strip))
                .frame(width: stand.width - 90, height: 8)
                .blur(radius: 4)
                .offset(x: stand.minX + 45, y: stand.maxY - 4)
        }
        .opacity(plugged ? 1 : 0)
        .animation(.easeInOut(duration: reduceMotion ? 0 : 0.8), value: plugged)
        .animation(.easeInOut(duration: reduceMotion ? 0 : 1.2), value: gta)
        .allowsHitTesting(false)
    }

    private var plugPoint: CGPoint {
        let base = plugged ? layout.socket : layout.hanging
        return CGPoint(x: base.x + drag.width, y: base.y + drag.height)
    }

    /// Nino: fiş takılı değilken prizin kenarlarından taşan, yanıp sönen ışık: fişin nereye takılacağı anlaşılsın.
    /// Görselin arkasında çizilir (priz görselin parçasıdır; ışık kenarlarından taşar). Fiş takılınca söner. "Hareketi
    /// azalt" açıksa yanıp sönmez, sabit yanar.
    private var socketGlow: some View {
        let color = Color(red: 0.30, green: 0.66, blue: 1.0)
        let size = Self.socketSize
        return ZStack {
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .fill(color)
                .frame(width: size + 26, height: size + 26)
                .blur(radius: 18)
                .opacity(socketPulse ? 0.95 : 0.3)
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(Color(red: 0.62, green: 0.84, blue: 1.0))
                .frame(width: size + 8, height: size + 8)
                .blur(radius: 5)
                .opacity(socketPulse ? 1 : 0.45)
        }
        .position(layout.socket)
        .opacity(plugged ? 0 : 1)
        .animation(.easeInOut(duration: reduceMotion ? 0 : 0.5), value: plugged)
        .allowsHitTesting(false)
        .onAppear {
            guard !reduceMotion else { socketPulse = true; return }
            withAnimation(.easeInOut(duration: 0.95).repeatForever(autoreverses: true)) { socketPulse = true }
        }
    }

    /// Görseldeki prizin kenar uzunluğu (sahne pikseli).
    static let socketSize: CGFloat = 86

    /// Fiş çıkıkken uçlarının baktığı yön (radyan; 0 = aşağı, saat yönü artı). Dinlenirken yerçekimiyle aşağı sarkar;
    /// prize yaklaştıkça uçlar prize döner (eskiden hep aşağı bakıyordu, prize götürürken de).
    private var plugTurn: Double {
        Self.plugTurn(plug: plugPoint, socket: layout.socket, rest: layout.hanging)
    }

    /// Yön kuralı (saf işlev, sınanır): priz uzaktayken 0, prize `Self.turnDone` kadar yaklaşınca tam prize dönük.
    static func plugTurn(plug: CGPoint, socket: CGPoint, rest: CGPoint) -> Double {
        let restDistance = hypot(socket.x - rest.x, socket.y - rest.y)
        let distance = hypot(socket.x - plug.x, socket.y - plug.y)
        guard restDistance > turnDone, distance > 1 else { return 0 }
        let t = min(1, max(0, (restDistance - distance) / (restDistance - turnDone)))
        let eased = t * t * (3 - 2 * t)
        // Uçlar dönmeden önce (0, +1) yönüne bakar; θ kadar dönünce (−sin θ, cos θ). Prize bakması için:
        let toward = atan2(-(socket.x - plug.x), socket.y - plug.y)
        return eased * toward
    }

    /// Prize bu kadar yaklaşınca fiş tam prize dönmüş olur (sahne pikseli).
    static let turnDone: CGFloat = 120
    /// Kablonun serbest boyu: fiş konsola yaklaşınca kablo bu boydan artanı kadar sarkar.
    static let cableLength: CGFloat = 330
    static let cableWidth: CGFloat = 8

    /// Konsoldan fişe giden kablo. Görseldeki kablonun (PS5) son parçasının üstünden başlar ki ek yeri belli olmasın;
    /// Xbox'ta konsolun arkasından çıkar. Fişin arkasına fişin ekseni boyunca girer; çıkıkken sarkar, takılıyken
    /// alttan prize kıvrılır.
    private var cable: some View {
        let p = plugPoint
        let inSocket = plugged && drag == .zero
        let turn = plugTurn
        let prong = CGPoint(x: -sin(turn), y: cos(turn))
        let start = layout.cableLead.last ?? layout.cableStart
        let out = layout.cableOut
        return ZStack {
            Path { path in
                path.move(to: layout.cableLead.first ?? layout.cableStart)
                for point in layout.cableLead.dropFirst() { path.addLine(to: point) }
                if inSocket {
                    let end = CGPoint(x: p.x, y: p.y + 30)
                    path.addCurve(to: end, control1: CGPoint(x: start.x + out.dx * 90, y: start.y + out.dy * 90),
                                  control2: CGPoint(x: end.x + 10, y: end.y + 170))
                } else {
                    // Fişin arkası: gövdenin üstündeki kablo boğazı.
                    let back = CGPoint(x: p.x - prong.x * 40, y: p.y - prong.y * 40)
                    let sag = max(0, Self.cableLength - hypot(back.x - start.x, back.y - start.y)) * 0.45
                    path.addCurve(to: back,
                                  control1: CGPoint(x: start.x + out.dx * 70, y: start.y + out.dy * 70 + sag),
                                  control2: CGPoint(x: back.x - prong.x * 80, y: back.y - prong.y * 80 + sag))
                }
            }
            .stroke(Color(white: 0.06), style: StrokeStyle(lineWidth: Self.cableWidth, lineCap: .round, lineJoin: .round))
            .shadow(color: .black.opacity(0.25), radius: 3, y: 2)
            // Xbox'ta kablo konsolun arkasındaki girişten çıkar: küçük bir fiş başı.
            if layout.cableLead.isEmpty {
                RoundedRectangle(cornerRadius: 3, style: .continuous)
                    .fill(Color(white: 0.08))
                    .frame(width: 14, height: 12)
                    .position(layout.cableStart)
            }
        }
        .allowsHitTesting(false)
    }

    /// Fiş: çıkıkken siyah gövde ve iki metal uç; uçlar `plugTurn` yönüne bakar. Takılıyken prizin önünde yuvarlak
    /// siyah kapak görünür.
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
                    RoundedRectangle(cornerRadius: 5, style: .continuous)
                        .fill(Color(white: 0.06))
                        .frame(width: 13, height: 14)
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
                .rotationEffect(.radians(plugTurn))
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
                let base = plugged ? layout.socket : layout.hanging
                let end = CGPoint(x: base.x + value.translation.width, y: base.y + value.translation.height)
                let nearSocket = hypot(end.x - layout.socket.x, end.y - layout.socket.y) < 140
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
        // Nino: Xbox'ta PS5 bağlanmaz; eksik olan TV ya da bu Mac'te açılacak Xbox penceresidir.
        // Fiş takılmaya hazırken burada bir şey yazmaz: ne yapılacağı TV ekranında yazıyor ("Çalıştırmak için fişi prize
        // sürükleyiniz") ve priz yanıp sönüyor; aynı şeyi iki kez söylemeye gerek yok. Satırın yeri korunur (sahne kaymasın).
        let idleReady = !(model.isRunning || DebugPreview.state != nil) && model.canStart
        Text(model.isRunning || DebugPreview.state != nil ? "Unplug to stop"
             : model.canStart ? "Plug in to turn on Turkish subtitles"
             : model.settings.gameConsole == .xbox ? "Connect your TV first, then plug in" : "Connect your PS5 first")
            .font(.csCallout)
            .foregroundStyle(Color.csSecondary)
            .opacity(idleReady ? 0 : 1)
            .accessibilityHidden(idleReady)
    }
}


/// Nino: fiş takılı değilken TV ekranı. Ortada ne yapılacağı ("Çalıştırmak için fişi prize sürükleyiniz"; eskiden
/// "SİNYAL YOK"), sağ üstte toplam indirme.
struct TVStandbyScreen: View {
    let downloads: Int?

    var body: some View {
        ZStack {
            Color.black
            Text("Drag the plug to the socket to start")
                .font(.system(size: 13, weight: .semibold, design: .monospaced))
                // Nino: harf aralığı Arapça harflerin birleşmesini bozar.
                .tracking(TargetLanguage.containsArabic(String(localized: "Drag the plug to the socket to start")) ? 0 : 2)
                .textCase(.uppercase)
                .foregroundStyle(Color.white.opacity(0.4))
                .multilineTextAlignment(.center)
                .padding(.horizontal, 40)
        }
        .overlay(alignment: .topTrailing) {
            if let downloads { DownloadHUD(total: downloads).padding(18) }
        }
    }
}

/// Nino: toplam indirme göstergesi. Oyunlardaki para göstergesi gibi: kalın, hafif eğik, siyah çerçeveli; üstte küçük
/// beyaz başlık, altında yeşil sayı. Yazı tipi sistemdeki "Impact" (yoksa sistemin en kalın yazısı); oyunun kendi
/// logosu ya da yazı tipi kullanılmaz.
struct DownloadHUD: View {
    let total: Int
    /// Nino (kullanıcı isteği, 21 Kasım 2026): fiş takılınca sayı 1, 2, 3 diye yavaş başlar, hızlanıp toplam sayıya fırlar;
    /// sonda oyunun "görev tamam" yazısı gibi büyüyüp parlayarak yerine oturur.
    var countsUp = false

    private static let green = Color(red: 0.48, green: 0.91, blue: 0.48)
    @State private var shown: Int?
    @State private var punch = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        let arabic = TargetLanguage.containsArabic(String(localized: "Total downloads"))
        let value = shown ?? total
        VStack(alignment: .trailing, spacing: 1) {
            outlined(Text("Total downloads").tracking(arabic ? 0 : 0.8), size: 11, color: .white, weight: 1)
                .textCase(.uppercase)
            outlined(Text(verbatim: value.formatted(.number.grouping(.automatic))), size: 27, color: Self.green, weight: 1.5)
                .monospacedDigit()
                .scaleEffect(punch ? 1.32 : 1, anchor: .trailing)
                .shadow(color: Self.green.opacity(punch ? 0.95 : 0), radius: punch ? 14 : 0)
        }
        .task(id: countsUp) {
            guard countsUp, !reduceMotion, total > 3 else { shown = nil; return }
            shown = 0
            // İlk üç sayı tek tek görünür, sonra hız katlanarak artar (toplam ~2,4 sn).
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
        .transformEffect(arabic ? .identity : CGAffineTransform(a: 1, b: 0, c: -0.12, d: 1, tx: 3, ty: 0))
        .fixedSize()
        .accessibilityElement(children: .combine)
    }

    /// Siyah çerçeveli yazı: dört yöne keskin gölge + altta derinlik gölgesi.
    private func outlined(_ text: Text, size: CGFloat, color: Color, weight: CGFloat) -> some View {
        text.font(Font.custom("Impact", size: size).weight(.black))
            .foregroundStyle(color)
            .shadow(color: .black, radius: 0, x: weight, y: 0)
            .shadow(color: .black, radius: 0, x: -weight, y: 0)
            .shadow(color: .black, radius: 0, x: 0, y: weight)
            .shadow(color: .black, radius: 0, x: 0, y: -weight)
            .shadow(color: .black.opacity(0.9), radius: 0, x: 0, y: weight + 1)
    }
}
