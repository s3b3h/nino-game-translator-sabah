// SPDX-License-Identifier: AGPL-3.0-only

import CouchSubsCore
#if !APP_STORE
// Mac App Store sürümünde (APP_STORE) güncellemeyi App Store yapar; Sparkle pakete hiç girmez.
import Sparkle
#endif
import SwiftUI

/// Nino 4.0.5: uygulama `--ocr-helper` ile açıldıysa pencere açmaz, yedek okuyucu olarak çalışır (`OcrHelper`).
@main
enum NinoLauncher {
    static func main() {
        if CommandLine.arguments.contains(OcrHelper.argument) { OcrHelper.runAsHelper() }
        CouchSubsApp.main()
    }
}

struct CouchSubsApp: App {
    /// Nino: her şeyden önce (özellikler bildirim sırasıyla kurulur; bu ilkidir): CouchSubs'tan kalan veri ve günlük
    /// klasörleri, hiçbir dosya açılmadan `Nino` adına taşınır (bkz. `AppFolders`).
    private let folders = AppFolders.prepareAtLaunch()
    @StateObject private var model = Self.makeModel()
    /// Bilgisayar ekranındaki altyazı penceresi.
    @State private var overlay = SubtitleOverlayController()
    /// Yayın programlarının yakaladığı düz zeminli altyazı penceresi (Ayarlar > OBS'ten açılır).
    @State private var stream = StreamWindowController()
    #if !APP_STORE
    /// Sparkle: her açılışta ve uygulama açıkken saatte bir GitHub'daki son sürüme bakar; testlerde başlamaz.
    /// Nino: Nino'nun kendi appcast'i ve anahtarıyla (bkz. project.yml SUFeedURL, SUPublicEDKey). Yeni sürüm arka planda
    /// iner ve uygulama kapanınca kendiliğinden kurulur; Ayarlar › Güncellemeler'deki düğme de bunu kullanır.
    private let updater = AppUpdater.controller
    #endif

    /// Nino: arayüz çeviri dilinde (Türkçe, Arapça, Hintçe, Endonezce…); listede olmayan dilde İngilizce.
    static func uiLanguage(_ target: String) -> String { TargetLanguage.interfaceLanguage(target) }

    /// Testler uygulamanın içinde çalışır. Gerçek Anahtarlığa dokunmazlar: imza farklı olunca macOS parola sorar ve test takılır.
    private static func makeModel() -> AppModel {
        AppFolders.prepareAtLaunch()
        return ProcessInfo.processInfo.environment["XCTestConfigurationFilePath"] == nil ? AppModel() : AppModel(store: EphemeralStore())
    }

