// SPDX-License-Identifier: AGPL-3.0-only
// Karşılama ve kurulum (PSN girişi, PS5 eşleme, altyazının yeri). Onaylı tuvaldeki Telefon · 1–6 ekranları;
// uygulama hesap istemediği için kayıt/giriş ekranı yok.

import CouchSubsCore
import RemotePlay
import SwiftUI

// MARK: - 1–2 Karşılama (3 sayfa)

struct WelcomeFlow: View {
    @EnvironmentObject private var model: PhoneModel
    @Environment(\.locale) private var locale
    let onFinish: () -> Void
    @State private var page = Self.initialPage

    private var t: L10n { L10n(locale: locale) }

    /// Hata ayıklama: COUCHSUBS_WELCOME_PAGE=0…2 ile karşılamanın o sayfası açılır (ekran görüntüsü için).
    private static var initialPage: Int {
        #if DEBUG
        return Int(ProcessInfo.processInfo.environment["COUCHSUBS_WELCOME_PAGE"] ?? "").map { min(max($0, 0), 2) } ?? 0
        #else
        return 0
        #endif
    }

    var body: some View {
        MobileScreen {
            // Nino: üstte logo, çeviri dili bayrakları ve Atla.
            HStack(spacing: 10) {
                LogoView(size: 36)
                Spacer()
                LanguageFlags(selection: $model.settings.targetLanguage)
                Button(t("ob.skip"), action: onFinish).buttonStyle(.mobileGhost)
            }
            .environment(\.layoutDirection, .leftToRight)
            .frame(height: Mobile.Control.icon)
        } content: {
            TabView(selection: $page) {
                pageView(stage: AnyView(SubtitleDemoStage(target: model.settings.targetLanguage, locale: locale)),
                         title: t("ob.p1.title"), message: t("ob.p1.body")).tag(0)
                pageView(stage: AnyView(packsStage), title: t("ob.p2.title"), message: t("ob.p2.body")).tag(1)
                pageView(stage: AnyView(screensStage), title: t("ob.p3.title"), message: t("ob.p3.body")).tag(2)
            }
            .tabViewStyle(.page(indexDisplayMode: .never))
            .frame(minHeight: 610)
        } bottom: {
            PageDots(count: 3, current: page)
            Button(page == 2 ? t("ob.start") : t("ob.continue")) {
                if page == 2 { onFinish() } else { withAnimation { page += 1 } }
            }
            .buttonStyle(.mobilePrimary)
        }
    }

    private func pageView(stage: AnyView, title: String, message: String) -> some View {
        VStack(alignment: .leading, spacing: 22) {
            NinoStage(height: 380) { stage }
            NinoTitle(title: title, message: message)
            Spacer(minLength: 0)
        }
        .padding(.top, 4)
    }

    /// 2. sayfa: hazır paketler (camsı satırlar, satır sayısı ve "Ücretsiz").
    private var packsStage: some View {
        VStack(spacing: 10) {
            ForEach([("Grand Theft Auto V", "190"), ("Red Dead Redemption 2", "195"), ("Mafia", "18")], id: \.0) { game in
                GlassRow(symbol: "gamecontroller.fill", title: game.0, detail: String(format: t("ob.p2.lines"), game.1)) {
                    FreeTag(text: t("ob.free"))
                }
            }
        }
        .padding(18)
    }

    /// 3. sayfa: TV'de ya da telefonda; altında "Aynı Wi-Fi yeterli".
    private var screensStage: some View {
        VStack(spacing: 12) {
            HStack(spacing: 12) {
                option(symbol: "tv", title: t("ob.p3.tv"), detail: t("ob.p3.tv.detail"))
                option(symbol: "iphone", title: t("ob.p3.phone"), detail: t("ob.p3.phone.detail"))
            }
            GlassRow(symbol: "wifi", title: t("ob.p3.wifi"), detail: t("ob.p3.wifi.detail"))
        }
        .padding(18)
    }

    private func option(symbol: String, title: String, detail: String) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Image(systemName: symbol).font(.system(size: 22, weight: .semibold)).foregroundStyle(.white)
                .frame(width: 48, height: 48).background(Color.white.opacity(0.10), in: Circle())
            Spacer(minLength: 0)
            Text(verbatim: title).font(.system(size: 22, weight: .bold)).foregroundStyle(.white).lineLimit(1).minimumScaleFactor(0.7)
            Text(verbatim: detail).font(.system(size: 13)).foregroundStyle(.white.opacity(0.6)).lineLimit(2)
        }
        .frame(maxWidth: .infinity, minHeight: 170, alignment: .leading)
        .padding(16)
        .background(Color.white.opacity(0.07), in: RoundedRectangle(cornerRadius: 20, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 20, style: .continuous).strokeBorder(Color.white.opacity(0.12), lineWidth: 1))
    }
}

