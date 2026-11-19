// SPDX-License-Identifier: AGPL-3.0-only
// Nino: "Nino'ya Sor" (kurulum yardımcısı). Sağ altta yüzen robot düğmesi (ana ekranda, karşılamada ve kurulum
// adımlarında) ve Ayarlar/Profil'deki satır sohbet sayfasını alttan açar. Sohbet Nino'nun sunucusuna gider
// (CouchSubsCore/AssistantChat.swift); uygulama açık kaldıkça bellekte durur.

import CouchSubsCore
import PhotosUI
import SwiftUI

/// Sohbet, sayfa kapatılıp açılınca kaybolmasın diye uygulama açık kaldıkça tutulur.
@MainActor
enum AskNinoChat {
    static let shared = AssistantChatSession()
}

/// Sağ altta yüzen yuvarlak robot düğmesi.
struct AskNinoButton: View {
    @Environment(\.locale) private var locale
    @EnvironmentObject private var model: PhoneModel
    @State private var showing = false
    /// Nino: çeviri başlayınca robotun solunda 7 sn "Altyazı Çevirisi Başladı" balonu.
    @State private var startedBubble = false
    @State private var bubbleTask: Task<Void, Never>?

    static let startedTexts: [String: String] = [
        "ar": "نينو: بدأت ترجمة الحوارات. استمتع باللعب!",
        "bn": "নিনো: সাবটাইটেল অনুবাদ শুরু হয়েছে। খেলা উপভোগ করুন!",
        "fil": "Nino: Nagsimula na ang Pagsasalin ng Subtitle. Mag-enjoy sa Laro!",
        "hi": "नीनो: सबटाइटल अनुवाद शुरू हो गया। खेल का मज़ा लें!",
        "id": "Nino: Terjemahan Subtitle Dimulai. Selamat Bermain!",
        "ms": "Nino: Terjemahan Sari Kata Bermula. Selamat Bermain!",
        "nl": "Nino: Ondertitelvertaling Gestart. Veel Speelplezier!",
        "th": "Nino: เริ่มแปลคำบรรยายแล้ว ขอให้สนุกกับเกม!",
        "tr": "Nino: Altyazı Çevirisi Başladı. Keyifli Oyunlar!",
        "ur": "نینو: سب ٹائٹل کا ترجمہ شروع ہو گیا۔ کھیل کا لطف اٹھائیں!",
        "vi": "Nino: Đã Bắt Đầu Dịch Phụ Đề. Chúc Chơi Vui!"
    ]

    private var startedText: String {
        Self.startedTexts[locale.language.languageCode?.identifier ?? "en"] ?? "Nino: Subtitle Translation Started. Enjoy the Game!"
    }

    var body: some View {
        HStack(spacing: 10) {
            if startedBubble {
                Text(startedText)
                    .font(.system(size: 15, weight: .bold))
                    .foregroundStyle(.white)
                    .multilineTextAlignment(.leading)
                    .padding(.horizontal, 16).padding(.vertical, 11)
                    .background(Capsule().fill(Color.black.opacity(0.7)))
                    .transition(.move(edge: .trailing).combined(with: .opacity))
            }
            robot
        }
        .onChange(of: model.isRunning) { running in
            bubbleTask?.cancel()
            guard running else { withAnimation(.easeOut(duration: 0.25)) { startedBubble = false }; return }
            withAnimation(.spring(response: 0.4, dampingFraction: 0.8)) { startedBubble = true }
            bubbleTask = Task {
                try? await Task.sleep(nanoseconds: 7_000_000_000)
                guard !Task.isCancelled else { return }
                withAnimation(.easeOut(duration: 0.4)) { startedBubble = false }
            }
        }
    }

    private var robot: some View {
        Button { showing = true } label: {
            NinoBotFace(size: 46, bobbing: true)
                .frame(width: 62, height: 62)
                .background(Circle().fill(Color.white.opacity(0.95)))
                .overlay(Circle().strokeBorder(Mobile.Palette.border))
                .shadow(color: Mobile.Palette.pro.opacity(0.22), radius: 14, y: 6)
                .contentShape(Circle())
        }
        .buttonStyle(AskNinoPressStyle())
        .accessibilityLabel(Text(AskNino.text("Ask Nino", locale)))
        .sheet(isPresented: $showing) { AskNinoSheet() }
    }
}

