// SPDX-License-Identifier: AGPL-3.0-only

import CouchSubsCore
import SwiftUI

/// Ayarların bölümleri; solda kenar çubuğunda listelenir, sağda seçili olan gösterilir.
enum SettingsSection: CaseIterable, Identifiable {
    case interface, appearance, dubbing, translation, packs, language, area, obs, health, updates, about

    var id: Self { self }

    var title: LocalizedStringKey {
        switch self {
        case .interface: "Interface"
        case .appearance: "Subtitle appearance"
        case .dubbing: "Turkish dubbing"
        case .translation: "Translation"
        case .packs: "Game packs"
        case .language: "Language"
        case .area: "Subtitle area"
        case .obs: "OBS overlay"
        case .health: "System health"
        case .updates: "Updates"
        case .about: "About Nino"
        }
    }

    var symbol: String {
        switch self {
        case .interface: "macwindow"
        case .appearance: "captions.bubble"
        case .dubbing: "waveform"
        case .translation: "globe"
        case .packs: "shippingbox"
        case .language: "character.bubble"
        case .area: "rectangle.dashed"
        case .obs: "dot.radiowaves.left.and.right"
        case .health: "waveform.path.ecg"
        case .updates: "arrow.down.circle"
        case .about: "info.circle"
        }
    }
}

extension SettingsSection {
    /// Sistem Ayarları'ndaki gibi her bölümün kendi renkli simge kutusu.
    var tint: Color {
        switch self {
        case .interface: Color(red: 0.36, green: 0.30, blue: 0.95)
        case .appearance: Color(red: 0.0, green: 0.44, blue: 0.82)
        case .dubbing: Color(red: 0.55, green: 0.33, blue: 0.95)
        case .translation: Color(red: 0.0, green: 0.62, blue: 0.75)
        case .packs: Color(red: 0.98, green: 0.55, blue: 0.10)
        case .language: Color(red: 0.20, green: 0.70, blue: 0.40)
        case .area: Color(red: 0.35, green: 0.40, blue: 0.95)
        case .obs: Color(red: 0.92, green: 0.26, blue: 0.30)
        case .health: Color(red: 0.95, green: 0.30, blue: 0.45)
        case .updates: Color(red: 0.12, green: 0.62, blue: 0.36)
        case .about: Color(red: 0.45, green: 0.50, blue: 0.60)
        }
    }
}

struct SettingsView: View {
    @Environment(\.dismiss) private var dismiss
    /// nil: iPhone ayarları gibi gruplu liste; bir bölüm: o bölümün sayfası (solda geri düğmesiyle).
    @State private var section: SettingsSection?

    init(section: SettingsSection? = nil) {
        _section = State(initialValue: section)
    }

    var body: some View {
        VStack(spacing: Theme.space("m")) {
            HStack {
                if section != nil {
                    Button {
                        withAnimation(.spring(response: 0.4, dampingFraction: 0.86)) { section = nil }
                    } label: {
                        Label("Settings", systemImage: "chevron.left").font(.csBody.weight(.semibold))
                    }
                    .buttonStyle(.plain)
                    .foregroundStyle(Color.csAccentText)
                    .keyboardShortcut("[", modifiers: .command)
                } else {
                    Text("Settings").font(.system(size: 28, weight: .bold, design: .rounded))
                }
                Spacer()
                Button("Done") { dismiss() }
                    .buttonStyle(CSButtonStyle(kind: .primary))
                    .keyboardShortcut(.defaultAction)
            }
            ScrollView {
                Group {
                    if let section {
                        SettingsPage(section: section)
                            .transition(.asymmetric(insertion: .move(edge: .trailing).combined(with: .opacity),
                                                    removal: .move(edge: .trailing).combined(with: .opacity)))
                    } else {
                        SettingsList(section: $section)
                            .transition(.asymmetric(insertion: .move(edge: .leading).combined(with: .opacity),
                                                    removal: .move(edge: .leading).combined(with: .opacity)))
                    }
                }
                .frame(maxWidth: section == .appearance ? 900 : 640)
                .frame(maxWidth: .infinity)
                .padding(.vertical, Theme.space("s"))
            }
            .scrollIndicators(.never)
        }
        .padding(Theme.space("xl"))
        .frame(width: Theme.size("windowWidth") - 2 * Theme.space("screen"), height: Theme.size("windowHeight") - 2 * Theme.space("screen"))
    }
}

/// iPhone ayarları gibi: cam gruplar içinde renkli simgeli satırlar, aralarında ince çizgi, sağda ok.
private struct SettingsList: View {
    @Binding var section: SettingsSection?

    private let groups: [[SettingsSection]] = [
        [.interface, .appearance, .translation, .language],
        [.packs, .dubbing, .area, .obs],
        [.health, .updates, .about],
    ]

    var body: some View {
        VStack(spacing: Theme.space("xl")) {
            ForEach(groups.indices, id: \.self) { g in
                VStack(spacing: 0) {
                    ForEach(Array(groups[g].enumerated()), id: \.element) { i, item in
                        SettingsListRow(item: item) {
                            withAnimation(.spring(response: 0.4, dampingFraction: 0.86)) { section = item }
                        }
                        if i < groups[g].count - 1 {
                            Divider().padding(.leading, 58)
                        }
                    }
                }
                .ninoGlass(in: RoundedRectangle(cornerRadius: Theme.radius("card"), style: .continuous))
                .overlay(RoundedRectangle(cornerRadius: Theme.radius("card"), style: .continuous).strokeBorder(Color.ninoGlassEdge))
            }
        }
    }
}

private struct SettingsListRow: View {
    let item: SettingsSection
    let action: () -> Void
    @State private var hovering = false

    var body: some View {
        Button(action: action) {
            HStack(spacing: Theme.space("m")) {
                Image(systemName: item.symbol)
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(.white)
                    .frame(width: 30, height: 30)
                    .background(RoundedRectangle(cornerRadius: 8, style: .continuous)
                        .fill(LinearGradient(colors: [item.tint.opacity(0.85), item.tint], startPoint: .top, endPoint: .bottom)))
                Text(item.title).font(.csBody).foregroundStyle(Color.csText)
                Spacer()
                Image(systemName: "chevron.right")
                    .font(.system(size: 12, weight: .bold))
                    .foregroundStyle(Color.csSecondary.opacity(0.7))
            }
            .padding(.horizontal, Theme.space("l"))
            .frame(minHeight: 52)
            .background(hovering ? Color.csAccentSoft.opacity(0.6) : Color.clear)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { h in withAnimation(.easeOut(duration: 0.15)) { hovering = h } }
    }
}

/// Bölüm listesi: seçili satır yüzey-2 zeminli ve yarı kalın (sarı değil).
private struct SettingsSidebar: View {
    @Binding var section: SettingsSection

    var body: some View {
        VStack(alignment: .leading, spacing: Theme.space("xs")) {
            Text("Settings")
                .font(.csTitle)
                .padding(.horizontal, Theme.space("m"))
                .padding(.bottom, Theme.space("s"))
            ForEach(SettingsSection.allCases) { item in
                SidebarRow(title: item.title, symbol: item.symbol, selected: item == section, tint: item.tint) {
                    withAnimation(.spring(response: 0.35, dampingFraction: 0.85)) { section = item }
                }
            }
            Spacer(minLength: 0)
        }
        .frame(width: Theme.size("sidebarWidth"), alignment: .leading)
        .frame(maxHeight: .infinity, alignment: .top)
        .tile(padding: Theme.space("m"))
    }
}

/// Kenar çubuğundaki bir satır (ayarlar bölümü ya da kurulum adımı).
struct SidebarRow: View {
    let title: LocalizedStringKey
    let symbol: String
    let selected: Bool
    var tint: Color? = nil
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: Theme.space("m")) {
                if let tint {
                    Image(systemName: symbol)
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(.white)
                        .frame(width: 26, height: 26)
                        .background(RoundedRectangle(cornerRadius: 7, style: .continuous)
                            .fill(LinearGradient(colors: [tint.opacity(0.85), tint], startPoint: .top, endPoint: .bottom)))
                } else {
                    Image(systemName: symbol)
                        .frame(width: 20)
                        .foregroundStyle(selected ? Color.csText : Color.csSecondary)
                }
                Text(title)
                    .font(selected ? .csBody.weight(.semibold) : .csBody)
                    .foregroundStyle(Color.csText)
                Spacer(minLength: 0)
            }
            .padding(.horizontal, Theme.space("m"))
            .frame(minHeight: 40)
            .background(selected ? Color.csAccentSoft : Color.clear, in: RoundedRectangle(cornerRadius: Theme.radius("control"), style: .continuous))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(selected ? .isSelected : [])
    }
}

