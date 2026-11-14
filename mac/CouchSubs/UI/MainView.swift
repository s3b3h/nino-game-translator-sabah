// SPDX-License-Identifier: AGPL-3.0-only

import CouchSubsCore
import RemotePlay
import SwiftUI

/// Ana ekran (Nino, tasarım A): ortada TV'nin küçük bir kopyası (seçili temayla akan altyazı, köşede PS5/TV durumu),
/// altında kaydırarak açılan çeviri anahtarı ve tek satır kısayol (tema, çıkış, çeviri).
struct MainView: View {
    @EnvironmentObject private var model: AppModel
    @State private var settingsSection: SettingsSection?
    @ObservedObject private var updates = NinoUpdates.shared

    var body: some View {
        VStack(spacing: 0) {
            MainHeader()
                .padding(.horizontal, Theme.space("xl"))
                .padding(.top, Theme.space("m"))
            ScrollView {
                VStack(spacing: Theme.space("l")) {
                    if let release = updates.available { UpdateBanner(version: release.version) { updates.open() } }
                    TVScreenCard()
                        .padding(.top, Theme.space("s"))
                    SlideToTranslate()
                        .frame(maxWidth: 560)
                    QuickLinks(open: { settingsSection = $0 })
                    if model.settings.output.showsOnComputer {
                        Button("Adjust the subtitle window") { model.overlayAdjusting = true }
                            .buttonStyle(.ghost)
                            .disabled(model.overlayAdjusting)
                    }
                    VStack(spacing: Theme.space("m")) { MainWarnings() }
                        .frame(maxWidth: 640)
                }
                .frame(maxWidth: .infinity)
                .padding(.horizontal, Theme.space("xl"))
                .padding(.bottom, Theme.space("xl"))
            }
            .scrollIndicators(.never)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .task { await updates.check() }
        .sheet(isPresented: $model.showSettings) { SettingsView().appSurface() }
        .sheet(item: $settingsSection) { SettingsView(section: $0).appSurface() }
        .sheet(isPresented: $model.showHistory) { HistoryView().appSurface() }
    }
}

/// TV'nin küçük kopyası: seçili temayla altyazı (çeviri sürerken gerçek satır), sol üstte PS5/TV durumu, sağ üstte canlı.
private struct TVScreenCard: View {
    @EnvironmentObject private var model: AppModel

    var body: some View {
        VStack(spacing: Theme.space("s")) {
            SubtitleStylePreview(style: model.settings.style, size: CGSize(width: 640, height: 360),
                                 live: model.isRunning ? (model.lastTranslation, model.lastSource) : nil)
                .overlay(alignment: .topLeading) {
                    HStack(spacing: 6) {
                        ScreenChip(text: "PS5 · " + model.ps5StatusText,
                                   tone: AppModel.ps5Tone(model.sessionState, running: model.isRunning))
                        if model.settings.output.showsOnTV {
                            if model.hasTV {
                                ScreenChip(text: "TV · " + (model.tvClients > 0 ? String(localized: "Connected") : String(localized: "Waiting for the TV app")),
                                           tone: AppModel.tvTone(clients: model.tvClients, running: model.isRunning))
                            } else {
                                Button { model.step = .tv } label: { ScreenChip(text: String(localized: "Connect a TV") + " ›", tone: .warning) }
                                    .buttonStyle(.plain)
                            }
                        }
                    }
                    .padding(12)
                }
                .overlay(alignment: .topTrailing) {
                    if model.isRunning {
                        HStack(spacing: 6) {
                            LiveDot()
                            Text("LIVE").font(.system(size: 11, weight: .bold)).foregroundStyle(.white)
                        }
                        .padding(.horizontal, 10).frame(height: 26)
                        .background(Capsule().fill(Color.black.opacity(0.45)))
                        .padding(12)
                    } else {
                        Text("SAMPLE").font(.system(size: 11, weight: .bold)).tracking(1.5).foregroundStyle(.white)
                            .padding(.horizontal, 10).frame(height: 24)
                            .background(Capsule().fill(Color.black.opacity(0.4)))
                            .padding(12)
                    }
                }
                .shadow(color: Color.csPro.opacity(0.18), radius: 24, y: 12)
            Text(model.isRunning ? "Live on your TV" : "This is how it will look on your TV")
                .font(.csCaption)
                .foregroundStyle(Color.csSecondary)
        }
    }
}

/// Önizleme ekranının köşesindeki küçük koyu etiket.
private struct ScreenChip: View {
    let text: String
    let tone: StatusTone

