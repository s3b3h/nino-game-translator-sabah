// SPDX-License-Identifier: AGPL-3.0-only

import CouchSubsCore
import SwiftUI

/// Nino: ana ekranın tek düğmesi. Hap biçimli iz ve üstünde kayan cam bir küre: kapalıyken küre solda, iz soğuk
/// mavi-gri; sürükleyip ya da tıklayıp açınca küre sağa kayar, iz bayrak kırmızısına döner ve kürenin içinde ay yıldız
/// belirir. Altında PS5 ve TV'nin durumu ve çeviri sürerken son satır.
struct GlassTranslateToggle: View {
    @EnvironmentObject private var model: AppModel
    @State private var drag: CGFloat = 0
    @State private var hovering = false

    static let flagRed = Color(red: 0.89, green: 0.04, blue: 0.09)
    private static let flagDeep = Color(red: 0.66, green: 0.02, blue: 0.08)
    private static let offTop = Color(red: 0.47, green: 0.55, blue: 0.70)
    private static let offBottom = Color(red: 0.30, green: 0.36, blue: 0.52)

    static let width: CGFloat = 400
    private var width: CGFloat { Self.width }
    private let height: CGFloat = 92
    private let knob: CGFloat = 116

    private var on: Bool { model.isRunning || DebugPreview.live }
    private var canUse: Bool { model.isRunning || (model.canStart && !model.isStarting) }

    var body: some View {
        let travel = width - height
        let base: CGFloat = on ? travel : 0
        let x = min(max(base + drag, 0), travel)
        let progress = travel > 0 ? x / travel : 0

        ZStack(alignment: .leading) {
            track(progress: progress)
            label(progress: progress)
            GlassKnob(size: knob, progress: progress, starting: model.isStarting)
                .scaleEffect(hovering ? 1.04 : 1)
                // Küre izin yüksekliğinden büyük: iki ucta izin dışına taşar (cam baloncuk görünümü).
                .offset(x: x - (knob - height) / 2)
                .gesture(DragGesture(minimumDistance: 2)
                    .onChanged { drag = $0.translation.width }
                    .onEnded { value in
                        let end = base + value.translation.width
                        withAnimation(.spring(response: 0.45, dampingFraction: 0.78)) { drag = 0 }
                        if !on && end > travel * 0.6 { toggle() } else if on && end < travel * 0.4 { toggle() }
                    })
                .onTapGesture { toggle() }
                .onHover { h in withAnimation(.spring(response: 0.3)) { hovering = h } }
        }
        .frame(width: width, height: height)
        .animation(.spring(response: 0.55, dampingFraction: 0.8), value: on)
        .opacity(canUse || !model.canStart ? 1 : 0.6)
        .contentShape(Capsule())
        .onTapGesture { toggle() }
        .accessibilityElement()
        .accessibilityLabel(Text(on ? "Stop translating" : "Start translating"))
        .accessibilityAddTraits(.isButton)
        .accessibilityAction { toggle() }
    }

    private func track(progress: CGFloat) -> some View {
        ZStack {
            Capsule().fill(LinearGradient(colors: [Self.offTop, Self.offBottom], startPoint: .top, endPoint: .bottom))
            Capsule().fill(LinearGradient(colors: [Self.flagRed, Self.flagDeep], startPoint: .top, endPoint: .bottom))
                .opacity(progress)
            // Camın üst parlaklığı.
            Capsule()
                .fill(LinearGradient(colors: [Color.white.opacity(0.35), Color.white.opacity(0)], startPoint: .top, endPoint: .center))
                .padding(3)
            Capsule().strokeBorder(Color.white.opacity(0.45), lineWidth: 1)
        }
        .shadow(color: (progress > 0.5 ? Self.flagRed : Self.offBottom).opacity(0.25 + 0.35 * progress), radius: 22, y: 10)
    }