/// 1. sayfa sahnesi: "ÖRNEK" rozeti ve birkaç saniyede bir değişen İngilizce → Türkçe/Arapça örnek satır.
private struct SubtitleDemoStage: View {
    let target: String
    let locale: Locale

    var body: some View {
        TimelineView(.periodic(from: .now, by: 2.8)) { context in
            let index = Int(context.date.timeIntervalSinceReferenceDate / 2.8) % DemoSamples.count
            let line = DemoSamples.line(index, target: target)
            ZStack(alignment: .topLeading) {
                Color.clear
                Text(verbatim: UILanguage.text("ob.sample", locale)).font(.system(size: 12, weight: .bold)).tracking(1.2)
                    .foregroundStyle(.white.opacity(0.85))
                    .padding(.horizontal, 12).padding(.vertical, 7)
                    .background(Color.white.opacity(0.10), in: Capsule())
                    .overlay(Capsule().strokeBorder(Color.white.opacity(0.18), lineWidth: 1))
                    .padding(16)
                VStack(spacing: 14) {
                    Spacer()
                    Text(verbatim: line.source).font(.system(size: 15)).foregroundStyle(.white.opacity(0.5))
                        .multilineTextAlignment(.center)
                    Image(systemName: "arrow.down").font(.system(size: 14, weight: .semibold)).foregroundStyle(.white.opacity(0.35))
                    Text(verbatim: TargetLanguage.displayText(line.translation))
                        .font(.system(size: 26, weight: .bold)).foregroundStyle(.white)
                        .multilineTextAlignment(.center)
                        .padding(.horizontal, 18).padding(.vertical, 12)
                        .background(Color.black.opacity(0.55), in: RoundedRectangle(cornerRadius: 16, style: .continuous))
                        .subtitleDirection(line.translation)
                    Spacer()
                }
                .frame(maxWidth: .infinity)
                .padding(.horizontal, 20)
                .id(index)
                .transition(.opacity)
            }
            .animation(.easeInOut(duration: 0.35), value: index)
        }
        .environment(\.layoutDirection, .leftToRight)
    }
}

// MARK: - Kurulum adımları (4–6)

/// "Kurulum · Adım n/3" ve üç parçalı ilerleme çubuğu.
struct SetupHeader: View {
    let step: Int
    let onBack: (() -> Void)?
    /// Kurulumda "Şimdilik geç" (PSN ve PS5 adımları); ana ekrandan açılınca nil.
    var onSkip: (() -> Void)?

    var body: some View {
        VStack(alignment: .leading, spacing: Mobile.Space.gap) {
            HStack(spacing: Mobile.Space.gap) {
                if let onBack { IconButton(symbol: "chevron.left", label: "Back", action: onBack) }
                HStack(spacing: Mobile.Space.hair) {
                    ForEach(1...3, id: \.self) { index in
                        Capsule().fill(index <= step ? Mobile.Palette.accent : Mobile.Palette.borderStrong).frame(height: 4)
                    }
                }
                if let onSkip { Button("Skip for now", action: onSkip).buttonStyle(.mobileGhost).fixedSize() }
            }
            .frame(height: Mobile.Control.icon)
        }
    }
}

struct PSNScreen: View {
    @EnvironmentObject private var model: PhoneModel
    @Environment(\.locale) private var locale
    @State private var showDemo = false
    private var t: L10n { L10n(locale: locale) }
    var onBack: (() -> Void)?
    var onSkip: (() -> Void)?
    var onDone: () -> Void
    @State private var showLogin = false
    @State private var showWhy = false
    @State private var redirected = false
    @State private var working = false
    @State private var error: String?