    var body: some View {
        HStack(spacing: 6) {
            Circle().fill(tone == .good ? Color(red: 0.37, green: 0.83, blue: 0.6) : (tone == .warning ? Color.orange : Color.white.opacity(0.6)))
                .frame(width: 7, height: 7)
            Text(verbatim: text).font(.system(size: 11, weight: .semibold)).foregroundStyle(.white).lineLimit(1)
        }
        .padding(.horizontal, 10).frame(height: 26)
        .background(Capsule().fill(Color.black.opacity(0.45)))
        .overlay(Capsule().strokeBorder(Color.white.opacity(0.18)))
    }
}

/// Kaydırarak açılan çeviri anahtarı: düğmeyi sağa sürükleyince çeviri başlar, sola sürükleyince durur. Düğmeye
/// tıklamak da aynı işi yapar (erişilebilirlik).
private struct SlideToTranslate: View {
    @EnvironmentObject private var model: AppModel
    @State private var drag: CGFloat = 0
    @State private var hovering = false

    private var canUse: Bool { model.isRunning || (model.canStart && !model.isStarting) }

    var body: some View {
        GeometryReader { geo in
            let knob: CGFloat = 48
            let travel = geo.size.width - knob - 8
            let on = model.isRunning
            let base: CGFloat = on ? travel : 0
            let x = min(max(base + drag, 0), travel)
            let progress = travel > 0 ? x / travel : 0
            ZStack(alignment: .leading) {
                // İz
                Capsule()
                    .fill(LinearGradient(colors: [Color.csAccent.opacity(0.15 + 0.85 * progress), Color(red: 0.0, green: 0.19, blue: 0.52).opacity(progress)],
                                         startPoint: .leading, endPoint: .trailing))
                    .background(Capsule().fill(Color.ninoGlassFill))
                    .overlay(Capsule().strokeBorder(on ? Color.white.opacity(0.35) : Color.ninoGlassEdge))
                // Yazı
                Text(label)
                    .font(.csBody.weight(.semibold))
                    .foregroundStyle(progress > 0.5 ? Color.white : Color.csSecondary)
                    .frame(maxWidth: .infinity)
                    .padding(.leading, on ? 0 : knob)
                    .padding(.trailing, on ? knob : 0)
                    .opacity(model.isStarting ? 0.4 : 1)
                // Düğme
                ZStack {
                    Circle().fill(on ? AnyShapeStyle(Color.white) : AnyShapeStyle(LinearGradient(colors: [Color.csAccentHi, Color(red: 0.0, green: 0.19, blue: 0.52)], startPoint: .top, endPoint: .bottom)))
                    if model.isStarting {
                        ProgressView().controlSize(.small)
                    } else {
                        Image(systemName: on ? "captions.bubble.fill" : "chevron.right.2")
                            .font(.system(size: 18, weight: .bold))
                            .foregroundStyle(on ? Color.csAccent : Color.white)
                    }
                }
                .frame(width: knob, height: knob)
                .shadow(color: Color.csAccent.opacity(0.4), radius: 8, y: 3)
                .scaleEffect(hovering ? 1.05 : 1)
                .offset(x: 4 + x)
                .gesture(DragGesture()
                    .onChanged { drag = $0.translation.width }
                    .onEnded { value in
                        let end = base + value.translation.width
                        withAnimation(.spring(response: 0.4, dampingFraction: 0.8)) { drag = 0 }
                        if !on && end > travel * 0.7 { Task { await model.start() } }
                        if on && end < travel * 0.3 { model.stop() }
                    })
                .onTapGesture { toggle() }
                .onHover { h in withAnimation(.spring(response: 0.3)) { hovering = h } }
            }
            .frame(height: 56)
            .animation(.spring(response: 0.45, dampingFraction: 0.8), value: model.isRunning)
        }
        .frame(height: 56)
        .opacity(canUse ? 1 : 0.55)
        .allowsHitTesting(canUse || !model.canStart)
        .onTapGesture { if !model.canStart && !model.isRunning { model.step = .console } }
        .accessibilityElement()
        .accessibilityLabel(Text(model.isRunning ? "Stop translating" : "Start translating"))
        .accessibilityAddTraits(.isButton)
        .accessibilityAction { toggle() }
    }

