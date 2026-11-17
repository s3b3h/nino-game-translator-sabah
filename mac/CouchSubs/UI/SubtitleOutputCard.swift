// SPDX-License-Identifier: AGPL-3.0-only

import CouchSubsCore
import SwiftUI

/// "Altyazıyı göster: TV / Bilgisayar ekranı / İkisi de" ve bilgisayar ekranındaki pencerenin seçenekleri.
/// Ana ekranda ve ayarlarda aynı karo kullanılır (Windows'ta da aynı düzen).
struct SubtitleOutputCard: View {
    @EnvironmentObject private var model: AppModel
    /// Ayarlarda açıklamalar da gösterilir; ana ekranda karo kısa kalır.
    var detailed = false
    /// Nino: yakalama kartı rehberi (ayrı pencerede).
    @State private var showGuide = false

    var body: some View {
        Card {
            // Nino: oyun TV'de mi oynanıyor (PS5'e ikinci hesapla bağlanılır), yoksa bu bilgisayarda PS Remote Play
            // penceresinde mi (görüntü pencereden okunur, altyazı pencerenin üstünde; monitörde oynayanlar için).
            // Nino: önce konsol (PS5 ya da Xbox) açıkça seçilir; görüntü kaynağı seçenekleri konsola göre değişir. Xbox'ta
            // PS5'e doğrudan bağlanma yoktur: Xbox penceresi (xbox.com/play ya da Greenlight) ya da Capture Card.
            Text("Console").font(.csCaption).foregroundStyle(Color.csSecondary)
            NinoSegmented(selection: Binding(get: { model.settings.gameConsole }, set: { model.switchConsole(to: $0) }), options: [
                (.ps5, "PS5", "gamecontroller"),
                (.xbox, "Xbox", "gamecontroller.fill"),
            ])
            Text("Game picture from").font(.csCaption).foregroundStyle(Color.csSecondary)
            if model.settings.gameConsole == .xbox {
                NinoSegmented(selection: $model.settings.videoSource, options: [
                    (.window, String(localized: "Xbox window"), "macwindow"),
                    (.card, String(localized: "Capture card"), "cable.connector"),
                ])
                if detailed && model.usesGameWindow {
                    HintText(text: "Xbox: open Greenlight or xbox.com/play › My consoles in your browser and sign in with your Microsoft account. Nino reads that window and shows the translation on top.")
                }
            } else {
                NinoSegmented(selection: $model.settings.videoSource, options: [
                    (.ps5, "PS5", "gamecontroller"),
                    (.window, String(localized: "Remote Play window"), "macwindow"),
                    (.card, String(localized: "Capture card"), "cable.connector"),
                ])
            }
            if model.usesCaptureCard {
                // Nino: kartla iki düzen var: geçişli kartla oyun TV'de (altyazı TV uygulamasında) ya da oyun bu
                // bilgisayarda tam ekran (altyazı üstünde; akıllı olmayan TV ve monitörler için).
                outputPicker
                HintText(text: model.showsOnTV
                    ? "TV: the PS5 picture goes to the TV through the card's HDMI out. Nino reads the card and sends the translation to the TV app."
                    : "Computer: Nino shows the game full screen with its sound and the translation on top. Connect this computer to your TV or monitor.")
                if detailed && !model.isRunning {
                    CaptureCardCheck(previewHeight: 170)
                }
                Button {
                    showGuide = true
                } label: {
                    Label("Connection guide", systemImage: "list.bullet.rectangle")
                }
                .buttonStyle(.secondary)
                .disabled(model.isRunning)
                .help(Text("How to connect the PS5, the card and your screen, and how to turn off HDCP."))
            } else if model.usesGameWindow {
                // Nino: Xbox'un açıklaması yukarıda (konsol seçiminin altında); bu açıklama yalnız PS5 içindir.
                if model.settings.gameConsole != .xbox {
                    HintText(text: "Play in PS Remote Play or chiaki-ng on this computer. Nino reads that window and shows the translation on top of the game. No second account needed.")
                }
                ComputerScreenOptions()
            } else {
                // Nino: PS5 yolunda altyazı her zaman TV uygulamasındadır; yer seçimi yalnız Capture Card'da gösterilir.
                HintText(text: "Subtitles show on your TV, in the Nino TV app.")
            }
        }
        .sheet(isPresented: $showGuide) {
            CaptureCardSetupView(inSheet: true)
                .frame(width: 720, height: 700)
                .appSurface()
                .environmentObject(model)
        }
    }

    @ViewBuilder private var outputPicker: some View {
            Text("Show subtitles on").font(.csCaption).foregroundStyle(Color.csSecondary)
            // Segmentli seçici bölmeleri en uzun etiket kadar eşit çizer (~3 × 127 pt) ve daralmaz; ana ekranın 380 pt'lik
            // sütununa sığmayınca kart sütundan taşıyordu. Sığmazsa aynı seçenekler yan yana radyo düğmeleriyle gösterilir.
            NinoSegmented(selection: $model.settings.output, options: [
                (.tv, "TV", "tv"),
                (.computer, String(localized: "Computer"), "desktopcomputer"),
                (.both, String(localized: "Both"), "rectangle.on.rectangle"),
            ])
            if model.showsOnComputer {
                if detailed {
                    HintText(text: "Subtitles appear in a window on this computer, over the game or PS Remote Play.")
                }
                ComputerScreenOptions()
                if detailed || model.settings.overlayClickThrough {
                    HintText(text: "When on, clicks go through to the window below. Press ⌥⌘L or use the menu bar to turn it off.")
                }
            }
    }

    private var _unusedOutputPicker: some View {
        Picker("Show subtitles on", selection: $model.settings.output) {
            Text(verbatim: "TV").tag(SubtitleOutput.tv)
            Text("Computer screen").tag(SubtitleOutput.computer)
            Text("Both").tag(SubtitleOutput.both)
        }
        .labelsHidden()
    }
}

/// Bilgisayar ekranındaki altyazı penceresi: tıklamalar geçsin, pencereyi ayarla.
private struct ComputerScreenOptions: View {
    @EnvironmentObject private var model: AppModel

    var body: some View {
        ViewThatFits(in: .horizontal) {
            HStack(spacing: Theme.space("m")) {
                Toggle("Clicks pass through", isOn: $model.settings.overlayClickThrough)
                Spacer()
                adjust
            }
            VStack(alignment: .leading, spacing: Theme.space("s")) {
                Toggle("Clicks pass through", isOn: $model.settings.overlayClickThrough)
                adjust
            }
        }
    }

    private var adjust: some View {
        Button("Adjust the subtitle window") { model.overlayAdjusting = true }
            .buttonStyle(.secondary)
            .disabled(model.overlayAdjusting)
    }
}