private struct AskNinoPressStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? 0.92 : 1)
            .animation(.spring(response: 0.25, dampingFraction: 0.7), value: configuration.isPressed)
    }
}

/// Ayarlar listelerindeki "Nino'ya Sor" satırı; sohbeti alttan açar.
struct AskNinoRow: View {
    @Environment(\.locale) private var locale
    @State private var showing = false

    var body: some View {
        Button { showing = true } label: {
            ListRow(symbol: "bubble.left.and.text.bubble.right", title: LocalizedStringKey(AskNino.text("Ask Nino", locale)))
        }
        .buttonStyle(.plain)
        .sheet(isPresented: $showing) { AskNinoSheet() }
    }
}

struct AskNinoSheet: View {
    @EnvironmentObject private var model: PhoneModel
    @Environment(\.dismiss) private var dismiss
    @Environment(\.locale) private var locale
    @ObservedObject private var chat = AskNinoChat.shared
    @State private var picked: [PhotosPickerItem] = []
    @State private var reporting = false
    @FocusState private var focused: Bool

    private func t(_ key: String) -> String { AskNino.text(key, locale) }

    var body: some View {
        VStack(spacing: 0) {
            header
            messages
            composer
        }
        .foregroundStyle(Mobile.Palette.text)
        .background(MobileBackground())
        .onChange(of: picked) { load($0) }
        .sheet(isPresented: $reporting) { ReportProblemSheet().environmentObject(model) }
        .sheetBackground(Mobile.Palette.bg)
    }

    // MARK: Başlık

    private var header: some View {
        HStack(spacing: Mobile.Space.gap) {
            NinoBotFace(size: 42, thinking: chat.isWaiting)
                .frame(width: 50, height: 50)
                .background(Circle().fill(Color.white.opacity(0.95)))
                .overlay(Circle().strokeBorder(Mobile.Palette.border))
            VStack(alignment: .leading, spacing: 1) {
                Text(verbatim: "Nino").font(.headline)
                Text(verbatim: t("Setup helper")).font(.subheadline).foregroundStyle(Mobile.Palette.secondary)
            }
            Spacer()
            if !chat.isEmpty {
                IconButton(symbol: "square.and.pencil", label: LocalizedStringKey(t("New chat"))) { chat.reset() }
            }
            IconButton(symbol: "xmark", label: "Close") { dismiss() }
        }
        .padding(.horizontal, Mobile.Space.screen)
        .padding(.top, Mobile.Space.screen)
        .padding(.bottom, Mobile.Space.inline)
    }

    // MARK: Mesajlar