    private var label: LocalizedStringKey {
        if model.isStarting { return "Connecting…" }
        if model.isRunning { return "Turkish subtitles are on" }
        if !model.canStart { return "Connect your PS5 first" }
        return "Slide to turn on Turkish subtitles"
    }

    private func toggle() {
        if model.isRunning { model.stop() } else if model.canStart { Task { await model.start() } } else { model.step = .console }
    }
}

/// Tek satır kısayol: Tema · Çıkış · Çeviri; her biri ilgili ayar sayfasını açar.
private struct QuickLinks: View {
    @EnvironmentObject private var model: AppModel
    let open: (SettingsSection) -> Void

    var body: some View {
        HStack(spacing: Theme.space("s")) {
            link(symbol: "paintpalette", title: "Theme", value: Text(model.settings.style.theme.title)) { open(.appearance) }
            dot
            link(symbol: "tv", title: "Output", value: Text(outputName)) { open(.display) }
            dot
            link(symbol: "globe", title: "Translation",
                 value: Text(verbatim: model.settings.translationEngine == .free ? String(localized: "Free") : model.settings.translationEngine.displayName)) { open(.translation) }
        }
        .font(.csCallout)
    }

    private var dot: some View { Text(verbatim: "·").foregroundStyle(Color.csSecondary) }

    private var outputName: LocalizedStringKey {
        switch model.settings.output {
        case .tv: "TV"
        case .computer: "Computer"
        case .both: "Both"
        }
    }

    private func link(symbol: String, title: LocalizedStringKey, value: Text, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 5) {
                Image(systemName: symbol).foregroundStyle(Color.csAccentText)
                Text(title).foregroundStyle(Color.csSecondary)
                value.fontWeight(.semibold).foregroundStyle(Color.csText)
                Image(systemName: "chevron.right").font(.system(size: 10, weight: .bold)).foregroundStyle(Color.csSecondary)
            }
            .padding(.horizontal, 12).frame(height: 32)
            .ninoGlass(in: Capsule())
            .overlay(Capsule().strokeBorder(Color.ninoGlassEdge))
        }
        .buttonStyle(.plain)
    }
}

/// Logo ve ad solda; geçmiş ve ayarlar sağda küçük yuvarlak cam düğmeler.
private struct MainHeader: View {
    @EnvironmentObject private var model: AppModel

    var body: some View {
        HStack(spacing: Theme.space("s")) {
            LogoView(size: 46)
            NinoWordmark(size: 24, alignment: .leading)
            Spacer()
            CircleIconButton(symbol: "clock.arrow.circlepath", help: "History") { model.showHistory = true }
            CircleIconButton(symbol: "gearshape.fill", help: "Settings") { model.showSettings = true }
        }
    }
}

private struct CircleIconButton: View {
    let symbol: String
    let help: LocalizedStringKey
    let action: () -> Void
    @State private var hovering = false

    var body: some View {
        Button(action: action) {
            Image(systemName: symbol)
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(hovering ? Color.csAccentText : Color.csText)
                .frame(width: 36, height: 36)
                .ninoGlass(in: Circle(), interactive: true)
                .overlay(Circle().strokeBorder(Color.ninoGlassEdge))
                .scaleEffect(hovering ? 1.08 : 1)
        }
        .buttonStyle(.plain)
        .help(Text(help))
        .accessibilityLabel(Text(help))
        .onHover { h in withAnimation(.spring(response: 0.3, dampingFraction: 0.7)) { hovering = h } }
    }
}