    var body: some View {
        MobileScreen {
            SetupHeader(step: 1, onBack: onBack, onSkip: onSkip)
        } content: {
            NinoTitle(step: String(format: t("setup.step"), 1), title: t("psn.title"), message: t("psn.body"))
            NinoStage {
                VStack(spacing: 10) {
                    GlassRow(symbol: "person.badge.plus", title: t("psn.free"), detail: t("psn.free.detail"))
                    GlassRow(symbol: "gamecontroller.fill", title: t("psn.play"), detail: t("psn.play.detail"))
                    GlassRow(symbol: "lock.shield.fill", title: t("psn.password"), detail: t("psn.password.detail"))
                }
                .padding(16)
            }
            .padding(.top, 6)
            // Kol ikinci hesaba atanırsa ana hesapla açılan oyun onu kendi kolu saymaz (GitHub #231).
            MobileNote(text: String(localized: "When you turn on the controller to play, choose your MAIN account on the PS5. Don't play with the second account Nino signs in with, or the controller won't work in the game."))
            if model.accountId != nil { MobilePill(text: t("psn.signedIn"), dot: true) }
            if working { ProgressView().tint(Mobile.Palette.accent) }
            if let error { MobileNote(text: error) }
        } bottom: {
            HStack {
                Button { showWhy = true } label: { Text(verbatim: t("psn.why")).lineLimit(1).minimumScaleFactor(0.75) }.buttonStyle(.mobileGhost)
                Spacer()
                TryWithoutPS5Button(title: t("demo.try")) { showDemo = true }
            }
            if model.accountId != nil {
                Button(t("psn.again")) {
                    redirected = false
                    showLogin = true
                }
                .buttonStyle(.mobileSecondary)
                Button(t("ob.continue"), action: onDone).buttonStyle(.mobilePrimary)
            } else {
                Button(t("psn.signIn")) {
                    redirected = false
                    showLogin = true
                }
                .buttonStyle(.mobilePrimary)
                .disabled(working)
            }
        }
        .sheet(isPresented: $showLogin, onDismiss: {
            if !redirected { error = PhoneError.loginWindowClosed.localizedDescription }
        }) {
            NavigationStack {
                LoginWebView(onRedirect: received, onProblem: { _ in })
                    .navigationTitle(Text(verbatim: "PlayStation Network"))
                    .navigationBarTitleDisplayMode(.inline)
                    .toolbar { ToolbarItem(placement: .cancellationAction) { Button("Cancel") { showLogin = false } } }
            }
            .presentationDragIndicator(.visible)
        }
        .sheet(isPresented: $showWhy) {
            VStack(alignment: .leading, spacing: Mobile.Space.gap) {
                NinoTitle(title: t("psn.why"), message: t("psn.whyBody"))
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(Mobile.Space.screen)
            .fittedSheet()
            .sheetBackground(Mobile.Palette.surface)
        }
        .fullScreenCover(isPresented: $showDemo) { DemoPreviewScreen() }
    }

    private func received(_ url: URL) {
        redirected = true
        showLogin = false
        working = true
        error = nil
        Task {
            do {
                try await model.completePSNLogin(redirect: url)
                onDone()
            } catch {
                self.error = error.localizedDescription
            }
            working = false
        }
    }
}

struct PS5PairScreen: View {
    @EnvironmentObject private var model: PhoneModel
    @Environment(\.locale) private var locale
    @State private var showDemo = false
    private var t: L10n { L10n(locale: locale) }
    var onBack: (() -> Void)?
    var onSkip: (() -> Void)?
    var onDone: () -> Void
    @State private var consoles: [ConsoleInfo] = []
    @State private var manualHost = ""
    @State private var pin = ""
    @State private var searching = false
    @State private var working = false
    @State private var error: String?
    @State private var showManual = false
    @FocusState private var codeFocused: Bool

    private var host: String {
        let typed = manualHost.trimmingCharacters(in: .whitespaces)
        return typed.isEmpty ? consoles.first?.host ?? "" : typed
    }