/// Seçili bölümün başlığı ve karoları.
private struct SettingsPage: View {
    let section: SettingsSection
    @EnvironmentObject private var model: AppModel

    var body: some View {
        VStack(alignment: .leading, spacing: Theme.space("gap")) {
            if section != .packs {
                HStack(spacing: Theme.space("m")) {
                    Image(systemName: section.symbol)
                        .font(.system(size: 18, weight: .semibold))
                        .foregroundStyle(.white)
                        .frame(width: 40, height: 40)
                        .background(RoundedRectangle(cornerRadius: 11, style: .continuous).fill(section.tint))
                        .shadow(color: section.tint.opacity(0.45), radius: 10, y: 4)
                    Text(section.title).font(.system(size: 28, weight: .bold, design: .rounded))
                }
            }
            switch section {
            case .appearance:
                // Tek sayfa, kaydırmasız: üstte önizleme + ince ayarlar, altta tek sırada altı tema.
                HStack(alignment: .top, spacing: Theme.space("gap")) {
                    SubtitleStylePreview(style: model.settings.style, size: CGSize(width: 470, height: 264))
                        .overlay(alignment: .topLeading) {
                            Text(model.settings.style.theme.title)
                                .font(.csCallout.weight(.semibold))
                                .foregroundStyle(.white)
                                .padding(.horizontal, 10).frame(height: 26)
                                .background(Capsule().fill(Color.black.opacity(0.45)))
                                .padding(10)
                        }
                    AppearanceCard()
                }
                SubtitleThemePicker(columns: 6)
            case .dubbing: DubbingCard()
            case .translation: TranslationCard()
            case .packs: GamePacksPage()
            case .language: LanguageCard()
            case .area: AreaCards()
            case .obs: OBSCard()
            case .health: SystemHealthPage()
            case .updates: UpdatesCard()
            case .interface: InterfacePage()
            case .about:
                AboutCard()
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

/// Yazı boyutu, yeri, arka planı, rengi; görünüm ayarları bilgisayar ekranındaki pencereye de uygulanır.
private struct AppearanceCard: View {
    @EnvironmentObject private var model: AppModel

    var body: some View {
        Card(title: model.settings.output == .tv ? "On the TV" : "Subtitle appearance") {
            // Nino: varsayılan olarak yazı boyu oyunun altyazısına uydurulur.
            Toggle("Match the game's subtitle size", isOn: $model.settings.style.autoSize)
                .toggleStyle(.switch)
            // 1920 piksellik TV ekranında yazı yüksekliği; sürüklerken TV'de örnek altyazı görünür.
            Slider(value: Binding(get: { Double(model.settings.style.fontSize) },
                                  set: { model.settings.style.fontSize = Int($0.rounded()) }), in: 20...80) {
                Text("Text size")
            } minimumValueLabel: {
                Text("Small").font(.csCallout).foregroundStyle(Color.csSecondary)
            } maximumValueLabel: {
                Text("Large").font(.csCallout).foregroundStyle(Color.csSecondary)
            } onEditingChanged: { editing in
                if editing { model.sendTestSubtitle() }
            }
            .disabled(model.settings.style.autoSize)
            // Yer ayarları TV içindir; bilgisayar ekranındaki altyazı penceresi sürüklenerek taşınır (Genzo, 2026-11-13:
            // "ekrandaki konum ayarı işlemiyor").
            if model.settings.output.showsOnTV {
                Picker("Placement", selection: $model.settings.style.placement) {
                    Text("Over the English subtitle").tag(SubtitlePlacement.cover)
                    Text("Above the English subtitle").tag(SubtitlePlacement.above)
                    Text("Below the English subtitle").tag(SubtitlePlacement.below)
                    Text("Fixed position").tag(SubtitlePlacement.fixed)
                }
                if model.settings.style.placement == .fixed {
                    // Sürüklerken TV'de örnek altyazı görünür; böylece yeri doğrudan ekranda ayarlanır.
                    Slider(value: Binding(get: { Double(model.settings.style.bottomPercent) },
                                          set: { model.settings.style.bottomPercent = Int($0.rounded()) }), in: 0...85) {
                        Text("Position on screen")
                    } minimumValueLabel: {
                        Text("Bottom").font(.csCallout).foregroundStyle(Color.csSecondary)
                    } maximumValueLabel: {
                        Text("Top").font(.csCallout).foregroundStyle(Color.csSecondary)
                    } onEditingChanged: { editing in
                        if editing { model.sendTestSubtitle() }
                    }
                    HintText(text: "In fixed position you can also move subtitles with the ▲ and ▼ buttons on the TV remote.")
                } else {
                    HintText(text: "The translation follows where the game shows its own subtitle.")
                }
            }
            if model.settings.output.showsOnComputer {
                HintText(text: "On the computer screen, move the subtitle by dragging its window: press Adjust the subtitle window.")
                Button("Adjust the subtitle window") { model.overlayAdjusting = true }.buttonStyle(.secondary)
            }
            Slider(value: Binding(get: { Double(model.settings.style.background) },
                                  set: { model.settings.style.background = Int($0.rounded()) }), in: 0...100) {
                Text("Background")
            } minimumValueLabel: {
                Text("None").font(.csCallout).foregroundStyle(Color.csSecondary)
            } maximumValueLabel: {
                Text("Solid").font(.csCallout).foregroundStyle(Color.csSecondary)
            } onEditingChanged: { editing in
                if editing { model.sendTestSubtitle() }
            }
            Toggle("Bold text", isOn: $model.settings.style.bold)
            Picker("Text color", selection: $model.settings.style.textColor) {
                Text("White").tag(SubtitleTextColor.white)
                Text("Yellow").tag(SubtitleTextColor.yellow)
            }
            if model.settings.output.showsOnTV, model.tv?.brand == .androidTV {
                AndroidDisplayModePicker(mode: $model.settings.style.displayMode)
            }
        }
    }
}

private struct LanguageCard: View {
    @EnvironmentObject private var model: AppModel

    var body: some View {
        Card {
            Picker("Game language", selection: $model.settings.sourceLanguage) {
                Text("English").tag("en")
                Text("Japanese").tag("ja")
                Text("German").tag("de")
                Text("French").tag("fr")
                Text("Spanish").tag("es")
            }
        }
    }
}

/// Bölge önizlemesi, son PS5 karesiyle (kare değişince yalnız bu görünüm yeniden çizilir).
private struct LiveRegionPreview: View {
    @Binding var settings: UserSettings
    @ObservedObject var preview: FramePreview

    var body: some View {
        RegionPreview(region: settings.region, frame: preview.image) { settings.setCustomRegion($0) }
    }
}

/// Altyazı bölgesi (hazır seçimler, canlı önizleme, Özel'de kaydırıcılar) ve ekranı çevirme kısayolu.
private struct AreaCards: View {
    @EnvironmentObject private var model: AppModel

    var body: some View {
        Card {
            Picker("Area preset", selection: Binding(get: { model.settings.areaPreset }, set: { model.settings.selectAreaPreset($0) })) {
                ForEach(AreaPreset.allCases, id: \.self) { preset in Text(preset.title).tag(preset) }
            }
            .pickerStyle(.segmented)
            .labelsHidden()
            LiveRegionPreview(settings: $model.settings, preview: model.framePreview)
            if model.settings.areaPreset == .custom { CustomAreaSliders(settings: $model.settings) }
            HintText(text: "Adjust the frame so it covers where the game shows its subtitles.")
            HintText(text: "Drag the frame to move it, or drag its corner to resize it.")
        }
        Card(title: "Translate the screen (⌥⌘T)") {
            HintText(text: "Press ⌥⌘T while playing: every text on the screen is translated once and shown on the TV in its own place. Press again to remove the translations.")
        }
    }
}

private struct OBSCard: View {
    @EnvironmentObject private var model: AppModel
    @State private var obsCopied = false

    /// OBS'de "Tarayıcı kaynağı" adresi; OBS çoğunlukla Nino ile aynı bilgisayarda çalışır.
    private var obsAddress: String { "http://localhost:\(model.serverPort)/obs" }

    var body: some View {
        Card {
            HintText(text: "Streaming with a capture card? In OBS add a Browser source with this address (width 1920, height 1080). The Turkish subtitles appear over the game on your screen and on the stream.")
            HStack(spacing: Theme.space("m")) {
                Text(verbatim: obsAddress)
                    .font(.csBody.monospaced())
                    .textSelection(.enabled)
                    .padding(.horizontal, Theme.space("l"))
                    .frame(maxWidth: .infinity, minHeight: Theme.size("buttonHeight"), alignment: .leading)
                    .background(Color.csSurface2, in: RoundedRectangle(cornerRadius: Theme.radius("control"), style: .continuous))
                Button(obsCopied ? "Copied" : "Copy") {
                    NSPasteboard.general.clearContents()
                    NSPasteboard.general.setString(obsAddress, forType: .string)
                    obsCopied = true
                }
                .buttonStyle(.secondary)
            }
            HintText(text: "If OBS runs on another computer, use this Mac's network address instead of localhost. The overlay only shows subtitles while the translation is running.")
        }
    }
}

/// Uygulamanın görünümü: koyu (varsayılan, onaylı tasarım), açık ya da sistemle aynı. Tüm pencerelere anında uygulanır.
/// Nino: Ayarlar › Arayüz. Ana ekranın iki arayüzü önizleme kartlarıyla seçilir (1. Salon, 2. Cam düğme); altta
/// uygulama penceresinin görünümü (koyu, açık, sistemle aynı).
private struct InterfacePage: View {
    @EnvironmentObject private var model: AppModel

    var body: some View {
        VStack(alignment: .leading, spacing: Theme.space("gap")) {
            Card(title: "Home screen") {
                HStack(alignment: .top, spacing: Theme.space("m")) {
                    choice(.livingRoom, title: "Living room", detail: "Plug the cable into the socket to turn on Turkish subtitles.") {
                        ZStack {
                            RoundedRectangle(cornerRadius: 10, style: .continuous).fill(Color(red: 0.04, green: 0.08, blue: 0.2))
                            Image("LivingRoom").resizable().scaledToFit().padding(12)
                                .shadow(color: Color(red: 0.12, green: 0.36, blue: 1.0).opacity(0.7), radius: 14)
                        }
                    }
                    choice(.toggle, title: "Glass switch", detail: "Slide the glass switch; the TV drops down with the live subtitle.") {
                        ZStack {
                            RoundedRectangle(cornerRadius: 10, style: .continuous).fill(Color(red: 0.04, green: 0.08, blue: 0.2))
                            ZStack(alignment: .leading) {
                                Capsule().fill(LinearGradient(colors: [Color(red: 0.47, green: 0.55, blue: 0.70), Color(red: 0.30, green: 0.36, blue: 0.52)],
                                                              startPoint: .top, endPoint: .bottom))
                                    .frame(width: 150, height: 40)
                                Circle().fill(Color(red: 0.36, green: 0.43, blue: 0.60))
                                    .overlay(Circle().strokeBorder(Color.white.opacity(0.8), lineWidth: 1.5))
                                    .overlay(Image(systemName: "power").font(.system(size: 16, weight: .bold)).foregroundStyle(.white))
                                    .frame(width: 50, height: 50)
                                    .offset(x: -5)
                            }
                        }
                    }
                }
                .fixedSize(horizontal: false, vertical: true)
            }
            Card {
                Picker("Appearance", selection: $model.settings.appearance) {
                    Text("Dark").tag(AppAppearance.dark)
                    Text("Light").tag(AppAppearance.light)
                    Text("Same as system").tag(AppAppearance.system)
                }
            }
        }
    }

    private func choice<Preview: View>(_ style: HomeStyle, title: LocalizedStringKey, detail: LocalizedStringKey,
                                       @ViewBuilder preview: () -> Preview) -> some View {
        let selected = model.settings.homeStyle == style
        return Button { model.settings.homeStyle = style } label: {
            VStack(alignment: .leading, spacing: Theme.space("s")) {
                preview()
                    .frame(height: 130)
                    .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
                HStack(spacing: 6) {
                    Image(systemName: selected ? "checkmark.circle.fill" : "circle")
                        .foregroundStyle(selected ? Color.csAccent : Color.csSecondary)
                    Text(title).font(.csBody.weight(.semibold)).foregroundStyle(Color.csText)
                }
                Text(detail).font(.csCaption).foregroundStyle(Color.csSecondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .padding(Theme.space("s"))
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            .background(RoundedRectangle(cornerRadius: 14, style: .continuous)
                .strokeBorder(selected ? Color.csAccent : Color.ninoGlassEdge, lineWidth: selected ? 2 : 1))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(selected ? .isSelected : [])
    }
}

/// Nino: güncellemeler. Bu sürüm, "Güncellemeleri denetle" düğmesi ve yeni sürüm varsa İndir.
private struct UpdatesCard: View {
    @ObservedObject private var updates = NinoUpdates.shared

    var body: some View {
        Card {
            HStack(spacing: Theme.space("m")) {
                LogoView(size: 44)
                VStack(alignment: .leading, spacing: 2) {
                    Text(verbatim: "Nino Game Translator").font(.csHeadline)
                    Text(String(format: String(localized: "Version %@"), AppIdentity.version))
                        .font(.csCallout).foregroundStyle(Color.csSecondary)
                }
                Spacer()
                Button(updates.state == .checking ? LocalizedStringKey("Checking…") : LocalizedStringKey("Check for updates")) {
                    Task { await updates.check(force: true) }
                }
                .buttonStyle(.secondary)
                .disabled(updates.state == .checking)
            }
            if let release = updates.available {
                HStack(spacing: Theme.space("m")) {
                    Image(systemName: "sparkles").foregroundStyle(Color.csAccent)
                    Text(String(format: String(localized: "Nino %@ is ready."), release.version)).font(.csBody.weight(.semibold))
                    Spacer()
                    Button("What's new") { updates.openNotes() }.buttonStyle(.secondary)
                    Button("Download") { updates.open() }.buttonStyle(CSButtonStyle(kind: .primary))
                }
                HintText(text: "Open the downloaded zip and drag Nino into Applications, replacing the old one. Your settings stay.")
            } else {
                switch updates.state {
                case .upToDate: DoneLabel(text: String(localized: "You have the latest version."))
                case .failed: ErrorText(error: String(localized: "Could not check for updates. Check your internet connection."))
                case .idle, .checking: EmptyView()
                }
            }
            HintText(text: "Nino also checks for a new version by itself when it opens and tells you on the main screen.")
        }
    }
}

private struct AboutCard: View {
    @EnvironmentObject private var model: AppModel
    @Environment(\.dismiss) private var dismiss
    @State private var confirmReset = false

    var body: some View {
        VStack(spacing: Theme.space("gap")) {
            NinoCredits()
            HStack {
                Spacer()
                Button("Set up again…") { confirmReset = true }.buttonStyle(.danger)
            }
        }
        // Nino: çoğu zaman yalnız TV yeniden kurulmak istenir; PS5 hesabını yeniden girmek gerekmesin.
        .confirmationDialog("Set up again?", isPresented: $confirmReset) {
            Button("Set up again from the TV") {
                model.resetFromTV()
                dismiss()
            }
            Button("Reset everything", role: .destructive) {
                model.resetSetup()
                dismiss()
            }
        } message: {
            Text("From the TV: your PS5 account and PS5 pairing stay; only the TV connection is set up again. Reset everything: the saved PS5, account and TV connection are removed and you sign in to PSN again.")
        }
    }
}

/// Oyun paketleri: masaüstünde ücretsiz; kurulu paketler karolar hâlinde, altta paket ve ortak havuz anahtarları
/// (Windows'taki ayarlarla aynı düzen).
private struct GamePacksPage: View {
    @EnvironmentObject private var model: AppModel
    private let columns = [GridItem(.flexible(), spacing: Theme.space("gap"), alignment: .top),
                           GridItem(.flexible(), spacing: Theme.space("gap"), alignment: .top)]

    var body: some View {
        HStack(alignment: .firstTextBaseline) {
            Text("Game packs").font(.csDisplay)
            Spacer()
            if !model.installedPacks.isEmpty {
                Pill(text: String(format: String(localized: "Free · %lld games"), model.installedPacks.count), tone: .success)
            }
        }
        Text("Ready-made Turkish translations for some games. A line found in a pack appears at once, without the translation engine.")
            .font(.csBody)
            .foregroundStyle(Color.csSecondary)
            .fixedSize(horizontal: false, vertical: true)
        if model.installedPacks.isEmpty {
            Card { HintText(text: "No game pack is installed.") }
        } else {
            LazyVGrid(columns: columns, spacing: Theme.space("gap")) {
                ForEach(model.installedPacks) { pack in PackTile(pack: pack) }
            }
        }
        VStack(alignment: .leading, spacing: Theme.space("m")) {
            SwitchRow(title: "Use game packs", isOn: $model.settings.gamePacks)
            Divider().overlay(Color.csBorder)
            SwitchRow(title: "Send the English subtitles read to the shared pool", isOn: $model.settings.sharePool)
            HintText(text: "Only the game's English text is sent, anonymously. It is used to make better Turkish translations for everyone.")
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .tile()
    }
}

/// Paket karosu: oyunun kısaltması, adı ve satır sayısı.
private struct PackTile: View {
    let pack: GamePackLibrary.Info

    /// Adın kelimelerinin baş harfleri (en çok üç): "Red Dead Redemption 2" → "RDR".
    private var initials: String {
        let words = pack.title.split(whereSeparator: { !$0.isLetter && !$0.isNumber })
        return String(words.prefix(3).compactMap(\.first)).uppercased()
    }

    var body: some View {
        HStack(alignment: .top, spacing: Theme.space("m")) {
            Text(verbatim: initials)
                .font(.csCaption.weight(.semibold))
                .foregroundStyle(Color.csText)
                .frame(width: 48, height: 48)
                .background(Color.csSurface2, in: RoundedRectangle(cornerRadius: Theme.radius("inner"), style: .continuous))
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: Theme.space("hair")) {
                Text(verbatim: pack.title).font(.csHeadline).fixedSize(horizontal: false, vertical: true)
                Text(verbatim: String(format: String(localized: "%@ lines"), pack.entries.formatted()))
                    .font(.csCaption)
                    .foregroundStyle(Color.csSecondary)
            }
            Spacer(minLength: 0)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .tile()
        .accessibilityElement(children: .combine)
    }
}

/// Başlık solda, anahtar sağda.
private struct SwitchRow: View {
    let title: LocalizedStringKey
    @Binding var isOn: Bool

    var body: some View {
        HStack(spacing: Theme.space("m")) {
            Text(title).font(.csHeadline).fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: Theme.space("m"))
            Toggle(title, isOn: $isOn)
                .labelsHidden()
                .toggleStyle(.switch)
                .tint(Color.csAccent)
        }
    }
}

/// Çeviri motoru: ücretsiz cihaz üstü çeviri ya da kullanıcının kendi anahtarıyla DeepL, Gemini, OpenAI, Claude
/// (Windows'taki ayarlarla aynı düzen).
/// Android TV'de PS5 görüntüsünün nasıl gösterileceği; bazı TV'lerde (ör. TCL) uygulama içindeki görüntü siyah kalıyor.
private struct AndroidDisplayModePicker: View {
    @Binding var mode: TVDisplayMode

    var body: some View {
        Picker("Picture mode", selection: $mode) {
            Text("Inside the app").tag(TVDisplayMode.inApp)
            Text("Overlay (for a black screen)").tag(TVDisplayMode.overlay)
        }
        HintText(text: "If the PS5 picture stays black inside the Nino TV app, choose Overlay: the TV shows the PS5 on its own HDMI input and the subtitles appear on top. If the picture never arrives, the TV app switches to Overlay by itself.")
    }
}

struct TranslationCard: View {
    @EnvironmentObject private var model: AppModel
    @Environment(\.openURL) private var openURL

    var body: some View {
        let engine = model.settings.translationEngine
        Card(title: "Translation engine") {
            EngineTiles(engine: $model.settings.translationEngine)
            HintText(text: Self.explanation(engine))
            if engine != .free, model.settings.sourceLanguage != "en" {
                HintText(text: "Online engines translate English games only. For other game languages the free translation is used.")
            }
            switch engine {
            case .free:
                // Ücretsiz çeviri zayıf kalıyor; ücretsiz Gemini anahtarı en kolay iyileştirme.
                HStack(spacing: Theme.space("m")) {
                    Text("For better translation, get a free Gemini key.")
                        .fixedSize(horizontal: false, vertical: true)
                    Spacer()
                    Button("Get a free key") {
                        model.chooseFreeGemini()
                        openURL(AIProvider.gemini.keyPage)
                    }
                    .buttonStyle(.secondary)
                }
            case .deepL: DeepLKeySection()
            case .gemini, .openAI, .claude:
                if let provider = engine.aiProvider { AIKeySection(provider: provider).id(provider) }
            case .local: LocalAISection()
            }
            if engine == .gemini {
                HintText(text: FreeGemini.privacy)
                HintText(text: FreeGemini.limit)
            }
        }
    }

    private static func explanation(_ engine: TranslationEngine) -> LocalizedStringKey {
        switch engine {
        case .free: "Free. Apple's translation runs on this Mac; subtitle text never leaves it."
        case .deepL: "Optional. With your own free DeepL key, translations read more naturally. Subtitle text is sent to DeepL; when DeepL cannot be reached, the translation model on this computer takes over."
        case .gemini: "Google's AI translates with the game's tone and keeps names as they are. Subtitle text is sent to Google with your own key, and any cost is billed to your Google account. When Gemini cannot be reached, the free translation takes over."
        case .openAI: "OpenAI's AI translates with the game's tone and keeps names as they are. Subtitle text is sent to OpenAI with your own key, and any cost is billed to your OpenAI account. When OpenAI cannot be reached, the free translation takes over."
        case .claude: "Anthropic's Claude translates with the game's tone and keeps names as they are. Subtitle text is sent to Anthropic with your own key, and any cost is billed to your Anthropic account. When Claude cannot be reached, the free translation takes over."
        case .local: "Free, with no quota. An AI model on this computer (Ollama or LM Studio) translates; subtitle text never leaves it. Speed depends on your computer. When the model cannot be reached, the free translation takes over."
        }
    }

    /// Çevrimiçi motor hatasının kullanıcıya söylenişi (ayarlar ve ana ekran aynı metni kullanır). Yerel modelde
    /// `server` sunucunun adresini ve modeli iletiye koyar.
    static func describe(_ state: OnlineKeyState, engine: TranslationEngine, server: LocalAIServer? = nil) -> String {
        if engine == .local { return describeLocal(state, server: server) }
        let name = engine.displayName
        return switch state {
        case .valid: String(localized: "It works.")
        case .invalid: String(format: String(localized: "%@ did not accept this key. Copy it again from your account page."), name)
        // Nino: Gemini'de bu hata çoğunlukla ücretsiz anahtarın günlük hakkının bitmesidir; "bakiye" sözü kullanıcıyı
        // para gitti sanıp korkutuyordu. Hak Pasifik saatiyle gece yarısı yenilenir; saat kullanıcının saatine çevrilir.
        case .quotaExceeded where engine == .gemini:
            String(format: String(localized: "Gemini's free daily limit is used up. A free key is never charged. It renews every day (next: %@)."),
                   Self.geminiQuotaReset().formatted(date: .omitted, time: .shortened))
        case .quotaExceeded: String(format: String(localized: "Your %@ account has no credit left or has reached its limit."), name)
        case .modelRejected: String(format: String(localized: "%@ did not accept the request. Choose the other model or try again later."), name)
        case .unreachable: String(format: String(localized: "%@ could not be reached. Check your internet connection."), name)
        }
    }

    /// Gemini'nin günlük hakkının yenileneceği an: sıradaki Pasifik saatiyle gece yarısı.
    static func geminiQuotaReset(after now: Date = Date()) -> Date {
        var pacific = Calendar(identifier: .gregorian)
        pacific.timeZone = TimeZone(identifier: "America/Los_Angeles")!
        return pacific.nextDate(after: now, matching: DateComponents(hour: 0, minute: 0), matchingPolicy: .nextTime) ?? now
    }

    /// Yerel model sunucusunun (Ollama, LM Studio) hatası; sunucunun türüne göre ne yapılacağı söylenir (Windows ile aynı).
    static func describeLocal(_ state: OnlineKeyState, server: LocalAIServer?) -> String {
        let server = server ?? LocalAIServer(baseURL: LocalAIServer.ollamaURL, model: LocalAIServer.defaultModel)!
        switch state {
        case .valid:
            return String(localized: "It works.")
        case .invalid:
            return String(localized: "The local model server did not accept the API key. Check the key, or remove it if the server does not need one.")
        case .quotaExceeded:
            return String(localized: "The local model server is busy. Try again in a moment.")
        case .modelRejected:
            if server.kind == .lmStudio {
                return String(format: String(localized: "LM Studio does not have the model %@. Download and load it in LM Studio, or check the model name."), server.model)
            }
            return String(format: String(localized: "The model %1$@ is not on the local server. Download it: ollama pull %1$@"), server.model)
        case .unreachable:
            switch server.kind {
            case .ollama:
                return String(format: String(localized: "Ollama is not running: %1$@ could not be reached, or the model did not answer in time. Open Ollama and download the model: ollama pull %2$@"), server.address, server.model)
            case .lmStudio:
                return String(format: String(localized: "LM Studio is not running: %@ could not be reached, or the model did not answer in time. Open LM Studio, load the model and start the local server."), server.address)
            case .other:
                return String(format: String(localized: "The local model server at %@ could not be reached, or the model did not answer in time. Check the address and that the server is running."), server.address)
            }
        }
    }
}

/// Çeviri motoru seçimi: altı karo (iki sıra), seçili olan sarı çerçeveli ve parlak.
private struct EngineTiles: View {
    @Binding var engine: TranslationEngine
    static let order: [TranslationEngine] = [.gemini] + TranslationEngine.allCases.filter { $0 != .gemini }
    private let columns = Array(repeating: GridItem(.flexible(), spacing: Theme.space("m"), alignment: .top), count: 3)

    var body: some View {
        LazyVGrid(columns: columns, spacing: Theme.space("m")) {
            // Nino: önerilen Gemini başta (en iyi çeviri, ücretsiz anahtar, kurması kolay).
            ForEach(Self.order, id: \.self) { option in
                EngineTile(option: option, selected: option == engine) { engine = option }
            }
        }
    }
}

private struct EngineTile: View {
    let option: TranslationEngine
    let selected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            VStack(alignment: .leading, spacing: Theme.space("hair")) {
                HStack(spacing: Theme.space("s")) {
                    Text(verbatim: name).font(.csHeadline).foregroundStyle(Color.csText)
                    Spacer(minLength: 0)
                    if option == .gemini {
                        Text("Recommended")
                            .font(.system(size: 11, weight: .bold))
                            .foregroundStyle(.white)
                            .padding(.horizontal, 8).padding(.vertical, 3)
                            .background(Capsule().fill(LinearGradient(colors: [Color.csAccentHi, Color(red: 0.0, green: 0.19, blue: 0.52)],
                                                                      startPoint: .top, endPoint: .bottom)))
                    }
                }
                Text(caption).font(.csCaption).foregroundStyle(Color.csSecondary).fixedSize(horizontal: false, vertical: true)
                Spacer(minLength: 0)
            }
            .frame(maxWidth: .infinity, minHeight: 64, alignment: .topLeading)
            .tile(selected ? .active : .plain, padding: Theme.space("m"))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(selected ? .isSelected : [])
    }

    private var name: String {
        option == .free ? String(localized: "Free") : option.displayName
    }

    private var caption: LocalizedStringKey {
        switch option {
        case .free: "On this computer, offline"
        case .gemini: "Free key · best translation"
        case .deepL: "With a free key"
        case .openAI, .claude: "With your own key"
        case .local: "Ollama or LM Studio, no quota"
        }
    }
}

/// DeepL anahtarı: kaydedilince bu ayki kullanım görünür.
private struct DeepLKeySection: View {
    @EnvironmentObject private var model: AppModel
    @State private var key = ""
    @State private var checking = false
    @State private var status: OnlineKeyCheck?

    var body: some View {
        if model.hasDeepLKey {
            // Nino: Gemini'deki gibi "Anahtar kayıtlı", Dene (aylık kullanımı okur) ve Anahtarı Sil.
            HStack(spacing: Theme.space("m")) {
                DoneLabel(text: String(localized: "Key saved"))
                Spacer()
                Button(checking ? LocalizedStringKey("Testing…") : LocalizedStringKey("Test")) {
                    checking = true
                    Task {
                        status = await model.deepLUsage()
                        checking = false
                    }
                }
                .buttonStyle(.secondary)
                .disabled(checking)
                Button("Remove key") {
                    model.removeDeepLKey()
                    status = nil
                }
                .buttonStyle(.secondary)
            }
        } else {
            HStack(spacing: Theme.space("m")) {
                SecureField("DeepL API key", text: $key).textFieldStyle(CSTextFieldStyle())
                Button("Save and test") {
                    checking = true
                    Task {
                        status = await model.setDeepLKey(key)
                        if model.hasDeepLKey { key = "" }
                        checking = false
                    }
                }
                .buttonStyle(.secondary)
                .disabled(checking || key.trimmingCharacters(in: .whitespaces).isEmpty)
            }
            Link("Get a free DeepL API key", destination: URL(string: "https://www.deepl.com/pro-api")!)
                .font(.csCallout)
        }
        Group {
            if let status {
                Text(Self.describe(status))
                    .font(.csCallout)
                    .foregroundStyle(Color.csSecondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .task {
            if model.hasDeepLKey { status = await model.deepLUsage() }
        }
    }

    private static func describe(_ check: OnlineKeyCheck) -> String {
        switch check.state {
        case .valid:
            String(format: String(localized: "This month: %1$@ of %2$@ characters used."),
                   check.used.formatted(), check.limit.formatted())
        case .quotaExceeded:
            String(localized: "This month's DeepL limit is used up. Until it renews, the translation model on this computer translates.")
        case .invalid:
            String(localized: "DeepL did not accept this key. Copy it again from your DeepL account page.")
        case .unreachable, .modelRejected:
            String(localized: "DeepL could not be reached. Check your internet connection.")
        }
    }
}

/// Yapay zekâ modeli (yalnız listedekiler), anahtar ve örnek satırla deneme.
private struct AIKeySection: View {
    @EnvironmentObject private var model: AppModel
    let provider: AIProvider
    @State private var key = ""
    @State private var checking = false
    @State private var result: Result<String, AIFailure>?

    private var engine: TranslationEngine { TranslationEngine(provider) }

    var body: some View {
        // Model adı yazılamaz; yalnız ortak listedeki modeller seçilir.
        Picker("Model", selection: Binding(get: { provider.model(model.settings.model(for: provider)).id },
                                           set: { model.settings.setModel($0, for: provider) })) {
            ForEach(provider.models, id: \.id) { option in
                Text(LocalizedStringKey(option.label)).tag(option.id)
            }
        }
        if model.hasKey(engine) {
            HStack(spacing: Theme.space("m")) {
                DoneLabel(text: String(localized: "Key saved"))
                Spacer()
                Button(checking ? LocalizedStringKey("Testing…") : LocalizedStringKey("Test")) {
                    run { await model.testAIKey(for: provider) }
                }
                .buttonStyle(.secondary)
                .disabled(checking)
                Button("Remove key") {
                    model.removeKey(engine)
                    result = nil
                }
                .buttonStyle(.secondary)
            }
        } else {
            HStack(spacing: Theme.space("m")) {
                SecureField("API key", text: $key).textFieldStyle(CSTextFieldStyle())
                Button("Save and test") {
                    let typed = key
                    run {
                        let result = await model.setAIKey(typed, for: provider)
                        if model.hasKey(engine) { key = "" }
                        return result
                    }
                }
                .buttonStyle(.secondary)
                .disabled(checking || key.trimmingCharacters(in: .whitespaces).isEmpty)
            }
            if model.settings.translationEngine == engine {
                HintText(text: "Add your key to start. Until then the free translation is used.")
            }
            Link(String(format: String(localized: "Get a %@ API key"), provider.displayName), destination: provider.keyPage)
                .font(.csCallout)
        }
        if let result {
            switch result {
            case .success(let sample):
                Text(String(format: String(localized: "It works. Sample translation: %@"), sample))
                    .font(.csCallout)
                    .foregroundStyle(Color.csSecondary)
                    .fixedSize(horizontal: false, vertical: true)
            case .failure(let failure):
                ErrorText(error: TranslationCard.describe(OnlineKeyState(failure), engine: engine))
            }
        }
    }

    private func run(_ work: @escaping () async -> Result<String, AIFailure>) {
        checking = true
        result = nil
        Task {
            result = await work()
            checking = false
        }
    }
}

/// Yerel model (Ollama, LM Studio). Nino: kullanıcı Terminal'e komut yazmasın. Üstte Ollama'nın durumu (çalışıyor mu),
/// altında önerilen çeviri modelleri: biri seçilir, kurulu değilse İndir'e basılır, Nino Ollama'ya indirtir. Sunucu
/// adresi, model adı, LM Studio ve anahtar "Gelişmiş"te (Windows'taki ayarlarla aynı alanlar).
private struct LocalAISection: View {
    @EnvironmentObject private var model: AppModel
    @State private var address = ""
    @State private var modelName = ""
    @State private var key = ""
    @State private var checking = false
    @State private var result: Result<String, AIFailure>?
    @FocusState private var focused: Field?
    /// Ollama'daki modeller; nil: Ollama'ya ulaşılamadı (kurulu değil ya da açık değil). Boş dizi: henüz bakılmadı.
    @State private var installed: [String]?
    @State private var looked = false
    @State private var downloading: String?
    @State private var progress = 0.0
    @State private var downloadError: String?
    @State private var advanced = false

    private enum Field { case address, model }

    private var serverURL: URL? { LocalAIServer.normalize(model.settings.localAIBaseURL) }
    private var usesOllama: Bool { model.settings.localAIServer?.kind == .ollama }

    var body: some View {
        Group {
            if usesOllama { ollamaStatus }
            if usesOllama {
                VStack(spacing: Theme.space("s")) {
                    ForEach(LocalModelPreset.all) { preset in presetRow(preset) }
                }
                if let downloadError { ErrorText(error: downloadError) }
            }
            HStack(spacing: Theme.space("m")) {
                Button(checking ? LocalizedStringKey("Testing…") : LocalizedStringKey("Test connection")) { test() }
                    .buttonStyle(.secondary)
                    .disabled(checking || downloading != nil || LocalAIServer.normalize(address) == nil)
                Spacer()
            }
            if let result {
                switch result {
                case .success(let sample):
                    Text(String(format: String(localized: "It works. Sample translation: %@"), sample))
                        .font(.csCallout)
                        .foregroundStyle(Color.csSecondary)
                        .fixedSize(horizontal: false, vertical: true)
                case .failure(let failure):
                    ErrorText(error: TranslationCard.describe(OnlineKeyState(failure), engine: .local, server: model.settings.localAIServer))
                }
            }
            DisclosureGroup(isExpanded: $advanced) { advancedFields } label: {
                Text("Advanced").font(.csCallout).foregroundStyle(Color.csSecondary)
            }
        }
        .onAppear {
            address = model.settings.localAIBaseURL
            modelName = model.settings.localAIModel
        }
        .task(id: model.settings.localAIBaseURL) { await refresh() }
        .onChange(of: focused) { _ in commit() }
    }

    /// Ollama çalışıyor mu; değilse indirme bağlantısı.
    @ViewBuilder private var ollamaStatus: some View {
        HStack(spacing: Theme.space("s")) {
            if !looked {
                ProgressView().controlSize(.small)
                Text("Looking for Ollama…").font(.csCallout).foregroundStyle(Color.csSecondary)
            } else if installed != nil {
                Image(systemName: "checkmark.circle.fill").foregroundStyle(Color.csSuccess)
                Text("Ollama is running on this computer.").font(.csCallout)
            } else {
                Image(systemName: "exclamationmark.circle.fill").foregroundStyle(Color.csWarning)
                VStack(alignment: .leading, spacing: 2) {
                    Text("Ollama is not running.").font(.csCallout)
                    Text("Download and open Ollama (free), then come back here.").font(.csCaption).foregroundStyle(Color.csSecondary)
                }
            }
            Spacer()
            if looked && installed == nil {
                Link("Download Ollama", destination: AIProvider.local.keyPage).buttonStyle(.secondary)
                Button("Check again") { Task { await refresh() } }.buttonStyle(.secondary)
            }
        }
    }

    /// Önerilen bir model: seçim, açıklama, boyut ve durum (Kurulu / İndir / ilerleme).
    private func presetRow(_ preset: LocalModelPreset) -> some View {
        let selected = AIProvider.local.model(model.settings.localAIModel).id.caseInsensitiveCompare(preset.id) == .orderedSame
        let isInstalled = installed.map { OllamaAPI.contains($0, preset.id) } ?? false
        let shape = RoundedRectangle(cornerRadius: Theme.radius("control"), style: .continuous)
        return HStack(alignment: .center, spacing: Theme.space("m")) {
            Image(systemName: selected ? "largecircle.fill.circle" : "circle")
                .font(.system(size: 18))
                .foregroundStyle(selected ? Color.csAccent : Color.csSecondary)
            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: Theme.space("xs")) {
                    Text(verbatim: preset.title).font(.csHeadline)
                    if preset.recommended {
                        Text("Recommended")
                            .font(.system(size: 11, weight: .bold))
                            .foregroundStyle(.white)
                            .padding(.horizontal, 8).padding(.vertical, 3)
                            .background(Capsule().fill(LinearGradient(colors: [Color.csAccentHi, Color(red: 0.0, green: 0.19, blue: 0.52)],
                                                                      startPoint: .top, endPoint: .bottom)))
                    }
                }
                Text(LocalizedStringKey(preset.detail)).font(.csCaption).foregroundStyle(Color.csSecondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: Theme.space("s"))
            if downloading == preset.id {
                VStack(alignment: .trailing, spacing: 4) {
                    ProgressView(value: progress).frame(width: 120)
                    Text(verbatim: "\(Int(progress * 100))%").font(.csCaption).monospacedDigit().foregroundStyle(Color.csSecondary)
                }
            } else if isInstalled {
                Label(String(localized: "Downloaded"), systemImage: "checkmark").font(.csCaption).foregroundStyle(Color.csSuccess)
            } else {
                Button(String(format: String(localized: "Download (%@ GB)"),
                              preset.gigabytes.formatted(.number.precision(.fractionLength(1))))) { download(preset) }
                    .buttonStyle(.secondary)
                    .disabled(installed == nil || downloading != nil)
            }
        }
        .padding(Theme.space("m"))
        .background(shape.fill(selected ? Color.csAccent.opacity(0.08) : Color.clear))
        .overlay(shape.strokeBorder(selected ? Color.csAccent : Color.csBorder, lineWidth: selected ? 1.5 : 1))
        .contentShape(shape)
        .onTapGesture { select(preset) }
    }

    /// Eski alanlar: elle adres ve model (LM Studio ya da başka bir model için), anahtar.
    @ViewBuilder private var advancedFields: some View {
        VStack(alignment: .leading, spacing: Theme.space("s")) {
            Grid(alignment: .leading, horizontalSpacing: Theme.space("m"), verticalSpacing: Theme.space("s")) {
                GridRow {
                    Text("Server address")
                    TextField("Server address", text: $address, prompt: Text(verbatim: LocalAIServer.ollamaURL))
                        .textFieldStyle(CSTextFieldStyle())
                        .focused($focused, equals: .address)
                        .onSubmit(commit)
                }
                GridRow {
                    Text("Model name")
                    TextField("Model name", text: $modelName, prompt: Text(verbatim: LocalAIServer.defaultModel))
                        .textFieldStyle(CSTextFieldStyle())
                        .focused($focused, equals: .model)
                        .onSubmit(commit)
                }
            }
            HStack(spacing: Theme.space("m")) {
                Button("Use Ollama") { use(LocalAIServer.ollamaURL) }.buttonStyle(.secondary)
                Button("Use LM Studio") { use(LocalAIServer.lmStudioURL) }.buttonStyle(.secondary)
                Spacer()
            }
            if LocalAIServer.normalize(address) == nil {
                ErrorText(error: String(format: String(localized: "This address is not valid. Example: %@"), LocalAIServer.ollamaURL))
            }
            HintText(text: "For LM Studio or another model, type the model name as the server shows it. In LM Studio, load the model and start the local server.")
            if model.hasKey(.local) {
                HStack(spacing: Theme.space("m")) {
                    DoneLabel(text: String(localized: "Key saved"))
                    Spacer()
                    Button("Remove key") {
                        model.removeKey(.local)
                        result = nil
                    }
                    .buttonStyle(.secondary)
                }
            } else {
                SecureField("API key (optional)", text: $key).textFieldStyle(CSTextFieldStyle())
            }
        }
        .padding(.top, Theme.space("s"))
    }

    private func refresh() async {
        guard usesOllama, let serverURL else {
            looked = true
            installed = nil
            return
        }
        installed = await OllamaAPI.installedModels(baseURL: serverURL)
        looked = true
    }

    private func select(_ preset: LocalModelPreset) {
        modelName = preset.id
        commit()
    }

    private func download(_ preset: LocalModelPreset) {
        guard let serverURL else { return }
        select(preset)
        downloading = preset.id
        progress = 0
        downloadError = nil
        Task {
            do {
                try await OllamaAPI.pull(preset.id, baseURL: serverURL) { value in
                    Task { @MainActor in progress = value }
                }
            } catch {
                downloadError = String(localized: "The download did not finish. Check your internet connection and that Ollama is open, then try again.")
            }
            downloading = nil
            await refresh()
        }
    }

    private func use(_ url: String) {
        address = url
        commit()
    }

    /// Yazılanı ayara yazar; değiştiyse eski deneme sonucu kalkar.
    private func commit() {
        let address = address.trimmingCharacters(in: .whitespacesAndNewlines)
        let name = modelName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard address != model.settings.localAIBaseURL || name != model.settings.localAIModel else { return }
        model.settings.localAIBaseURL = address
        model.settings.localAIModel = name
        result = nil
    }

    private func test() {
        commit()
        let typed = key
        checking = true
        result = nil
        Task {
            result = await model.testLocalAI(key: typed)
            if model.hasKey(.local) { key = "" }
            checking = false
        }
    }
}

/// Özel bölgenin dikey konumu ve yüksekliği (yüzde).
private struct CustomAreaSliders: View {
    @Binding var settings: UserSettings

    var body: some View {
        let percent = settings.region.verticalPercent
        Grid(alignment: .leading, verticalSpacing: Theme.space("m")) {
            GridRow {
                Text("Vertical position")
                Slider(value: Binding(get: { percent.position },
                                      set: { settings.setCustomRegion(settings.region.withVertical(position: $0, height: percent.height)) }),
                       in: 0...max(1, 100 - percent.height))
                Text(verbatim: percentText(percent.position)).font(.csCallout.monospacedDigit()).foregroundStyle(Color.csSecondary)
                    .frame(minWidth: 44, alignment: .trailing)
            }
            GridRow {
                Text("Height")
                Slider(value: Binding(get: { percent.height },
                                      set: { settings.setCustomRegion(settings.region.withVertical(position: percent.position, height: $0)) }),
                       in: CropRegion.minimumSize * 100...100)
                Text(verbatim: percentText(percent.height)).font(.csCallout.monospacedDigit()).foregroundStyle(Color.csSecondary)
                    .frame(minWidth: 44, alignment: .trailing)
            }
        }
        Button("Reset area") { settings.selectAreaPreset(.bottom) }.buttonStyle(.secondary)
    }
}

/// Temanın görünen adı ve kısa tarifi.
extension SubtitleTheme {
    var title: LocalizedStringKey {
        switch self {
        case .classic: "Classic"
        case .cinema: "Cinema"
        case .minimal: "Minimal"
        case .glass: "Nino Glass"
        case .contrast: "High Contrast"
        case .outline: "Outline"
        }
    }

    var subtitle: LocalizedStringKey {
        switch self {
        case .classic: "Translucent box"
        case .cinema: "Yellow, like a film"
        case .minimal: "Barely there"
        case .glass: "Frosted glass, blue edge"
        case .contrast: "Easiest to read"
        case .outline: "Like in-game text"
        }
    }
}

/// Bir altyazı satırını seçili temayla çizer (önizlemelerde ve tema kartlarında).
struct ThemedSubtitle: View {
    let text: String
    let style: SubtitleStyle
    let fontSize: CGFloat
    var maxLines: Int? = 2

    private var color: Color { style.textColor == .yellow ? Color(red: 1.0, green: 0.88, blue: 0.21) : .white }

    var body: some View {
        let label = Text(verbatim: text)
            .font(.system(size: fontSize, weight: weight))
            .foregroundStyle(color)
            .lineLimit(maxLines)
            .multilineTextAlignment(.center)
        let shape = RoundedRectangle(cornerRadius: corner, style: .continuous)
        switch style.theme {
        case .classic:
            label.shadow(color: .black.opacity(0.8), radius: 1, y: 1)
                .padding(.horizontal, fontSize * 0.5).padding(.vertical, fontSize * 0.2)
                .background(shape.fill(Color.black.opacity(Double(style.background) / 100 * 0.85)))
        case .cinema:
            label.shadow(color: .black, radius: fontSize * 0.08, y: fontSize * 0.04)
                .shadow(color: .black.opacity(0.9), radius: fontSize * 0.3)
        case .minimal:
            label.shadow(color: .black.opacity(0.9), radius: fontSize * 0.06, y: 1)
                .shadow(color: .black.opacity(0.5), radius: fontSize * 0.25)
        case .glass:
            // Demo ekranındaki görünüm: koyu lacivert kutu, ince mavi kenar, hafif mavi ışık.
            label.shadow(color: .black.opacity(0.6), radius: 1, y: 1)
                .padding(.horizontal, fontSize * 0.6).padding(.vertical, fontSize * 0.25)
                .background(shape.fill(Color(red: 0.024, green: 0.047, blue: 0.118).opacity(0.86)))
                .overlay(shape.strokeBorder(Color(red: 0.18, green: 0.55, blue: 1.0).opacity(0.45), lineWidth: max(1, fontSize * 0.045)))
                .shadow(color: Color(red: 0.18, green: 0.55, blue: 1.0).opacity(0.25), radius: fontSize * 0.4)
        case .contrast:
            label.padding(.horizontal, fontSize * 0.45).padding(.vertical, fontSize * 0.18)
                .background(RoundedRectangle(cornerRadius: fontSize * 0.12, style: .continuous).fill(Color.black))
        case .outline:
            ZStack {
                ForEach(0..<8, id: \.self) { i in
                    let a = Double(i) * .pi / 4
                    label.foregroundStyle(.black)
                        .offset(x: cos(a) * max(1, fontSize * 0.07), y: sin(a) * max(1, fontSize * 0.07))
                }
                label
            }
            .shadow(color: .black.opacity(0.6), radius: fontSize * 0.15)
        }
    }

    private var weight: Font.Weight {
        switch style.theme {
        case .minimal: .medium
        case .contrast, .outline, .cinema: .bold
        default: style.bold ? .bold : .semibold
        }
    }

    private var corner: CGFloat { style.theme == .glass ? fontSize * 0.45 : fontSize * 0.3 }
}

/// Oyun sahnesi gibi koyu bir zemin (önizlemelerde).
struct PreviewScene: View {
    var body: some View {
        GeometryReader { geo in
            let w = geo.size.width
            ZStack {
                LinearGradient(colors: [Color(red: 0.10, green: 0.14, blue: 0.28), Color(red: 0.24, green: 0.14, blue: 0.22),
                                        Color(red: 0.06, green: 0.08, blue: 0.14)], startPoint: .topLeading, endPoint: .bottomTrailing)
                Circle().fill(Color.orange.opacity(0.45)).frame(width: w * 0.4).blur(radius: w * 0.08).offset(x: w * 0.25, y: -w * 0.1)
                Circle().fill(Color(red: 0.0, green: 0.44, blue: 0.82).opacity(0.4)).frame(width: w * 0.45).blur(radius: w * 0.1).offset(x: -w * 0.3, y: -w * 0.02)
            }
        }
    }
}

/// Tema seçici: 3×2 kart; her kartta temanın küçük önizlemesi, adı ve tek satırlık tarifi.
struct SubtitleThemePicker: View {
    @EnvironmentObject private var model: AppModel
    var columns = 3

    var body: some View {
        LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: Theme.space("m")), count: columns), spacing: Theme.space("m")) {
            ForEach(SubtitleTheme.allCases, id: \.self) { theme in
                ThemeCard(theme: theme, selected: model.settings.style.theme == theme) {
                    withAnimation(.spring(response: 0.35, dampingFraction: 0.8)) {
                        model.settings.style = theme.applied(to: model.settings.style)
                    }
                    model.sendTestSubtitle()
                }
            }
        }
    }
}

private struct ThemeCard: View {
    let theme: SubtitleTheme
    let selected: Bool
    let action: () -> Void
    @State private var hovering = false

    var body: some View {
        Button(action: action) {
            VStack(alignment: .leading, spacing: Theme.space("s")) {
                ZStack {
                    PreviewScene()
                    ThemedSubtitle(text: "Kim var orada?", style: theme.applied(to: SubtitleStyle()), fontSize: 11)
                        .padding(.top, 26)
                }
                .aspectRatio(16 / 9, contentMode: .fit)
                .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
                .overlay(alignment: .topTrailing) {
                    if selected {
                        Image(systemName: "checkmark.circle.fill")
                            .font(.system(size: 18, weight: .bold))
                            .foregroundStyle(.white, Color.csAccent)
                            .padding(6)
                            .transition(.scale.combined(with: .opacity))
                    }
                }
                VStack(alignment: .leading, spacing: 1) {
                    Text(theme.title).font(.csCallout.weight(.semibold)).foregroundStyle(Color.csText).lineLimit(1)
                    Text(theme.subtitle).font(.system(size: 11)).foregroundStyle(Color.csSecondary).lineLimit(1)
                }
                .padding(.horizontal, 2)
            }
            .padding(Theme.space("s"))
            .background(RoundedRectangle(cornerRadius: 14, style: .continuous)
                .fill(selected ? Color.csAccentSoft : Color.clear))
            .overlay(RoundedRectangle(cornerRadius: 14, style: .continuous)
                .strokeBorder(selected ? Color.csAccent : Color.ninoGlassEdge, lineWidth: selected ? 2 : 1))
            .scaleEffect(hovering ? 1.03 : 1)
            .shadow(color: selected ? Color.csAccent.opacity(0.25) : .clear, radius: 10, y: 4)
            .contentShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
        }
        .buttonStyle(.plain)
        .onHover { h in withAnimation(.spring(response: 0.3, dampingFraction: 0.75)) { hovering = h } }
        .accessibilityAddTraits(selected ? .isSelected : [])
    }
}

/// Canlı önizleme: oyun sahnesi gibi koyu bir ekranda, seçilen boyut, arka plan, kalınlık ve renkle örnek altyazı.
struct SubtitleStylePreview: View {
    let style: SubtitleStyle
    var size = CGSize(width: 452, height: 254)
    /// Çeviri sürerken gerçek satır (Türkçe, İngilizce); nil iken demo cümleleri akar.
    var live: (tr: String, en: String)? = nil
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var index = 0
    @State private var showEnglish = false
    @State private var showTurkish = false

    /// TV demosundaki gibi: önce oyunun İngilizce satırı, ardından üstüne Nino'nun Türkçesi.
    private static let lines: [(en: String, tr: String)] = [
        ("This city needs someone to watch over it.", "Bu şehrin onu kollayacak birine ihtiyacı var."),
        ("They're coming. Stay out of sight.", "Geliyorlar. Gözden uzak dur."),
        ("Who's there?", "Kim var orada?"),
        ("The rain hides everything.", "Yağmur her şeyi saklıyor."),
        ("Get to the rooftop. Now!", "Çatıya çık. Hemen!"),
        ("This isn't over.", "Bu iş daha bitmedi."),
    ]

    var body: some View {
        GeometryReader { geo in
            let w = geo.size.width
            let fontSize = max(CGFloat(style.autoSize ? 38 : style.fontSize) / 1920 * w * 1.6, 10)
            let line = live ?? Self.lines[index % Self.lines.count]
            let showTR = live.map { !$0.tr.isEmpty } ?? showTurkish
            let showEN = live == nil && showEnglish && !showTurkish
            let bottom = style.placement == .fixed
                ? max(geo.size.height * CGFloat(style.bottomPercent) / 100, 10) : geo.size.height * 0.08
            ZStack(alignment: .bottom) {
                PreviewScene()
                // Oyunun kendi İngilizce altyazısı
                Text(verbatim: line.en)
                    .font(.system(size: fontSize * 0.92, weight: .medium))
                    .foregroundStyle(Color(white: 0.95))
                    .shadow(color: .black, radius: 2, y: 1)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 20)
                    .padding(.bottom, bottom)
                    .opacity(showEN ? 1 : 0)
                // Nino'nun Türkçesi, seçili temayla
                if showTR {
                    ThemedSubtitle(text: line.tr, style: style, fontSize: fontSize)
                        .padding(.horizontal, 16)
                        .padding(.bottom, bottom)
                        .transition(.opacity.combined(with: .scale(scale: 0.96, anchor: .bottom)))
                }
            }
            .animation(.easeOut(duration: 0.3), value: showEnglish)
            .animation(.spring(response: 0.35, dampingFraction: 0.85), value: showTurkish)
            .animation(.spring(response: 0.35, dampingFraction: 0.85), value: style)
            .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 14, style: .continuous).strokeBorder(Color.ninoGlassEdge))
        }
        .frame(width: size.width, height: size.height)
        .accessibilityHidden(true)
        .task {
            if reduceMotion { showTurkish = true; return }
            while !Task.isCancelled {
                showEnglish = true
                try? await Task.sleep(for: .milliseconds(900))
                showTurkish = true
                try? await Task.sleep(for: .milliseconds(2600))
                showTurkish = false
                showEnglish = false
                try? await Task.sleep(for: .milliseconds(500))
                index += 1
            }
        }
    }
}
