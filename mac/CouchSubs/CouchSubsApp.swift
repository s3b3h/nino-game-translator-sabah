// SPDX-License-Identifier: AGPL-3.0-only

import CouchSubsCore
#if !APP_STORE
// Mac App Store sürümünde (APP_STORE) güncellemeyi App Store yapar; Sparkle pakete hiç girmez.
import Sparkle
#endif
import SwiftUI

@main
struct CouchSubsApp: App {
    @StateObject private var model = Self.makeModel()
    /// Bilgisayar ekranındaki altyazı penceresi.
    @State private var overlay = SubtitleOverlayController()
    #if !APP_STORE
    /// Sparkle: her açılışta ve uygulama açıkken saatte bir GitHub'daki son sürüme bakar; testlerde başlamaz.
    /// Nino: Nino'nun kendi appcast'i ve anahtarıyla (bkz. project.yml SUFeedURL, SUPublicEDKey). Yeni sürüm arka planda
    /// iner ve uygulama kapanınca kendiliğinden kurulur; Ayarlar › Güncellemeler'deki düğme de bunu kullanır.
    private let updater = AppUpdater.controller
    #endif

    /// Testler uygulamanın içinde çalışır. Gerçek Anahtarlığa dokunmazlar: imza farklı olunca macOS parola sorar ve test takılır.
    private static func makeModel() -> AppModel {
        ProcessInfo.processInfo.environment["XCTestConfigurationFilePath"] == nil ? AppModel() : AppModel(store: EphemeralStore())
    }

    var body: some Scene {
        WindowGroup {
            RootView()
                .environmentObject(model)
                // Sparkle kendi takviminde günde bir bakar; yeni sürüm her açılışta fark edilsin diye açılışta da sessizce bakılır.
                .task {
                    overlay.attach(model)
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
            Group {
                if model.step == .done { MainView() } else { OnboardingView() }
            }
            .opacity(showSplash ? 0 : 1)
            if showSplash {
                SplashView { withAnimation(.easeOut(duration: 0.35)) { showSplash = false } }
                    .transition(.opacity)
            }
        }
        .sheet(isPresented: $model.showAbout) { AboutView().appSurface() }
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