    var body: some View {
        MobileScreen {
            SetupHeader(step: 2, onBack: onBack, onSkip: onSkip)
        } content: {
            NinoTitle(step: String(format: t("setup.step"), 2), title: t("pair.title"), message: t("pair.body"))
            NinoStage {
                GlassRow(symbol: "gamecontroller.fill", title: consoleTitle, detail: consoleDetail) {
                    if !host.isEmpty && !searching {
                        Circle().fill(Color(hex: 0x30C578)).frame(width: 10, height: 10)
                    } else {
                        SearchAgainButton(searching: searching) { Task { await search() } }
                    }
                }
                .padding(14)
            }
            .padding(.top, 6)
            Tile {
                Text(verbatim: t("pair.code")).font(Mobile.TypeScale.caption).foregroundStyle(Mobile.Palette.secondary)
                ZStack {
                    TextField("", text: $pin)
                        .keyboardType(.numberPad)
                        .textContentType(.oneTimeCode)
                        .focused($codeFocused)
                        .opacity(0.01)
                        .onChange(of: pin) { value in pin = String(value.filter(\.isNumber).prefix(8)) }
                    HStack(spacing: Mobile.Space.hair + 2) {
                        ForEach(0..<8, id: \.self) { index in
                            let digits = Array(pin)
                            Text(verbatim: index < digits.count ? String(digits[index]) : "")
                                .font(Mobile.TypeScale.title)
                                .frame(maxWidth: .infinity, minHeight: Mobile.Control.field)
                                .background(Mobile.Palette.surface2, in: RoundedRectangle(cornerRadius: Mobile.Radius.inner))
                                .overlay(RoundedRectangle(cornerRadius: Mobile.Radius.inner)
                                    // Kutular belli olsun: beyaz kenar açık zeminde görünmüyordu (Mac'te de aynı şikâyet vardı).
                                    .strokeBorder(index == digits.count && codeFocused ? Mobile.Palette.accent : Mobile.Palette.secondary.opacity(0.4),
                                                  lineWidth: index == digits.count && codeFocused ? 2 : 1.5))
                        }
                    }
                    .allowsHitTesting(false)
                }
                .contentShape(Rectangle())
                .onTapGesture { codeFocused = true }
                if let error {
                    MobileNote(text: error)
                } else {
                    Text(verbatim: t("pair.code.note"))
                        .font(Mobile.TypeScale.caption).foregroundStyle(Mobile.Palette.secondary)
                }
            }
            if working {
                HStack(spacing: Mobile.Space.inline) {
                    ProgressView().tint(Mobile.Palette.accent)
                    Text(verbatim: t("pair.connecting")).font(Mobile.TypeScale.caption).foregroundStyle(Mobile.Palette.secondary)
                }
            }
        } bottom: {
            HStack {
                Button { showManual = true } label: { Text(verbatim: t("pair.notFound")).lineLimit(1).minimumScaleFactor(0.75) }.buttonStyle(.mobileGhost)
                Spacer()
                TryWithoutPS5Button(title: t("demo.try")) { showDemo = true }
            }
            Button(t("pair.button")) { Task { await register() } }
                .buttonStyle(.mobilePrimary)
                .disabled(working || pin.count != 8 || host.isEmpty)
        }
        // Nino: arama ekran açık kaldıkça yinelenir; PS5 sonradan açılır ya da dinlenme modundan uyanırsa kendiliğinden
        // bulunur (bulunamazken 2 sn, bulununca 6 sn arayla; bulunduktan sonraki aramalar ekranı oynatmaz).
        .task {
            await search()
            while !Task.isCancelled {
                try? await Task.sleep(nanoseconds: (consoles.isEmpty ? 2 : 6) * 1_000_000_000)
                if Task.isCancelled { break }
                if consoles.isEmpty { await search() } else { await refreshQuietly() }
            }
        }
        .sheet(isPresented: $showManual) {
            VStack(alignment: .leading, spacing: Mobile.Space.gap) {
                ScreenTitle(title: "Can't find the PS5?",
                            message: "Make sure the PS5 is on (not in rest mode) and on the same Wi-Fi, and that Nino is allowed in Settings › Privacy & Security › Local Network. You can also type the PS5's IP address (PS5: Settings › Network › Connection Status).")
                TextField("IP address, e.g. 192.168.1.20", text: $manualHost)
                    .textFieldStyle(MobileFieldStyle())
                    .keyboardType(.decimalPad)
                Button("Search again") { Task { await search() } }.buttonStyle(.mobileSecondary)
                Button("Done") { showManual = false }.buttonStyle(.mobilePrimary)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(Mobile.Space.screen)
            .fittedSheet()
            .sheetBackground(Mobile.Palette.surface)
        }
        .fullScreenCover(isPresented: $showDemo) { DemoPreviewScreen() }
    }

    private var consoleTitle: String {
        if let found = consoles.first, manualHost.isEmpty { return String(format: t("pair.found"), found.name) }
        if !manualHost.isEmpty { return "PS5" }
        return t("pair.searching")
    }

    private var consoleDetail: String {
        if let found = consoles.first, manualHost.isEmpty { return String(format: t("pair.sameWifi"), found.host) }
        if !manualHost.isEmpty { return manualHost }
        return t("pair.searching.detail")
    }

    private func search() async {
        guard !searching else { return }
        searching = true
        consoles = await model.discoverConsoles()
        searching = false
    }

    /// PS5 zaten bulunmuşken arka planda tazeler (adresi değiştiyse günceller; bulunamazsa eskisini tutar).
    private func refreshQuietly() async {
        guard !searching, !working else { return }
        let found = await model.discoverConsoles()
        if !found.isEmpty { consoles = found }
    }

    private func register() async {
        guard !working else { return }
        working = true
        error = nil
        do {
            try await model.register(host: host, pin: pin)
            onDone()
        } catch {
            self.error = error.localizedDescription
        }
        working = false
    }
}

/// Altyazının yeri: ağdaki TV'ler (TV uygulaması kurulu) ya da bu telefon. Ayarlar › Altyazı hedefi de burayı açar.
struct TargetScreen: View {
    @EnvironmentObject private var model: PhoneModel
    @Environment(\.locale) private var locale
    private var t: L10n { L10n(locale: locale) }
    var setup = true
    var onBack: (() -> Void)?
    var onDone: () -> Void
    @State private var tvs: [LGTV] = []
    @State private var launched: [LGTV: Bool] = [:]
    @State private var searching = false
    @State private var working: LGTV?
    @State private var error: String?
    @State private var showManual = false
    @State private var manualHost = ""
    @State private var manualBrand = TVBrand.lg
    /// Elle yazılan adres geçersizse sayfada gösterilen ileti.
    @State private var manualError: String?
    @State private var showInstall = false