    private func label(progress: CGFloat) -> some View {
        ZStack {
            VStack(alignment: .trailing, spacing: 2) {
                Text(offTitle).font(.system(size: 22, weight: .semibold, design: .rounded))
                Text(offSubtitle).font(.system(size: 12, weight: .medium)).opacity(0.8)
            }
            .frame(maxWidth: .infinity, alignment: .trailing)
            .padding(.trailing, 30)
            .opacity(1 - progress)
            VStack(alignment: .leading, spacing: 2) {
                Text("Turkish").font(.system(size: 26, weight: .bold, design: .rounded))
                Text("Subtitles are on").font(.system(size: 12, weight: .medium)).opacity(0.85)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.leading, 34)
            .opacity(progress)
        }
        .foregroundStyle(.white)
        .allowsHitTesting(false)
    }

    private var offTitle: LocalizedStringKey {
        if model.isStarting { return "Connecting…" }
        if !model.canStart { return "Connect your PS5" }
        return "Turn on"
    }

    private var offSubtitle: LocalizedStringKey {
        model.canStart || model.isStarting ? "Turkish subtitles" : "Tap to start setup"
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

/// Cam küre: içinde izin renginde küçük bir disk ve onun üstünde simge (kapalı: güç, açık: ay yıldız).
private struct GlassKnob: View {
    let size: CGFloat
    let progress: CGFloat
    let starting: Bool

    var body: some View {
        let inner = size * 0.62
        ZStack {
            // Kürenin arkasındaki renkli disk (iz rengini taşır).
            Circle()
                .fill(GlassTranslateToggle.flagRed.opacity(progress))
                .background(Circle().fill(Color(red: 0.36, green: 0.43, blue: 0.60)))
                .frame(width: inner, height: inner)
            if starting {
                ProgressView().controlSize(.regular).tint(.white)
            } else {
                Image(systemName: "power")
                    .font(.system(size: inner * 0.42, weight: .bold))
                    .foregroundStyle(.white)
                    .opacity(1 - progress)
                CrescentStar(background: GlassTranslateToggle.flagRed)
                    .frame(width: inner * 0.72, height: inner * 0.72)
                    .opacity(progress)
                    .scaleEffect(0.7 + 0.3 * progress)
            }
            // Cam: buzlu dolgu, kenar ışığı ve sol üstte parlama.
            Circle()
                .fill(.ultraThinMaterial)
                .opacity(0.35)
            Circle()
                .strokeBorder(LinearGradient(colors: [Color.white.opacity(0.95), Color.white.opacity(0.15), Color.white.opacity(0.6)],
                                             startPoint: .topLeading, endPoint: .bottomTrailing), lineWidth: 2)
            Ellipse()
                .fill(LinearGradient(colors: [Color.white.opacity(0.65), Color.white.opacity(0)], startPoint: .top, endPoint: .bottom))
                .frame(width: size * 0.55, height: size * 0.28)
                .offset(x: -size * 0.12, y: -size * 0.28)
                .blur(radius: 2)
        }
        .frame(width: size, height: size)
        .compositingGroup()
        .shadow(color: Color.black.opacity(0.18), radius: 14, y: 8)
    }
}

/// Bayraktaki ay yıldız: beyaz ay (iç daire zemin rengiyle oyulur) ve ucu aya bakan beş köşeli yıldız.
struct CrescentStar: View {
    let background: Color

    var body: some View {
        GeometryReader { geo in
            let s = min(geo.size.width, geo.size.height)
            let r = s * 0.42
            ZStack {
                Circle().fill(.white).frame(width: 2 * r, height: 2 * r).position(x: s * 0.42, y: s / 2)
                Circle().fill(background).frame(width: 1.6 * r, height: 1.6 * r).position(x: s * 0.42 + r * 0.32, y: s / 2)
                Star(points: 5).fill(.white).frame(width: s * 0.34, height: s * 0.34).position(x: s * 0.8, y: s / 2)
            }
            .frame(width: s, height: s)
        }
        .aspectRatio(1, contentMode: .fit)
    }
}

/// Beş köşeli yıldız; bir ucu sola (aya) bakar.
struct Star: Shape {
    let points: Int

    func path(in rect: CGRect) -> Path {
        let center = CGPoint(x: rect.midX, y: rect.midY)
        let outer = min(rect.width, rect.height) / 2
        let inner = outer * 0.382
        var path = Path()
        for i in 0..<(points * 2) {
            let angle = Double.pi + Double(i) * Double.pi / Double(points)
            let radius = i.isMultiple(of: 2) ? outer : inner
            let point = CGPoint(x: center.x + CGFloat(cos(angle)) * radius, y: center.y + CGFloat(sin(angle)) * radius)
            if i == 0 { path.move(to: point) } else { path.addLine(to: point) }
        }
        path.closeSubpath()
        return path
    }
}

/// Nino: çeviri açılınca düğmenin üstünde beliren sade TV: ince çerçeve, ayak, sol üstte "CANLI" ve altta seçili
/// temayla o an TV'ye giden Türkçe satır. Altında küçük gri İngilizce aslı. Eski önizlemedeki gibi demo cümleleri ve
/// üst üste binen İngilizce/Türkçe yoktur; yalnız gerçek satır gösterilir.
struct LiveTVScreen: View {
    @EnvironmentObject private var model: AppModel
    static let width: CGFloat = 580

    private var translation: String { DebugPreview.live ? DebugPreview.sample(for: model.settings.targetLanguage) : model.lastTranslation }
    private var source: String { DebugPreview.live ? DebugPreview.sampleSource(for: model.settings.targetLanguage) : model.lastSource }

    var body: some View {
        let height = Self.width * 9 / 16
        VStack(spacing: 0) {
            ZStack {
                // Çerçeve ve ekran.
                RoundedRectangle(cornerRadius: 18, style: .continuous)
                    .fill(Color(red: 0.05, green: 0.05, blue: 0.07))
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .fill(LinearGradient(colors: [Color(red: 0.10, green: 0.13, blue: 0.24), Color(red: 0.16, green: 0.10, blue: 0.20)],
                                         startPoint: .topLeading, endPoint: .bottomTrailing))
                    .overlay(
                        RadialGradient(colors: [GlassTranslateToggle.flagRed.opacity(0.18), .clear],
                                       center: .bottomTrailing, startRadius: 10, endRadius: Self.width * 0.6)
                            .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                    )
                    .padding(7)
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
                        if translation.isEmpty {
                            Text("Waiting for the next subtitle…")
                                .font(.system(size: 15, weight: .medium))
                                .foregroundStyle(Color.white.opacity(0.55))
                        } else {
                            ThemedSubtitle(text: translation, style: model.settings.style, fontSize: 27)
                                .id(translation)
                                .transition(.opacity.combined(with: .offset(y: 6)))
                        }
                    }
                    .padding(.bottom, 10)
                }
                .padding(20)
            }
            .frame(width: Self.width, height: height)
            .shadow(color: Color.black.opacity(0.28), radius: 24, y: 14)
            // Ayak.
            RoundedRectangle(cornerRadius: 2).fill(Color(red: 0.12, green: 0.12, blue: 0.15))
                .frame(width: 34, height: 14)
            Capsule().fill(Color(red: 0.12, green: 0.12, blue: 0.15)).frame(width: 150, height: 6)
            Text(verbatim: source.isEmpty ? " " : source)
                .font(.csCallout)
                .italic()
                .foregroundStyle(Color.csSecondary)
                .lineLimit(1)
                .frame(maxWidth: Self.width)
                .padding(.top, 10)
        }
        .animation(.easeOut(duration: 0.3), value: translation)
        .accessibilityElement(children: .combine)
    }
}