    var body: some Scene {
        WindowGroup {
            RootView()
                .environmentObject(model)
                // Nino: arayüz dili çeviri diliyle aynı (Türkçe ya da Arapça; Android ve iPhone'daki gibi): bayrak seçilince
                // ekranlar o dile geçer, Arapçada sağdan sola dizilir. `String(localized:)` ile kurulan metinler (durum
                // satırları gibi) sistem dilinden okunduğu için seçim AppleLanguages'a da yazılır: sonraki açılışta onlar da
                // aynı dilde olur.
                .environment(\.locale, Locale(identifier: Self.uiLanguage(model.settings.targetLanguage)))
                .environment(\.layoutDirection, TargetLanguage.isRightToLeft(model.settings.targetLanguage) ? .rightToLeft : .leftToRight)
                .onChange(of: model.settings.targetLanguage) { target in
                    UserDefaults.standard.set([Self.uiLanguage(target)], forKey: "AppleLanguages")
                }
                // Sparkle kendi takviminde günde bir bakar; yeni sürüm her açılışta fark edilsin diye açılışta da sessizce bakılır.
                .task {
                    overlay.attach(model)
                    stream.attach(model)
                    // Yazı okuması takılıp kendini yeniden açtıysa çeviri kaldığı yerden sürer.
                    await model.resumeIfRelaunched()
                }
                .appSurface()
                .frame(minWidth: Theme.size("windowWidth"), idealWidth: Theme.size("windowWidth"), maxWidth: Theme.size("windowWidth") * 1.25,
                       minHeight: Theme.size("windowHeight"), idealHeight: Theme.size("windowHeight"))
                // Başlık çubuğu da pencere zemininin rengini alır (macOS 15 ve sonrası; öncesinde sistem rengi).
                .windowBackground(Color.csBackground)
                .toolbarBackground(.hidden, for: .windowToolbar)
        }
        .windowResizability(.contentSize)
        .commands {
            CommandGroup(replacing: .appInfo) {
                Button("About Nino") { model.showAbout = true }
            }
            CommandGroup(replacing: .appSettings) {
                Button("Settings") { model.showSettings = true }
                    .keyboardShortcut(",")
                    .disabled(model.step != .done)
            }
        }
        // Altyazı bilgisayar ekranındayken menü çubuğundan pencereye ulaşılır ("Tıklamalar geçsin" açıkken geri dönüş yolu).
        MenuBarExtra("Nino", systemImage: "captions.bubble",
                     isInserted: Binding(get: { model.step == .done && model.showsOnComputer }, set: { _ in })) {
            // Nino: yakalama kartıyla oyun bu Mac'te gösteriliyorsa durum ve tam ekran.
            if model.usesCaptureCard {
                Text(verbatim: model.cardStatusText)
                if model.showsCardPlayer {
                    Button("Game Full Screen") { model.toggleCardFullScreen() }
                        .keyboardShortcut("f", modifiers: [.control, .command])
                }
                Divider()
            }
            Toggle("Clicks pass through", isOn: Binding(get: { model.settings.overlayClickThrough },
                                                        set: { model.settings.overlayClickThrough = $0 }))
            Button("Adjust the subtitle window") { model.overlayAdjusting = true }
            Divider()
            Button("Open Nino") {
                if #available(macOS 14, *) { NSApp.activate() } else { NSApp.activate(ignoringOtherApps: true) }
            }
        }
    }
}

struct RootView: View {
    @EnvironmentObject private var model: AppModel
    /// Açılış animasyonu her açılışta bir kez oynar.
    @State private var showSplash = ProcessInfo.processInfo.environment["XCTestConfigurationFilePath"] == nil

    var body: some View {
        ZStack {
            // Nino: ana ekran açılış logosu kalkınca kurulur; salondaki fiş ve sayaç gösterisi logonun arkasında oynayıp
            // kaçıyordu (kullanıcı isteği, 21 Kasım 2026).
            if !showSplash || model.step != .done {
                Group {
                    if model.step == .done { MainView() } else { OnboardingView() }
                }
                .opacity(showSplash ? 0 : 1)
            }
            if showSplash {
                SplashView { withAnimation(.easeOut(duration: 0.35)) { showSplash = false } }
                    .transition(.opacity)
            }
        }
        // Nino: "Nino'ya Sor": yüzen robot. Ana ekranda sol altta (sağ altta fiş ve kablo durur: PS5 ve Xbox sahnesi),
        // kurulumda sağ altta Devam düğmesinin üstünde.
        .overlay(alignment: model.step == .done ? .bottomLeading : .bottomTrailing) {
            if !showSplash {
                AskNinoButton()
                    .padding(model.step == .done ? .leading : .trailing, Theme.space("xl"))
                    .padding(.bottom, model.step == .done ? 60 : 96)
                    .transition(.scale.combined(with: .opacity))
            }
        }
        .sheet(isPresented: $model.showAbout) { AboutView().appSurface() }
        .sheet(isPresented: $model.showAssistant) { AskNinoSheet().appSurface() }
        #if DEBUG
        // Tasarım denemesi için: open Nino.app --args -NinoPreviewStep 4  (7 = ana ekran)
        .onAppear {
            let n = UserDefaults.standard.integer(forKey: "NinoPreviewStep")
            if n > 0, let step = AppModel.Step(rawValue: n - 1) { model.step = step }
        }
        #endif
    }
}

private extension View {
    /// Pencere zemini; `containerBackground(_:for: .window)` macOS 15'te geldi.
    @ViewBuilder func windowBackground(_ color: Color) -> some View {
        if #available(macOS 15, *) {
            containerBackground(color, for: .window)
        } else {
            self
        }
    }
}