    var body: some View {
        MobileScreen {
            if setup { SetupHeader(step: 3, onBack: onBack) } else { BackHeader(title: "Subtitle target") }
        } content: {
            NinoTitle(step: setup ? String(format: t("setup.step"), 3) : nil, title: t("target.title"), message: t("target.body"))
            Tile(emphasis: model.settings.output.showsOnTV && model.hasTV ? .selected : .none) {
                HStack(spacing: Mobile.Space.gap) {
                    MobileTileIcon(symbol: "tv")
                    Text("On the TV, over the game").font(Mobile.TypeScale.headline)
                    Spacer()
                    if !allTVs.isEmpty {
                        SearchAgainButton(searching: searching) { Task { await search() } }
                    }
                }
                ForEach(allTVs, id: \.self) { tv in
                    RowDivider()
                    Button { Task { await pair(tv) } } label: { tvRow(tv) }.buttonStyle(.plain).disabled(working != nil)
                }
                if allTVs.isEmpty {
                    HStack(spacing: Mobile.Space.gap) {
                        Text(searching ? "Looking for the TV on the network…" : "No TV found on the network.")
                            .font(Mobile.TypeScale.caption).foregroundStyle(Mobile.Palette.secondary)
                        Spacer()
                        SearchAgainButton(searching: searching) { Task { await search() } }
                    }
                }
            }
            BentoGrid {
                Button { model.settings.output = .computer } label: {
                    InfoTile(symbol: "iphone", title: "On this phone", caption: "No TV, or the app is not installed",
                             emphasis: model.settings.output == .computer ? .selected : .none)
                }
                .buttonStyle(.plain)
                Button { showManual = true } label: {
                    InfoTile(symbol: "questionmark.circle", title: "My TV is not listed", caption: "Supported TVs")
                }
                .buttonStyle(.plain)
            }
            // TV uygulaması yoksa ya da eskiyse bu telefondan kurulur (ilk kurulumda da).
            Button { showInstall = true } label: {
                InfoTile(symbol: "arrow.down.app", title: "Install the TV app from this phone", caption: "Samsung · LG · Android TV",
                         emphasis: model.tvAppMissing ? .selected : .none)
            }
            .buttonStyle(.plain)
            if let error { MobileNote(text: error) }
        } bottom: {
            Button(setup ? t("ob.continue") : t("common.done"), action: onDone)
                .buttonStyle(.mobilePrimary)
                .disabled(!(model.hasTV || model.settings.output == .computer))
        }
        .task { await search() }
        .sheet(isPresented: $showManual) { manualSheet }
        .sheet(isPresented: $showInstall, onDismiss: { Task { await search() } }) {
            // Kurulum bitince sayfa kapanır ve TV eşlendiyse bu adım da geçilir (Android'de ana ekrana geçilir, #113).
            TVInstallScreen(onDone: {
                showInstall = false
                if !setup || model.canAdvance { onDone() }
            }).environmentObject(model)
        }
    }

    private var allTVs: [LGTV] {
        var list = tvs
        if let tv = model.tv, model.hasTV, !list.contains(where: { $0.host == tv.host && $0.brand == tv.brand }) { list.insert(tv, at: 0) }
        return list
    }