/// Sol sütun, kendi genişliğinde kayan. İçerik genişliği sabitlenir: dikey `ScrollView` içeriğine her düzen
/// geçişinde kendi genişliğini önermez; pencere içerik boyuna göre yeniden ölçülünce (Ayarlar sayfası açılıp
/// kapanınca) içerik "ideal" genişliğinde, yazılar tek satırda ölçülebiliyor. `MainControls`'ün ideal genişliği
/// sütundan geniştir (456–681 pt); sabitlenmezse karolar sütundan taşıp ortalanır: sol kenar boşluğu daralır,
/// sağda karolar sağ sütuna dayanır ve kenarları kesilir.
struct ControlsColumn: View {
    let width: CGFloat

    var body: some View {
        ScrollView {
            MainControls()
                .padding(.vertical, Theme.space("m"))
                .frame(width: width)
        }
        .scrollIndicators(.never)
        .padding(.vertical, -Theme.space("m"))
        .frame(width: width)
    }
}

/// Sol sütun: başlat/durdur, PS5 ve TV, altyazının yeri, çeviri motoru, kısayol, uyarılar.
struct MainControls: View {
    @EnvironmentObject private var model: AppModel

    var body: some View {
        VStack(alignment: .leading, spacing: Theme.space("gap")) {
            HStack(spacing: Theme.space("m")) {
                StartStopButton()
                TestSubtitleButton()
            }
            HStack(alignment: .top, spacing: Theme.space("gap")) {
                StatusTile(symbol: "gamecontroller", title: "PS5", value: model.ps5StatusText,
                           tone: AppModel.ps5Tone(model.sessionState, running: model.isRunning))
                // Altyazı yalnız bilgisayar ekranındaysa TV durumu gösterilmez.
                if model.settings.output.showsOnTV { TVStatusTile() }
            }
            .fixedSize(horizontal: false, vertical: true)
            SubtitleOutputCard()
            HStack(alignment: .top, spacing: Theme.space("gap")) {
                StatusTile(symbol: "globe", title: "Translation", value: engineName)
                StatusTile(symbol: "keyboard", title: "Shortcut", value: String(localized: "Translate the screen (⌥⌘T)"))
            }
            .fixedSize(horizontal: false, vertical: true)
            MainWarnings()
        }
    }

    private var engineName: String {
        let engine = model.settings.translationEngine
        return engine == .free ? String(localized: "Free") : engine.displayName
    }
}

private struct StartStopButton: View {
    @EnvironmentObject private var model: AppModel

    var body: some View {
        Button {
            Task { model.isRunning ? model.stop() : await model.start() }
        } label: {
            Label(model.isRunning ? "Stop translating" : "Start translating",
                  systemImage: model.isRunning ? "stop.fill" : "play.fill")
                .font(.csHeadline)
        }
        .buttonStyle(CSButtonStyle(kind: model.isRunning ? .danger : .primary, fullWidth: true, height: "primaryActionHeight"))
        .disabled(model.isStarting || (!model.isRunning && !model.canStart))
    }
}

/// Başlat düğmesinin yanında: deneme altyazısını TV'ye (ya da bilgisayar ekranına) gönderir.
private struct TestSubtitleButton: View {
    @EnvironmentObject private var model: AppModel

    var body: some View {
        let onTV = model.settings.output.showsOnTV
        Button {
            Task { await model.testSubtitle() }
        } label: {
            Label(onTV ? "Test on TV" : "Test on screen", systemImage: onTV ? "tv" : "macwindow")
        }
        .buttonStyle(CSButtonStyle(kind: .secondary, height: "primaryActionHeight"))
        .fixedSize()
        .disabled(onTV && !model.hasTV && !model.settings.output.showsOnComputer)
        .help(Text(onTV ? "Sends a sample subtitle to the TV." : "Shows a sample subtitle on this computer's screen."))
    }
}

private struct TVStatusTile: View {
    @EnvironmentObject private var model: AppModel

    var body: some View {
        if model.hasTV {
            StatusTile(symbol: "tv", title: "TV",
                       value: model.tvClients > 0 ? String(localized: "Connected") : String(localized: "Waiting for the TV app"),
                       tone: AppModel.tvTone(clients: model.tvClients, running: model.isRunning))
        } else {
            StatusTile(symbol: "tv", title: "TV", value: String(localized: "Not set up")) {
                Button("Connect a TV") { model.step = .tv }.buttonStyle(.secondary)
            }
        }
    }
}

