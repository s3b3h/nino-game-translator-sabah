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
            // Nino: salon sahnesi kaydırılmaz: güncelleme şeridi, uyarılar ve ipucundan kalan alanın tamamına sığar.
            if (DebugPreview.home ?? model.settings.homeStyle) == .livingRoom {
                VStack(spacing: Theme.space("m")) {
                    if let release = updates.available { UpdateBanner(version: release.version) { updates.open() } }
                    GeometryReader { scene in
                        LivingRoomScene(available: scene.size)
                            .fixedLeftToRight()
                            .frame(width: scene.size.width, height: scene.size.height)
                    }
                    LivingRoomHint()
                    XboxConnectButton()
                    if model.showsOnComputer {
                        Button("Adjust the subtitle window") { model.overlayAdjusting = true }
                            .buttonStyle(.ghost)
                            .disabled(model.overlayAdjusting)
                    }
                    VStack(spacing: Theme.space("m")) { MainWarnings() }
                        .frame(maxWidth: 640)
                }
                .padding(.horizontal, Theme.space("xl"))
                .padding(.vertical, Theme.space("m"))
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
            // Nino: ana ekran neredeyse tek düğme; pencere ne boyda olursa olsun düğme dikeyde ortada durur.
            GeometryReader { geo in
                ScrollView {
                    VStack(spacing: Theme.space("l")) {
                        if let release = updates.available { UpdateBanner(version: release.version) { updates.open() } }
                        Spacer(minLength: 0)
                        if (DebugPreview.home ?? model.settings.homeStyle) == .livingRoom {
                            // Nino: ikinci arayüz, salon sahnesi (fişi prize tak → çeviri başlar).
                            VStack(spacing: 14) {
                                LivingRoomScene(available: CGSize(width: geo.size.width - 64, height: geo.size.height - 70))
                                    .fixedLeftToRight()
                                LivingRoomHint()
                            }
                            .frame(maxWidth: .infinity)
                        } else {
                        VStack(spacing: model.isRunning || DebugPreview.live ? 20 : 28) {
                            // Çeviri açılınca TV yukarıdan iner, altındakiler aşağı kayar.
                            if model.isRunning || DebugPreview.live {
                                LiveTVScreen()
                                    .fixedLeftToRight()
                                    .transition(.move(edge: .top).combined(with: .opacity).combined(with: .scale(scale: 0.94)))
                            }
                            GlassTranslateToggle()
                                .fixedLeftToRight()
                            LiveLine()
                        }
                        .padding(.vertical, model.isRunning || DebugPreview.live ? 12 : 40)
                        .frame(maxWidth: .infinity)
                        .animation(.spring(response: 0.6, dampingFraction: 0.86), value: model.isRunning)
                        .background(PowerHalo())
                        }
                        XboxConnectButton()
                        if model.showsOnComputer {
                            Button("Adjust the subtitle window") { model.overlayAdjusting = true }
                                .buttonStyle(.ghost)
                                .disabled(model.overlayAdjusting)
                        }
                        VStack(spacing: Theme.space("m")) { MainWarnings() }
                            .frame(maxWidth: 640)
                        Spacer(minLength: 0)
                    }
                    .frame(maxWidth: .infinity, minHeight: geo.size.height)
                    .padding(.horizontal, Theme.space("xl"))
                }
                .scrollIndicators(.never)
            }
            }
            // Durum ve kısayollar en altta tek satırlık ince şeritte (ortada yalnız TV ve düğme).
            MainBottomBar(open: { settingsSection = $0 })
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .task { await updates.check() }
        .sheet(isPresented: $model.showSettings) { SettingsView().appSurface() }
        .sheet(item: $settingsSection) { SettingsView(section: $0).appSurface() }
        .sheet(isPresented: $model.showHistory) { HistoryView().appSurface() }
    }
}

/// Çeviri sürerken TV'ye giden son Türkçe satır (önizleme kaldırıldı; satır düğmenin altında görünür).
private struct LiveLine: View {
    @EnvironmentObject private var model: AppModel

    var body: some View {
        // Çeviri sürerken satır TV ekranında görünür; kapalıyken tek cümlelik açıklama.
        if !model.isRunning && !DebugPreview.live {
            Text("Nino reads the PS5's English subtitles and shows them in Turkish on your TV.")
                .font(.csCallout)
                .foregroundStyle(Color.csSecondary)
                .multilineTextAlignment(.center)
                .frame(maxWidth: 420)
        }
    }
}

/// Düğmenin arkasındaki yumuşak ışık: kapalıyken soluk mavi, açıkken bayrak kırmızısı.
private struct PowerHalo: View {
    @EnvironmentObject private var model: AppModel

    var body: some View {
        Circle()
            .fill(model.isRunning || DebugPreview.live ? GlassTranslateToggle.flagRed.opacity(0.22) : Color.csAccent.opacity(0.10))
            .frame(width: 520, height: 520)
            .blur(radius: 90)
            .animation(.easeInOut(duration: 0.6), value: model.isRunning)
            .allowsHitTesting(false)
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
                StatusTile(symbol: "gamecontroller", title: model.usesGameWindow ? "Game window" : model.usesCaptureCard ? "Capture card" : "PS5", value: model.ps5StatusText,
                           tone: AppModel.ps5Tone(model.sessionState, running: model.isRunning))
                // Altyazı yalnız bilgisayar ekranındaysa TV durumu gösterilmez.
                if model.showsOnTV { TVStatusTile() }
            }
            .fixedSize(horizontal: false, vertical: true)
            if model.isRunning { GameSection(choice: model.gameChoice) }
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
        let onTV = model.showsOnTV
        Button {
            Task { await model.testSubtitle() }
        } label: {
            Label(onTV ? "Test on TV" : "Test on screen", systemImage: onTV ? "tv" : "macwindow")
        }
        .buttonStyle(CSButtonStyle(kind: .secondary, height: "primaryActionHeight"))
        .fixedSize()
        .disabled(onTV && !model.hasTV && !model.showsOnComputer)
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
        // Apple'ın çevirisi bu dili desteklemese de yapay zekâ açıksa satırlar oradan gelir: uyarı gerekmez.
        if model.translatorStatus != .ready && !(model.translatorStatus == .unsupported && model.onlineTranslationActive) {
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
                    } else {
                        HintText(text: "Apple's free translation doesn't support this language yet. Turn on AI translation in Settings › Translation; Gemini is free.")
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
                // Çeviri PS5'ten (ikinci hesap) okunurken: kolu açınca ana hesap seçilmeli (CouchSubs GitHub #231).
                if model.isRunning && model.settings.videoSource == .ps5 {
                    HintText(text: "When you turn on the controller to play, choose your MAIN account on the PS5. Don't play with the second account Nino signs in with, or the controller won't work in the game.")
                }
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
            Text(verbatim: TargetLanguage.displayText(translation))
                .font(.system(size: 28, weight: .semibold))
                .foregroundStyle(Color.csAccentText)
                .multilineTextAlignment(.leading)
                .fixedSize(horizontal: false, vertical: true)
                .subtitleDirection(translation, fill: true)
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