    private var messages: some View {
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(alignment: .leading, spacing: Mobile.Space.gap) {
                    NinoBubble { Text(verbatim: t(AskNino.greeting)) }
                    if chat.isEmpty {
                        ChipFlow(spacing: 8) {
                            ForEach(AskNino.suggestions.map(t), id: \.self) { item in
                                Button { send(item) } label: {
                                    Text(verbatim: item)
                                        .font(.subheadline.weight(.medium))
                                        .foregroundStyle(Mobile.Palette.accent)
                                        .padding(.horizontal, 14).padding(.vertical, 9)
                                        .background(Capsule().fill(Color.white.opacity(0.9)))
                                        .overlay(Capsule().strokeBorder(Mobile.Palette.accent.opacity(0.3)))
                                }
                                .buttonStyle(.plain)
                            }
                        }
                        .padding(.leading, 36)
                    }
                    ForEach(chat.entries) { entry in
                        row(entry).id(entry.id)
                    }
                    if chat.isWaiting {
                        NinoBubble(thinking: true) { NinoTypingDots(color: Mobile.Palette.secondary) }
                            .accessibilityElement()
                            .accessibilityLabel(Text(verbatim: t("Nino is typing…")))
                    }
                    Color.clear.frame(height: 1).id("bottom")
                }
                .padding(.horizontal, Mobile.Space.screen)
                .padding(.vertical, Mobile.Space.gap)
            }
            .scrollDismissesKeyboard(.interactively)
            .onChange(of: chat.entries.count) { _ in scrollDown(proxy) }
            .onChange(of: chat.isWaiting) { _ in scrollDown(proxy) }
            .onChange(of: focused) { _ in scrollDown(proxy) }
            .onAppear { proxy.scrollTo("bottom", anchor: .bottom) }
        }
    }

    private func scrollDown(_ proxy: ScrollViewProxy) {
        withAnimation(.easeOut(duration: 0.25)) { proxy.scrollTo("bottom", anchor: .bottom) }
    }

    @ViewBuilder private func row(_ entry: AssistantChatSession.Entry) -> some View {
        if entry.role == .user {
            VStack(alignment: .trailing, spacing: 4) {
                UserBubble(entry: entry)
                if case .failed(let failure) = entry.state, failure.isRetryable, chat.failedEntry == entry.id {
                    HStack(spacing: Mobile.Space.inline) {
                        Label(t("Not sent"), systemImage: "exclamationmark.circle.fill")
                            .font(.caption).foregroundStyle(Mobile.Palette.danger)
                        Button(t("Try again")) { chat.retry(context: context) }
                            .font(.caption.weight(.semibold))
                            .disabled(chat.isWaiting)
                    }
                }
            }
            .frame(maxWidth: .infinity, alignment: .trailing)
        } else if let notice = entry.notice {
            NinoBubble {
                VStack(alignment: .leading, spacing: Mobile.Space.inline) {
                    Text(verbatim: t(AskNino.notice(notice)))
                    if notice == .disabled || notice == .rateLimited {
                        Button { reporting = true } label: {
                            Label("Report a Problem", systemImage: "exclamationmark.bubble")
                                .font(.subheadline.weight(.semibold))
                                .foregroundStyle(Mobile.Palette.onAccent)
                                .padding(.horizontal, 14).padding(.vertical, 9)
                                .background(Capsule().fill(Mobile.Palette.accent))
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
        } else {
            VStack(alignment: .leading, spacing: 4) {
                NinoBubble { NinoMessageText(text: entry.text) }
                if entry.report != nil {
                    Label(t("Report sent"), systemImage: "checkmark.circle.fill")
                        .font(.caption.weight(.semibold)).foregroundStyle(Mobile.Palette.success)
                        .padding(.horizontal, 10).padding(.vertical, 4)
                        .background(Capsule().fill(Mobile.Palette.success.opacity(0.12)))
                        .padding(.leading, 36)
                }
            }
        }
    }

    // MARK: Yazma alanı

    private var composer: some View {
        VStack(alignment: .leading, spacing: Mobile.Space.inline) {
            if !chat.attachments.isEmpty || chat.isPreparing {
                HStack(spacing: Mobile.Space.inline) {
                    ForEach(chat.attachments) { attachment in
                        AttachmentThumb(jpeg: attachment.jpeg) { chat.remove(attachment) }
                    }
                    if chat.isPreparing { ProgressView() }
                }
            }
            if chat.unreadableImage { MobileNote(text: String(localized: "This file could not be read as a photo.")) }
            HStack(alignment: .bottom, spacing: Mobile.Space.inline) {
                PhotosPicker(selection: $picked, maxSelectionCount: max(1, chat.remainingImages), matching: .images) {
                    Image(systemName: "photo.badge.plus")
                        .font(.system(size: 19, weight: .medium))
                        .foregroundStyle(chat.canAddImage ? Mobile.Palette.accent : Mobile.Palette.tertiary)
                        .frame(width: 40, height: 40)
                }
                .disabled(!chat.canAddImage)
                .accessibilityLabel(Text(verbatim: t("Add a screenshot")))

                TextField(t("Ask Nino…"), text: $chat.draft, axis: .vertical)
                    .font(.body)
                    .lineLimit(1 ... 5)
                    .focused($focused)
                    .padding(.horizontal, 14)
                    .padding(.vertical, 9)
                    .frame(minHeight: 40)
                    .background(Color.white.opacity(0.95), in: RoundedRectangle(cornerRadius: 20, style: .continuous))
                    .overlay(RoundedRectangle(cornerRadius: 20, style: .continuous).strokeBorder(Mobile.Palette.borderStrong))

                Button { send(nil) } label: {
                    Image(systemName: "arrow.up")
                        .font(.system(size: 17, weight: .bold))
                        .foregroundStyle(.white)
                        .frame(width: 40, height: 40)
                        .background(Circle().fill(chat.canSend ? Mobile.Palette.accent : Mobile.Palette.tertiary.opacity(0.5)))
                }
                .buttonStyle(.plain)
                .disabled(!chat.canSend)
                .accessibilityLabel(Text("Send"))
            }
        }
        .padding(.horizontal, Mobile.Space.screen)
        .padding(.top, Mobile.Space.inline)
        .padding(.bottom, Mobile.Space.gap)
        .background(Mobile.Palette.bg.opacity(0.9).ignoresSafeArea(edges: .bottom))
    }

    // MARK: İşlemler

    private var context: @Sendable () async -> AssistantChatSession.Context {
        let model = model
        let language = UILanguage.code(for: model.settings.targetLanguage)
        return {
            AssistantChatSession.Context(install: await model.reportInstallID(), app: AppIdentity.version,
                                         platform: "ios", language: language,
                                         // Her mesajda yeniden okunur: TV ya da konsol sonradan bağlanmış olabilir.
                                         device: await model.deviceInfoSummary)
        }
    }

    private func send(_ text: String?) {
        guard text != nil || chat.canSend else { return }
        chat.submit(text, context: context)
    }

    private func load(_ items: [PhotosPickerItem]) {
        guard !items.isEmpty else { return }
        picked = []
        Task {
            var data: [Data] = []
            for item in items {
                if let value = try? await item.loadTransferable(type: Data.self) { data.append(value) }
            }
            await chat.addImages(data)
        }
    }
}

/// Robotun balonu: solda küçük robot, açık yüzey.
private struct NinoBubble<Content: View>: View {
    var thinking = false
    @ViewBuilder var content: Content

    var body: some View {
        HStack(alignment: .bottom, spacing: Mobile.Space.inline) {
            NinoBotFace(size: 28, animated: thinking, thinking: thinking)
            content
                .font(.body)
                .foregroundStyle(Mobile.Palette.text)
                .padding(.horizontal, 14).padding(.vertical, 10)
                .background(Color.white.opacity(0.92), in: RoundedRectangle(cornerRadius: 18, style: .continuous))
                .overlay(RoundedRectangle(cornerRadius: 18, style: .continuous).strokeBorder(Mobile.Palette.border))
            Spacer(minLength: 32)
        }
    }
}

/// Kullanıcının balonu: sağda, vurgu mavisi, beyaz yazı; fotoğraflar küçük resim.
private struct UserBubble: View {
    let entry: AssistantChatSession.Entry

    /// Yalnız yeniden denenebilen (ağ, sunucu) mesaj soluk görünür; "henüz hazır değilim" gibi durumlarda değil.
    static func dimmed(_ state: AssistantChatSession.Entry.State) -> Bool {
        if case .failed(let failure) = state { return failure.isRetryable }
        return false
    }

    var body: some View {
        HStack {
            Spacer(minLength: 56)
            VStack(alignment: .trailing, spacing: 6) {
                if !entry.images.isEmpty {
                    HStack(spacing: 6) {
                        ForEach(entry.images.indices, id: \.self) { i in
                            if let image = UIImage(data: entry.images[i]) {
                                Image(uiImage: image).resizable().scaledToFill()
                                    .frame(width: 76, height: 76)
                                    .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
                            }
                        }
                    }
                }
                if !entry.text.isEmpty {
                    Text(verbatim: entry.text)
                        .font(.body)
                        .foregroundStyle(.white)
                        .textSelection(.enabled)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            .padding(.horizontal, 14).padding(.vertical, 10)
            .background(Mobile.Palette.accent, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
            .opacity(Self.dimmed(entry.state) ? 0.6 : 1)
        }
    }
}

/// Eklenen fotoğrafın küçük resmi; sağ üstte kaldırma düğmesi.
private struct AttachmentThumb: View {
    let jpeg: Data
    let remove: () -> Void

    var body: some View {
        ZStack(alignment: .topTrailing) {
            Group {
                if let image = UIImage(data: jpeg) { Image(uiImage: image).resizable().scaledToFill() } else { Mobile.Palette.surface2 }
            }
            .frame(width: 60, height: 60)
            .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
            Button(action: remove) {
                Image(systemName: "xmark.circle.fill")
                    .font(.system(size: 18))
                    .symbolRenderingMode(.palette)
                    .foregroundStyle(.white, Color.black.opacity(0.6))
            }
            .padding(2)
            .accessibilityLabel(Text("Remove photo"))
        }
    }
}
