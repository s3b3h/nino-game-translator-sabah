// SPDX-License-Identifier: AGPL-3.0-only

import AppKit
import CouchSubsCore
import SwiftUI
import XCTest
@testable import Nino

/// Nino: çeviri dili Arapça seçilince Türkçeye özel işler (dublaj, paketler, çevrimiçi motorlar) kapanır ve altyazı
/// sağdan sola çizilir.
@MainActor
final class ArabicTargetTests: XCTestCase {
    func testOldSettingsOpenInTurkish() throws {
        let old = #"{"sourceLanguage":"en"}"#.data(using: .utf8)!
        XCTAssertEqual(try JSONDecoder().decode(UserSettings.self, from: old).targetLanguage, "tr")
    }

    func testArabicTurnsOffTurkishOnlyFeatures() {
        let store = MemoryStore()
        store.save("deepl-key", for: try! XCTUnwrap(TranslationEngine.deepL.storeKey))
        let model = AppModel(services: FakeServices(), store: store, defaults: .isolated())
        // Sistem dili Arapçaysa ilk açılış Arapça seçer; bu test Türkçeden başlar.
        model.settings.targetLanguage = "tr"
        model.settings.dubbing.enabled = true
        model.settings.translationEngine = .deepL
        XCTAssertTrue(model.dubbingActive)
        XCTAssertTrue(model.onlineTranslationActive)
        model.lastTranslation = "Bu iş daha bitmedi."
        model.settings.targetLanguage = "ar"
        XCTAssertFalse(model.dubbingActive)
        // Çevrimiçi motorlar Arapçaya da çevirir.
        XCTAssertTrue(model.onlineTranslationActive)
        // Türkçe son satır Arapça seçilince ekranda kalmaz.
        XCTAssertEqual(model.lastTranslation, "")
        model.settings.targetLanguage = "tr"
        XCTAssertTrue(model.dubbingActive)
    }

    /// Dil değişince altyazı penceresi temizlenir ama sonraki (Arapça) satırlar yine görünür.
    func testOverlayShowsLinesAfterSwitchingToArabic() {
        let model = AppModel(services: FakeServices(), store: MemoryStore(), defaults: .isolated())
        model.settings.output = .computer
        model.settings.targetLanguage = "tr"
        model.overlayReceive(.subtitle(text: "Bu iş daha bitmedi.", durationMs: 5000, paragraphs: false))
        XCTAssertFalse(model.overlayLines.isEmpty)
        model.settings.targetLanguage = "ar"
        XCTAssertTrue(model.overlayLines.isEmpty)
        model.overlayReceive(.subtitle(text: "أين المخيم؟", durationMs: 5000, paragraphs: false))
        XCTAssertEqual(model.overlayLines.map(\.text), ["أين المخيم؟"])
    }