    private func tvRow(_ tv: LGTV) -> some View {
        let selected = model.hasTV && model.tv?.host == tv.host && model.tv?.brand == tv.brand && model.settings.output.showsOnTV
        let ready = launched[tv] ?? (selected ? !model.tvAppMissing : nil)
        return HStack(spacing: Mobile.Space.gap) {
            Image(systemName: selected ? "checkmark.circle.fill" : "circle")
                .foregroundStyle(selected ? Mobile.Palette.accent : Mobile.Palette.secondary)
            VStack(alignment: .leading, spacing: Mobile.Space.hair) {
                Text(verbatim: tv.name).font(Mobile.TypeScale.headline)
                Text(verbatim: Self.brandName(tv.brand) + (ready == true ? " · " + String(localized: "Nino installed") : ready == false ? " · " + String(localized: "no app") : ""))
                    .font(Mobile.TypeScale.caption).foregroundStyle(Mobile.Palette.secondary)
            }
            Spacer()
            if working == tv {
                ProgressView().tint(Mobile.Palette.accent)
            } else if ready == true {
                MobilePill(text: String(localized: "Ready"), dot: true)
            } else if ready == false {
                MobilePill(text: String(localized: "Not installed"))
            }
        }
        .frame(minHeight: Mobile.Control.row)
        .contentShape(Rectangle())
    }

    static func brandName(_ brand: TVBrand) -> String {
        switch brand {
        case .lg: "LG"
        case .samsung: "Samsung"
        case .androidTV: "Android TV"
        }
    }

    private var manualSheet: some View {
        VStack(alignment: .leading, spacing: Mobile.Space.gap) {
            ScreenTitle(title: "My TV is not listed",
                        message: "Nino works with LG (webOS 4+), Samsung (Tizen, 2019+) and Android TV / Google TV. Type the TV's IP address, or choose Android TV: its Nino app finds this phone by itself.")
            SegmentedTabs(options: [TVBrand.lg: "LG", .samsung: "Samsung", .androidTV: "Android TV"], selection: $manualBrand)
            if manualBrand != .androidTV {
                TextField("IP address, e.g. 192.168.1.20", text: $manualHost)
                    .textFieldStyle(MobileFieldStyle())
                    .keyboardType(.decimalPad)
            }
            if manualBrand != .androidTV, let manualError { MobileNote(text: manualError) }
            Link("Supported TVs", destination: AppIdentity.tvGuideURL).font(Mobile.TypeScale.caption).tint(Mobile.Palette.accent)
            Button("Connect") {
                // Adres temizlenir ("192.168.1.5:3000", "http://…", virgüllü yazım); geçersizse sayfa açık kalır ve
                // söylenir. Eskiden olduğu gibi bağlanmaya gönderilen bozuk adres uygulamayı kapatıyordu.
                let host: String
                if manualBrand == .androidTV {
                    host = ""
                } else if let valid = ManualAddress.normalize(manualHost) {
                    host = valid
                } else {
                    manualError = String(localized: "This is not a valid IP address. Type it like 192.168.1.20, without http:// or a port number.")
                    return
                }
                manualError = nil
                showManual = false
                Task { await pair(LGTV(name: manualBrand == .androidTV ? "Android TV" : host, host: host, brand: manualBrand)) }
            }
            .buttonStyle(.mobilePrimary)
            .disabled(manualBrand != .androidTV && manualHost.isEmpty)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(Mobile.Space.screen)
        .fittedSheet()
        .sheetBackground(Mobile.Palette.surface)
    }

    private func search() async {
        guard !searching else { return }
        searching = true
        tvs = await model.discoverTVs()
        searching = false
    }

    private func pair(_ tv: LGTV) async {
        working = tv
        error = nil
        do {
            try await model.pair(tv)
            launched[tv] = !model.tvAppMissing
        } catch {
            self.error = String(localized: "Could not connect to the TV. Accept the request on the TV screen and try again.")
        }
        working = nil
    }
}

/// PS5 ve TV aramasının yanındaki "Yeniden ara" düğmesi; ararken aynı yerde dönen gösterge durur.
struct SearchAgainButton: View {
    let searching: Bool
    let action: () -> Void

    var body: some View {
        if searching {
            ProgressView()
                .tint(Mobile.Palette.accent)
                .frame(width: Mobile.Control.icon, height: Mobile.Control.icon)
        } else {
            IconButton(symbol: "arrow.clockwise", label: "Search again", tint: Mobile.Palette.accent, action: action)
        }
    }
}