/// Yalnız geliştirici derlemesi: PS5'e bağlanmadan tasarımı görmek ve ekran görüntüsü almak için. `NINO_PREVIEW_LIVE=1`
/// ana ekranı çeviri açıkmış gibi çizer; `NINO_PREVIEW_STATE=splash|connecting|live` salon sahnesinin o durumunu,
/// `NINO_PREVIEW_HOME=livingRoom` salon arayüzünü seçer. Yayın derlemesinde hepsi kapalıdır.
enum DebugPreview {
    private static var environment: [String: String] {
        #if DEBUG
        ProcessInfo.processInfo.environment
        #else
        [:]
        #endif
    }

    static let state: String? = environment["NINO_PREVIEW_STATE"] ?? (environment["NINO_PREVIEW_LIVE"] != nil ? "live" : nil)
    static let live: Bool = state != nil
    static var isActive: Bool { state != nil }
    static let home: HomeStyle? = environment["NINO_PREVIEW_HOME"].flatMap(HomeStyle.init(rawValue:))
    /// Önizlemedeki örnek Türkçe satır.
    static let sample = "Bu iş daha bitmedi."
    /// Nino: önizlemedeki örnek satır çeviri diline göre (Arapçada sağdan sola görünüşü denemek için).
    static func sample(for target: String) -> String {
        target == "ar" ? "ARTHUR: أين المخيم؟ يجب أن نذهب، Dutch ينتظرنا." : sample
    }
    static func sampleSource(for target: String) -> String {
        target == "ar" ? "ARTHUR: Where is the camp? We have to go, Dutch is waiting." : "This isn't over."
    }
}