    /// Ayarlar > Dil, Arapça seçiliyken (seçici ve uyarı). `NINO_ARABIC_SHOT` verilirse PNG yanına yazılır.
    func testLanguageSettingsRender() async throws {
        let model = AppModel(services: FakeServices(), store: MemoryStore(), defaults: .isolated())
        model.settings.targetLanguage = "ar"
        let size = CGSize(width: 900, height: 520)
        let window = NSWindow(contentRect: NSRect(origin: .zero, size: size), styleMask: [.titled], backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        window.appearance = NSAppearance(named: .darkAqua)
        window.contentView = NSHostingView(rootView: SettingsView(section: .language).environmentObject(model)
            .appSurface().frame(width: size.width, height: size.height))
        window.orderFrontRegardless()
        try await Task.sleep(for: .seconds(1))
        let view = try XCTUnwrap(window.contentView)
        let rep = try XCTUnwrap(view.bitmapImageRepForCachingDisplay(in: view.bounds))
        view.cacheDisplay(in: view.bounds, to: rep)
        window.close()
        if let path = ProcessInfo.processInfo.environment["NINO_ARABIC_SHOT"] {
            let png = try XCTUnwrap(rep.representation(using: .png, properties: [:]))
            try png.write(to: URL(fileURLWithPath: path.replacingOccurrences(of: ".png", with: "-ayar.png")))
        }
    }

    /// Altyazı penceresindeki satır (seçili temayla) Arapça örnekle çizilir. `NINO_ARABIC_SHOT` verilirse PNG oraya yazılır.
    func testArabicSubtitleRenders() throws {
        let text = "ARTHUR: أين المخيم؟ يجب أن نذهب، Dutch ينتظرنا.\nآرثر، انتظر؛ لم ننتهِ بعد."
        var style = SubtitleStyle()
        style.theme = .glass
        let classic = { () -> SubtitleStyle in var s = style; s.theme = .classic; return s }()
        let view = VStack(spacing: 24) {
            ThemedSubtitle(text: text, style: style, fontSize: 40, maxLines: nil)
            ThemedSubtitle(text: "ATREUS: Where is father?", style: classic, fontSize: 32, maxLines: nil)
        }
        .padding(40)
        .frame(width: 1100)
        .background(LinearGradient(colors: [Color(red: 0.2, green: 0.2, blue: 0.27), Color(red: 0.33, green: 0.2, blue: 0.2)],
                                   startPoint: .topLeading, endPoint: .bottomTrailing))
        let renderer = ImageRenderer(content: view)
        renderer.scale = 2
        let image = try XCTUnwrap(renderer.nsImage)
        XCTAssertGreaterThan(image.size.width, 0)
        if let path = ProcessInfo.processInfo.environment["NINO_ARABIC_SHOT"] {
            let tiff = try XCTUnwrap(image.tiffRepresentation)
            let png = try XCTUnwrap(NSBitmapImageRep(data: tiff)?.representation(using: .png, properties: [:]))
            try png.write(to: URL(fileURLWithPath: path))
        }
    }

    /// Arapça arayüz: `xcodebuild test -testLanguage ar` ile çalıştırılınca ana ekran, ayarlar ve kurulum PNG olarak
    /// `NINO_ARABIC_UI` klasörüne çizilir (verilmezse atlanır).
    func testArabicInterfaceScreens() async throws {
        guard let path = ProcessInfo.processInfo.environment["NINO_ARABIC_UI"] else { throw XCTSkip("NINO_ARABIC_UI verilmedi") }
        let folder = URL(fileURLWithPath: path, isDirectory: true)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        let model = AppModel(services: FakeServices(), store: MemoryStore(), defaults: .isolated())
        model.settings.targetLanguage = "ar"
        model.lastSource = "ARTHUR: Where is the camp? We have to go, Dutch is waiting."
        model.lastTranslation = "ARTHUR: أين المخيم؟ يجب أن نذهب، Dutch ينتظرنا."
        let setup = AppModel(services: FakeServices(), store: MemoryStore(), defaults: .isolated())
        let size = CGSize(width: Theme.size("windowWidth"), height: Theme.size("windowHeight"))
        let screens: [(String, AnyView)] = [
            ("ana", AnyView(MainView().environmentObject(model))),
            ("ayarlar-dil", AnyView(SettingsView(section: .language).environmentObject(model))),
            ("ayarlar-ceviri", AnyView(SettingsView(section: .translation).environmentObject(model))),
            ("ayarlar-alan", AnyView(SettingsView(section: .area).environmentObject(model))),
            ("kurulum", AnyView(OnboardingView().environmentObject(setup))),
        ]
        var windows: [(String, NSWindow)] = []
        for (name, view) in screens {
            let window = NSWindow(contentRect: NSRect(origin: .zero, size: size), styleMask: [.titled], backing: .buffered, defer: false)
            window.isReleasedWhenClosed = false
            window.appearance = NSAppearance(named: .darkAqua)
            window.contentView = NSHostingView(rootView: view.appSurface().frame(width: size.width, height: size.height))
            window.orderFrontRegardless()
            windows.append((name, window))
        }
        try await Task.sleep(for: .seconds(2))
        for (name, window) in windows {
            let view = try XCTUnwrap(window.contentView)
            let rep = try XCTUnwrap(view.bitmapImageRepForCachingDisplay(in: view.bounds))
            view.cacheDisplay(in: view.bounds, to: rep)
            try XCTUnwrap(rep.representation(using: .png, properties: [:])).write(to: folder.appendingPathComponent("\(name).png"))
            window.close()
        }
    }
}
