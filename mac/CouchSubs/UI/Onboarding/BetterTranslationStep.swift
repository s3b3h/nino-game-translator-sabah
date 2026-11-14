// SPDX-License-Identifier: AGPL-3.0-only

import CouchSubsCore
import SwiftUI

/// İsteğe bağlı son adım: ücretsiz Gemini anahtarıyla daha doğal çeviri (Windows'taki BetterTranslationStep ile aynı).
/// "Kaydet ve dene" ayarlardaki denemeyi çalıştırır; anahtar kabul edilince Gemini seçilir. Alttaki düğme anahtar yokken
/// "Şimdilik geç", varken "Devam" olur.
struct BetterTranslationStep: View {
    @EnvironmentObject private var model: AppModel
    @Environment(\.openURL) private var openURL
    @State private var key = ""
    @State private var checking = false
    @State private var result: Result<String, AIFailure>?

    var body: some View {
        StepLayout(title: "Better translation (free)", message: FreeGemini.pitch) {
            VStack(alignment: .leading, spacing: Theme.space("l")) {
                if model.usesFreeGemini {
                    // Nino: sade başarı kartı; örnek çeviri küçük TV önizlemesinde.
                    HStack(alignment: .center, spacing: Theme.space("gap")) {
                        VStack(alignment: .leading, spacing: Theme.space("s")) {
                            HStack(spacing: Theme.space("m")) {
                                GradientIcon(symbol: "checkmark", size: 40)
                                Text("Gemini is ready").font(.system(size: 20, weight: .bold, design: .rounded))
                            }
                            Text("Subtitles will now be translated with Gemini.").font(.csBody).foregroundStyle(Color.csSecondary)
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                        // Deneme yapıldıysa Gemini'nin örnek çevirisi, yoksa akan örnek cümleler.
                        SubtitleStylePreview(style: model.settings.style, size: CGSize(width: 300, height: 169),
                                             live: { if case .success(let sample)? = result { return (sample, "") }; return nil }())
                    }
                    .tile(padding: Theme.space("l"))
                } else {
                    Card {
                        NumberedRow(number: 1, text: "Press Get a free key and sign in with your Google account.")
                        NumberedRow(number: 2, text: "Press Create API key and copy the key.")
                        NumberedRow(number: 3, text: "Paste the key here and press Save and test.")
                        Button("Get a free key") { openURL(AIProvider.gemini.keyPage) }
                            .buttonStyle(.primary)
                    }
                    HStack(spacing: Theme.space("m")) {
                        SecureField("API key", text: $key).textFieldStyle(CSTextFieldStyle())
                        Button(checking ? LocalizedStringKey("Testing…") : LocalizedStringKey("Save and test")) { save() }
                            .buttonStyle(.secondary)
                            .disabled(checking || key.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                    }
                }
                if case .failure(let failure)? = result {
                    ErrorText(error: TranslationCard.describe(OnlineKeyState(failure), engine: .gemini))
                }
                // Kısa notlar: tek satır, simgeli.
                VStack(alignment: .leading, spacing: 6) {
                    Label("Only the game's subtitles are sent to Google.", systemImage: "lock.fill")
                    Label("If the free limit is reached, Nino's free translation takes over.", systemImage: "gauge.with.dots.needle.33percent")
                    Label("You can choose DeepL, OpenAI, Claude or a local model later in Settings › Translation.", systemImage: "slider.horizontal.3")
                }
                .font(.csCaption)
                .foregroundStyle(Color.csSecondary)
            }
        }
    }

    private func save() {
        let typed = key
        checking = true
        result = nil
        Task {
            result = await model.setAIKey(typed, for: .gemini)
            if model.hasKey(.gemini) { key = "" }
            checking = false
        }
    }
}

/// Ücretsiz Gemini anahtarının anlatımı; sihirbaz ve Ayarlar › Çeviri aynı metinleri kullanır (Windows'ta da aynı).
/// Veri kullanımı (Kasım 2026): aistudio.google.com/docs/terms ücretsiz hizmetler için "Google uses the content you submit
/// to the Services and any generated responses to provide, improve, and develop" ve "human reviewers may read, annotate,
/// and process your API input and output" diyor; aistudio.google.com/docs/pricing'de "Used to improve our products"
/// ücretsiz katmanda Yes, ücretlide No. Ücretsiz katmanın dakikalık sınırı için bkz. `AIModel.requestsPerMinute`.
enum FreeGemini {
    static let pitch: LocalizedStringKey = "The free translation works without the internet but often sounds stiff. Google's Gemini translates much more naturally, and a free Google key is enough."
    static let privacy: LocalizedStringKey = "Subtitle text is sent to Google. With a free key, Google may use it to improve its products, and people at Google may read it. Only the game's subtitles are sent."
    static let limit: LocalizedStringKey = "The free key has a per-minute limit. When it is reached, that line is translated by the free translation."
}