/// Nino: pencerenin en altındaki ince şerit: solda PS5 ve TV durumu (renkli nokta + kısa yazı), sağda Tema · Çıkış ·
/// Çeviri kısayolları. Kutusuz, tek satır; ortada yalnız TV ve düğme kalır.
struct MainBottomBar: View {
    @EnvironmentObject private var model: AppModel
    let open: (SettingsSection) -> Void

    var body: some View {
        VStack(spacing: 0) {
            Rectangle().fill(Color.ninoGlassEdge).frame(height: 1)
            HStack(spacing: 22) {
                status(title: model.usesGameWindow ? String(localized: "Game window") : model.usesCaptureCard ? String(localized: "Capture card") : "PS5", value: ps5Status, tone: AppModel.ps5Tone(model.sessionState, running: model.isRunning))
                if model.showsOnTV {
                    if model.hasTV {
                        status(title: "TV",
                               value: model.tvClients > 0 ? String(localized: "Connected") : String(localized: "Waiting for the TV app"),
                               tone: AppModel.tvTone(clients: model.tvClients, running: model.isRunning))
                    } else {
                        Button { model.step = .tv } label: {
                            status(title: "TV", value: String(localized: "Connect a TV") + " ›", tone: .warning)
                        }
                        .buttonStyle(.plain)
                    }
                }
                Spacer(minLength: 12)
                // Nino: "Tema" kısayolu kaldırıldı (Ayarlar › Altyazı görünümü'nde duruyor). Burada o an GERÇEKTEN kullanılan
                // çeviri yazar: GTA 6 tanınınca (ve havuz o dilde çeviriyorsa) Nino'nun havuzu, başka oyunda ya da oyun
                // henüz tanınmamışken kullanıcının seçtiği motor. Oyun değişince kendiliğinden güncellenir.
                link(title: "Translation",
                     value: Text(verbatim: model.liveGamePoolFirst && model.ninoPoolActive ? String(localized: "Nino · GTA 6 active")
                                 : model.settings.translationEngine == .free ? String(localized: "Free") : model.settings.translationEngine.displayName)) { open(.translation) }
            }
            .padding(.horizontal, Theme.space("xl"))
            .frame(height: 44)
            // Nino: ortada güncelleme denetimi; yeni sürüm varsa hemen indirip kurar.
            .overlay { UpdateCheckLink() }
        }
    }

    private var ps5Status: String {
        if !model.usesGameWindow, !model.usesCaptureCard, !model.isRunning, let console = model.console {
            return String(format: String(localized: "%@ · ready"), console.name.isEmpty ? "PS5" : console.name)
        }
        return model.ps5StatusText
    }