/// Dil paketi eksik, çevrimiçi motor çeviremiyor, macOS yazıyı okuyamıyor.
private struct MainWarnings: View {
    @EnvironmentObject private var model: AppModel

    private var sourceName: String { Locale.current.localizedString(forLanguageCode: model.settings.sourceLanguage) ?? model.settings.sourceLanguage }
    private var targetName: String { Locale.current.localizedString(forLanguageCode: model.settings.targetLanguage) ?? model.settings.targetLanguage }

    var body: some View {
        if model.translatorStatus != .ready {
            Card {
                if model.translatorStatus == .needsDownload {
                    Label(String(format: String(localized: "The %@–%@ language pack is not downloaded yet."), sourceName, targetName),
                          systemImage: "arrow.down.circle")
                        .font(.csBody.weight(.semibold))
                        .foregroundStyle(Color.csWarning)
                    HintText(text: "Open System Settings › General › Language & Region › Translation Languages and download both languages.")
                    Button("Open Language & Region") {
                        NSWorkspace.shared.open(URL(string: "x-apple.systempreferences:com.apple.Localization-Settings.extension")!)
                    }
                    .buttonStyle(.secondary)
                } else {
                    Label(String(format: String(localized: "Translation from %@ to %@ is not available on this Mac."), sourceName, targetName),
                          systemImage: "exclamationmark.triangle")
                        .font(.csBody.weight(.semibold))
                        .foregroundStyle(Color.csWarning)
                    if !Translator.isAvailable {
                        HintText(text: "Apple's free translation needs macOS 26 or later. Game packs, DeepL and AI translation (Settings › Translation) work on this Mac.")
                    }
                }
            }
        }

        // Çevrimiçi motor çeviremiyor: satırlar bu arada ücretsiz çeviriyle geliyor.
        if model.isRunning, let issue = model.onlineIssue {
            Card {
                Label(String(format: String(localized: "%@ is not translating right now"), model.settings.onlineEngine.displayName),
                      systemImage: "exclamationmark.triangle")
                    .font(.csBody.weight(.semibold))
                    .foregroundStyle(Color.csWarning)
                Text(verbatim: TranslationCard.describe(issue, engine: model.settings.onlineEngine, server: model.settings.localAIServer) + " "
                     + String(localized: "Meanwhile the free translation is used."))
                    .font(.csCallout)
                    .foregroundStyle(Color.csSecondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }

        if let free = model.readingFailedFreeGB {
            Card {
                Label("macOS can't read the text on the screen.", systemImage: "exclamationmark.triangle")
                    .font(.csBody.weight(.semibold))
                    .foregroundStyle(Color.csWarning)
                if free < 10 {
                    HintText(text: LocalizedStringKey(String(format: String(localized: "The disk is almost full (%.1f GB free). macOS needs free space to read text; free up a few GB and start the translation again."), free)))
                } else {
                    HintText(text: "Restart the Mac and start the translation again.")
                }
            }
        }
    }
}

/// Hazır Türkçe çevirisi olan oyunlar kullanılıyor (yalnız İngilizce→Türkçede ve ayar açıkken).
private struct PackInUseTile: View {
    @EnvironmentObject private var model: AppModel

    private var active: Bool {
        model.settings.gamePacks && model.settings.sourceLanguage == "en" && model.settings.targetLanguage == "tr"
            && !model.installedPacks.isEmpty
    }

    var body: some View {
        if active {
            HStack(spacing: Theme.space("m")) {
                TileIcon(symbol: "shippingbox", tint: .csPro)
                Text(verbatim: String(format: String(localized: "Game packs are on · %lld games translated in advance"), model.installedPacks.count))
                    .font(.csBody)
                    .fixedSize(horizontal: false, vertical: true)
                Spacer(minLength: 0)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .tile()
        }
    }
}

/// Son altyazı büyük ve altyazı sarısında, öncekiler altında ikincil renkte; çeviri sürerken sağ üstte canlı nokta.
private struct LiveSubtitlesTile: View {
    @EnvironmentObject private var model: AppModel

    var body: some View {
        VStack(alignment: .leading, spacing: Theme.space("gap")) {
            HStack {
                Text("Live subtitles").font(.csHeadline)
                Spacer()
                if model.isRunning { Pill(text: String(localized: "Translating…"), tone: .success, live: true) }
            }
            if model.lastTranslation.isEmpty {
                Spacer(minLength: 0)
                VStack(spacing: Theme.space("m")) {
                    GradientIcon(symbol: "captions.bubble.fill", size: 64)
                    Text("Subtitles will appear here while you play.")
                        .font(.csBody)
                        .foregroundStyle(Color.csSecondary)
                        .multilineTextAlignment(.center)
                }
                .frame(maxWidth: .infinity)
                .opacity(0.9)
            } else {
                CurrentLine(translation: model.lastTranslation, source: model.lastSource)
                if let metrics = model.lastMetrics { MetricsRow(metrics: metrics) }
                SubtitleHistoryList()
            }
            Spacer(minLength: 0)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .tile()
    }
}

private struct CurrentLine: View {
    let translation: String
    let source: String

    var body: some View {
        VStack(alignment: .leading, spacing: Theme.space("hair")) {
            Text(verbatim: translation)
                .font(.system(size: 28, weight: .semibold))
                .foregroundStyle(Color.csAccentText)
                .fixedSize(horizontal: false, vertical: true)
            Text(verbatim: source)
                .font(.csCaption)
                .foregroundStyle(Color.csSecondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .textSelection(.enabled)
    }
}

/// Son satırın ölçümleri: yazı tanıma, çeviri, karenin gelişinden TV'ye kadar gecikme ve tanıma güveni.
/// Küçük ve sessiz (13 pt, ikincil renk, sabit genişlikte rakamlar).
struct MetricsRow: View {
    let metrics: LineMetrics

    var body: some View {
        Text(verbatim: metrics.summary)
            .font(.csCaption.monospacedDigit())
            .foregroundStyle(Color.csSecondary)
            .lineLimit(1)
            .minimumScaleFactor(0.8)
            .accessibilityLabel(Text("Measurements"))
            .accessibilityValue(Text(verbatim: metrics.summary))
    }
}

/// Kaçırılan satır buradan yeniden okunur (en yenisi üstte; yalnız bu oturumun satırları).
private struct SubtitleHistoryList: View {
    @EnvironmentObject private var model: AppModel

    var body: some View {
        let entries = Array(model.sessionHistory.dropFirst())
        if !entries.isEmpty {
            ScrollView {
                LazyVStack(alignment: .leading, spacing: Theme.space("m")) {
                    ForEach(entries, id: \.id) { entry in
                        VStack(alignment: .leading, spacing: Theme.space("m")) {
                            Divider().overlay(Color.csBorder)
                            HistoryRow(entry: entry)
                        }
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .scrollIndicators(.automatic)
            .accessibilityLabel(Text("Subtitle history"))
        }
    }
}

private struct HistoryRow: View {
    let entry: SubtitleHistory.Entry

    var body: some View {
        VStack(alignment: .leading, spacing: Theme.space("hair")) {
            Text(verbatim: entry.translation)
                .font(.csHeadline.weight(.regular))
                .foregroundStyle(Color.csSecondary)
                .fixedSize(horizontal: false, vertical: true)
            Text(verbatim: entry.source)
                .font(.csCaption)
                .foregroundStyle(Color.csSecondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .textSelection(.enabled)
    }
}


/// Nino: yeni sürüm bildirimi (GitHub'daki son sürüm). Tıklayınca yeni sürüm indirilir.
private struct UpdateBanner: View {
    let version: String
    let action: () -> Void

    var body: some View {
        HStack(spacing: Theme.space("m")) {
            Image(systemName: "arrow.down.circle.fill").font(.system(size: 22)).foregroundStyle(Color.csAccent)
            VStack(alignment: .leading, spacing: 2) {
                Text("A new version of Nino is available").font(.csCallout.weight(.semibold))
                Text(verbatim: "Nino \(version)").font(.csCaption).foregroundStyle(Color.csSecondary)
            }
            Spacer()
            Button("Download", action: action).buttonStyle(.primary)
        }
        .padding(Theme.space("m"))
        .frame(maxWidth: 640)
        .ninoGlass(in: RoundedRectangle(cornerRadius: Theme.radius("card"), style: .continuous))
    }
}