    private func status(title: String, value: String, tone: StatusTone) -> some View {
        HStack(spacing: 7) {
            Circle().fill(tone.color).frame(width: 7, height: 7)
            Text(verbatim: title).fontWeight(.semibold).foregroundStyle(Color.csText)
            Text(verbatim: value).foregroundStyle(Color.csSecondary).lineLimit(1)
        }
        .font(.csCaption)
    }

    private func link(title: LocalizedStringKey, value: Text, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 5) {
                Text(title).foregroundStyle(Color.csSecondary)
                value.fontWeight(.semibold).foregroundStyle(Color.csText).lineLimit(1)
                Image(systemName: "chevron.right").font(.system(size: 8, weight: .bold)).foregroundStyle(Color.csSecondary)
            }
            .font(.csCaption)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}

/// Nino: alt şeridin ortasındaki güncelleme durumu. Güncelse "Güncel" ve yanında yenile düğmesi; yeni sürüm bulununca
/// kendiliğinden iner ("… indiriliyor"), inince "Güncelleme hazır · Yeniden başlat" görünür: tek tıkla kurulur ve Nino
/// yeniden açılır (çeviri sürüyorsa yeniden açılınca kendiliğinden sürer). Boştayken sorulmadan kurulur.
struct UpdateCheckLink: View {
    @ObservedObject private var updates = NinoUpdates.shared
    @State private var hovering = false

    var body: some View {
        if updates.ready {
            pill(icon: "arrow.clockwise.circle.fill", title: "Update ready · Restart") { updates.open() }
        } else if let version = updates.available?.version {
            if updates.downloading {
                HStack(spacing: 6) {
                    ProgressView().controlSize(.mini)
                    Text("Downloading \(version)…").lineLimit(1)
                }
                .font(.csCaption)
                .foregroundStyle(Color.csSecondary)
            } else {
                pill(icon: "arrow.down.circle.fill", title: "New version \(version) · Update") { updates.open() }
            }
        } else {
            HStack(spacing: 6) {
                HStack(spacing: 5) {
                    if updates.state == .upToDate { Image(systemName: "checkmark.circle").font(.system(size: 10, weight: .bold)) }
                    Text(status).lineLimit(1)
                }
                .font(.csCaption)
                .foregroundStyle(Color.csSecondary)
                // Yenile: şimdi yeniden bakar.
                Button { Task { await updates.check(force: true) } } label: {
                    Image(systemName: "arrow.clockwise")
                        .font(.system(size: 10, weight: .bold))
                        .foregroundStyle(hovering ? Color.csText : Color.csSecondary)
                        .frame(width: 22, height: 22)
                        .background(Circle().fill(Color.csSecondary.opacity(hovering ? 0.18 : 0.10)))
                        .contentShape(Circle())
                        .rotationEffect(.degrees(updates.state == .checking ? 360 : 0))
                        .animation(updates.state == .checking ? .linear(duration: 0.9).repeatForever(autoreverses: false) : .default,
                                   value: updates.state == .checking)
                }
                .buttonStyle(.plain)
                .disabled(updates.state == .checking)
                .onHover { hovering = $0 }
                .help(Text("Check for updates"))
                .accessibilityLabel(Text("Check for updates"))
            }
        }
    }

    private var status: LocalizedStringKey {
        switch updates.state {
        case .checking: return "Checking…"
        case .upToDate: return "Up to date"
        default: return "Check for updates"
        }
    }

    private func pill(icon: String, title: LocalizedStringKey, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 5) {
                Image(systemName: icon).font(.system(size: 11, weight: .bold))
                Text(title).lineLimit(1)
            }
            .font(.csCaption.weight(.semibold))
            .foregroundStyle(Color.white)
            .padding(.horizontal, 12).padding(.vertical, 5)
            .background(Capsule().fill(Color.csAccent))
            .contentShape(Capsule())
        }
        .buttonStyle(.plain)
    }
}
