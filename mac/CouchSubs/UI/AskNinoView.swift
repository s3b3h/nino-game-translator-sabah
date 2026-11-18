// SPDX-License-Identifier: AGPL-3.0-only
// Nino: "Nino'ya Sor" (kurulum yardımcısı). Sağ altta yüzen robot düğmesi (ana ekranda ve kurulumda) ve Ayarlar'daki
// satır sohbet sayfasını açar. Sohbet Nino'nun sunucusuna gider (CouchSubsCore/AssistantChat.swift); uygulama açık
// kaldıkça bellekte durur.

import AppKit
import CouchSubsCore
import SwiftUI
import UniformTypeIdentifiers

/// Sohbet, sayfa kapatılıp açılınca kaybolmasın diye uygulama açık kaldıkça tutulur.
@MainActor
enum AskNinoChat {
    static let shared = AssistantChatSession()
}

/// Sağ altta yüzen yuvarlak robot düğmesi.
struct AskNinoButton: View {
    @EnvironmentObject private var model: AppModel
    @Environment(\.locale) private var locale
    @State private var hovering = false
    /// Nino: çeviri başlayınca robotun yanında 7 sn "Altyazı Çevirisi Başladı" balonu.
    @State private var startedBubble = false
    @State private var bubbleTask: Task<Void, Never>?

    var body: some View {
        HStack(spacing: 12) {
            robot
            if startedBubble {
                Text(AskNino.text("Nino: Subtitle Translation Started. Enjoy the Game!", locale))
                    .font(.system(size: 17, weight: .bold))
                    .foregroundStyle(.white)
                    .padding(.horizontal, 20).padding(.vertical, 13)
                    .background(Capsule().fill(Color.black.opacity(0.55)))
                    .overlay(Capsule().strokeBorder(Color.white.opacity(0.14)))
                    .fixedSize()
                    .transition(.move(edge: .leading).combined(with: .opacity))
                    .accessibilityAddTraits(.updatesFrequently)
            }
        }
        .onChange(of: model.isRunning) { running in
            bubbleTask?.cancel()
            guard running, model.step == .done else {
                withAnimation(.easeOut(duration: 0.25)) { startedBubble = false }
                return
            }
            withAnimation(.spring(response: 0.4, dampingFraction: 0.8)) { startedBubble = true }
            bubbleTask = Task {
                try? await Task.sleep(nanoseconds: 7_000_000_000)
                guard !Task.isCancelled else { return }
                withAnimation(.easeOut(duration: 0.4)) { startedBubble = false }
            }
        }
    }

    private var robot: some View {
        Button { model.showAssistant = true } label: {
            NinoBotFace(size: 44, bobbing: true)
                .frame(width: 60, height: 60)
                .background(Circle().fill(Color.white.opacity(0.92)))
                .ninoGlass(in: Circle(), interactive: true)
                .overlay(Circle().strokeBorder(Color.ninoGlassEdge))
                .shadow(color: Color.csPro.opacity(hovering ? 0.28 : 0.18), radius: hovering ? 16 : 12, y: 6)
                .scaleEffect(hovering ? 1.05 : 1)
                .contentShape(Circle())
        }
        .buttonStyle(.plain)
        .onHover { h in withAnimation(.spring(response: 0.3, dampingFraction: 0.7)) { hovering = h } }
        .help(AskNino.text("Ask Nino", locale))
        .accessibilityLabel(Text(AskNino.text("Ask Nino", locale)))
    }
}

/// Sohbet sayfası. "Sorun Bildir"e geçilince aynı sayfada form açılır (kurulumda Ayarlar yok).
struct AskNinoSheet: View {
    @EnvironmentObject private var model: AppModel
    @Environment(\.dismiss) private var dismiss
    @Environment(\.locale) private var locale
    @ObservedObject private var chat = AskNinoChat.shared
    @State private var reporting = false
    @State private var choosing = false
    @State private var dropTargeted = false
    @FocusState private var composerFocused: Bool

    private func t(_ key: String) -> String { AskNino.text(key, locale) }

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider().opacity(0.5)
            if reporting {
                ScrollView {
                    ReportProblemCard(close: { reporting = false })
                        .padding(Theme.space("l"))
                }
                .scrollIndicators(.never)
            } else {
                messages
                composer
            }
        }
        .frame(width: 540, height: 660)
        .fileImporter(isPresented: $choosing, allowedContentTypes: [.image], allowsMultipleSelection: true) { result in
            guard case .success(let urls) = result else { return }
            add(urls: urls)
        }
        .onDrop(of: [.fileURL, .image], isTargeted: $dropTargeted) { drop($0) }
        .onAppear {
            composerFocused = true
            startPasteMonitor()
        }
        .onDisappear { stopPasteMonitor() }
    }

    /// ⌘V: panoda resim ya da resim dosyası varsa ek olarak alınır (yazı alanı yapıştırmayı kendisi yuttuğu için
    /// tuş burada yakalanır); düz yazı yapıştırma olduğu gibi yazı alanına gider.
    @State private var pasteMonitor: Any?

    private func startPasteMonitor() {
        guard pasteMonitor == nil else { return }
        pasteMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { event in
            guard event.modifierFlags.intersection(.deviceIndependentFlagsMask) == .command,
                  event.charactersIgnoringModifiers?.lowercased() == "v", !reporting else { return event }
            let board = NSPasteboard.general
            let fileURLs = (board.readObjects(forClasses: [NSURL.self], options: [.urlReadingFileURLsOnly: true]) as? [URL] ?? [])
                .filter { UTType(filenameExtension: $0.pathExtension)?.conforms(to: .image) == true }
            if !fileURLs.isEmpty {
                if chat.canAddImage { add(urls: fileURLs) }
                return nil
            }
            // Ekran görüntüsü (⌘⇧⌃4) ya da başka uygulamadan kopyalanan resim; yazı da varsa yazı yapıştırılır.
            if board.string(forType: .string) == nil, let data = board.data(forType: .png) ?? board.data(forType: .tiff) {
                if chat.canAddImage { Task { await chat.addImages([data]) } }
                return nil
            }
            return event
        }
    }

    private func stopPasteMonitor() {
        if let pasteMonitor { NSEvent.removeMonitor(pasteMonitor) }
        pasteMonitor = nil
    }

    // MARK: Başlık

    private var header: some View {
        HStack(spacing: Theme.space("m")) {
            if reporting {
                Button { reporting = false } label: { Image(systemName: "chevron.backward").font(.system(size: 15, weight: .semibold)) }
                    .buttonStyle(.plain).foregroundStyle(Color.csAccentText)
                    .accessibilityLabel(Text("Back"))
            }
            NinoBotFace(size: 40, thinking: chat.isWaiting)
                .frame(width: 46, height: 46)
                .background(Circle().fill(Color.white.opacity(0.9)))
                .overlay(Circle().strokeBorder(Color.ninoGlassEdge))
            VStack(alignment: .leading, spacing: 1) {
                Text(verbatim: "Nino").font(.csHeadline)
                Group { if reporting { Text("Report a Problem") } else { Text(verbatim: t("Setup helper")) } }
                    .font(.csCaption).foregroundStyle(Color.csSecondary)
            }
            Spacer()
            if !reporting && !chat.isEmpty {
                Button { chat.reset() } label: { Label(t("New chat"), systemImage: "square.and.pencil") }
                    .buttonStyle(CSButtonStyle(kind: .ghost))
            }
            Button("Close") { dismiss() }
                .buttonStyle(CSButtonStyle(kind: .secondary))
                .keyboardShortcut(.cancelAction)
        }
        .padding(.horizontal, Theme.space("l"))
        .padding(.vertical, Theme.space("m"))
    }

    // MARK: Mesajlar

    private var messages: some View {
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(alignment: .leading, spacing: Theme.space("m")) {
                    NinoBubble { Text(t(AskNino.greeting)) }
                    if chat.isEmpty {
                        suggestions
                    }
                    ForEach(chat.entries) { entry in
                        row(entry).id(entry.id)
                    }
                    if chat.isWaiting {
                        NinoBubble(thinking: true) { NinoTypingDots(color: .csSecondary) }
                            .accessibilityLabel(Text(t("Nino is typing…")))
                            .id("typing")
                    }
                    Color.clear.frame(height: 1).id("bottom")
                }
                .padding(Theme.space("l"))
            }
            .scrollIndicators(.automatic)
            .overlay {
                if dropTargeted {
                    RoundedRectangle(cornerRadius: Theme.radius("card"), style: .continuous)
                        .strokeBorder(Color.csAccent, style: StrokeStyle(lineWidth: 2, dash: [6, 5]))
                        .padding(Theme.space("s"))
                        .allowsHitTesting(false)
                }
            }
            .onChange(of: chat.entries.count) { _ in scrollDown(proxy) }
            .onChange(of: chat.isWaiting) { _ in scrollDown(proxy) }
            .onAppear { proxy.scrollTo("bottom", anchor: .bottom) }
        }
    }

    private func scrollDown(_ proxy: ScrollViewProxy) {
        withAnimation(.easeOut(duration: 0.25)) { proxy.scrollTo("bottom", anchor: .bottom) }
    }

    private var suggestions: some View {
        FlowChips(items: AskNino.suggestions.map(t)) { text in send(text) }
            .padding(.leading, 34)
    }

    @ViewBuilder private func row(_ entry: AssistantChatSession.Entry) -> some View {
        if entry.role == .user {
            VStack(alignment: .trailing, spacing: 4) {
                UserBubble(entry: entry)
                if case .failed(let failure) = entry.state, failure.isRetryable, chat.failedEntry == entry.id {
                    HStack(spacing: Theme.space("s")) {
                        Label(t("Not sent"), systemImage: "exclamationmark.circle.fill")
                            .font(.csCaption).foregroundStyle(Color.csDanger)
                        Button(t("Try again")) { chat.retry(context: context) }
                            .buttonStyle(.plain).font(.csCaption.weight(.semibold)).foregroundStyle(Color.csAccentText)
                            .disabled(chat.isWaiting)
                    }
                }
            }
            .frame(maxWidth: .infinity, alignment: .trailing)
        } else if let notice = entry.notice {
            NinoBubble {
                VStack(alignment: .leading, spacing: Theme.space("s")) {
                    Text(t(AskNino.notice(notice)))
                    if notice == .disabled || notice == .rateLimited {
                        Button("Report a Problem") { reporting = true }
                            .buttonStyle(CSButtonStyle(kind: .primary))
                    }
                }
            }
        } else {
            VStack(alignment: .leading, spacing: 4) {
                NinoBubble { NinoMessageText(text: entry.text) }
                if entry.report != nil {
                    Label(t("Report sent"), systemImage: "checkmark.circle.fill")
                        .font(.csCaption.weight(.semibold)).foregroundStyle(Color.csSuccess)
                        .padding(.horizontal, 10).padding(.vertical, 4)
                        .background(Capsule().fill(Color.csSuccessSoft))
                        .padding(.leading, 34)
                }
            }
        }
    }

    // MARK: Yazma alanı

    private var composer: some View {
        VStack(alignment: .leading, spacing: Theme.space("s")) {
            if !chat.attachments.isEmpty || chat.isPreparing {
                HStack(spacing: Theme.space("s")) {
                    ForEach(chat.attachments) { attachment in
                        AttachmentThumb(jpeg: attachment.jpeg) { chat.remove(attachment) }
                    }
                    if chat.isPreparing { ProgressView().controlSize(.small) }
                }
            }
            if chat.unreadableImage {
                ErrorText(error: String(localized: "This file could not be read as a photo."))
            }
            HStack(alignment: .bottom, spacing: Theme.space("s")) {
                Button { choosing = true } label: {
                    Image(systemName: "photo.badge.plus").font(.system(size: 17, weight: .medium))
                        .frame(width: 36, height: 36)
                }
                .buttonStyle(.plain)
                .foregroundStyle(chat.canAddImage ? Color.csAccentText : Color.csSecondary)
                .disabled(!chat.canAddImage)
                .help(t("Add a screenshot"))
                .accessibilityLabel(Text(t("Add a screenshot")))

                TextField(t("Ask Nino…"), text: $chat.draft, axis: .vertical)
                    .textFieldStyle(.plain)
                    .font(.csBody)
                    .lineLimit(1 ... 6)
                    .focused($composerFocused)
                    .onSubmit { send(nil) }
                    .padding(.horizontal, Theme.space("m"))
                    .padding(.vertical, 9)
                    .frame(minHeight: 36)
                    .ninoGlass(in: RoundedRectangle(cornerRadius: 18, style: .continuous))
                    .overlay(RoundedRectangle(cornerRadius: 18, style: .continuous).strokeBorder(Color.ninoGlassEdge))

                Button { send(nil) } label: {
                    Image(systemName: "arrow.up")
                        .font(.system(size: 15, weight: .bold))
                        .foregroundStyle(.white)
                        .frame(width: 36, height: 36)
                        .background(Circle().fill(chat.canSend ? Color.csAccent : Color.csSecondary.opacity(0.35)))
                }
                .buttonStyle(.plain)
                .disabled(!chat.canSend)
                .accessibilityLabel(Text("Send"))
            }
        }
        .padding(.horizontal, Theme.space("l"))
        .padding(.vertical, Theme.space("m"))
    }

    // MARK: İşlemler

    private var context: @Sendable () async -> AssistantChatSession.Context {
        let model = model
        let language = TargetLanguage.interfaceLanguage(model.settings.targetLanguage)
        return {
            AssistantChatSession.Context(install: await model.reportInstallID(), app: AppIdentity.version,
                                         platform: "mac", language: language)
        }
    }

    private func send(_ text: String?) {
        guard text != nil || chat.canSend else { return }
        chat.submit(text, context: context)
        composerFocused = true
    }

    private func add(urls: [URL]) {
        let urls = Array(urls.prefix(chat.remainingImages))
        Task {
            let items = await Task.detached(priority: .userInitiated) {
                urls.compactMap { url -> Data? in
                    let access = url.startAccessingSecurityScopedResource()
                    defer { if access { url.stopAccessingSecurityScopedResource() } }
                    let size = (try? url.resourceValues(forKeys: [.fileSizeKey]).fileSize) ?? 0
                    guard size <= 60_000_000 else { return Data() }
                    return try? Data(contentsOf: url)
                }
            }.value
            await chat.addImages(items)
        }
    }

    private func drop(_ providers: [NSItemProvider]) -> Bool {
        guard chat.canAddImage, !reporting else { return false }
        paste(providers)
        return true
    }

    /// Yapıştırılan ya da sürüklenen öğe: Finder'dan dosya ya da başka uygulamadan resim verisi.
    private func paste(_ providers: [NSItemProvider]) {
        let providers = Array(providers.prefix(chat.remainingImages))
        guard !providers.isEmpty else { return }
        Task {
            var items: [Data] = []
            for provider in providers {
                if let data = await Self.load(provider) { items.append(data) }
            }
            await chat.addImages(items)
        }
    }

    private static func load(_ provider: NSItemProvider) async -> Data? {
        if provider.hasItemConformingToTypeIdentifier(UTType.fileURL.identifier) {
            let url: URL? = await withCheckedContinuation { done in
                _ = provider.loadObject(ofClass: URL.self) { url, _ in done.resume(returning: url) }
            }
            if let url { return try? Data(contentsOf: url) }
        }
        if provider.hasItemConformingToTypeIdentifier(UTType.image.identifier) {
            return await withCheckedContinuation { done in
                _ = provider.loadDataRepresentation(forTypeIdentifier: UTType.image.identifier) { data, _ in done.resume(returning: data) }
            }
        }
        return nil
    }
}

/// Robotun balonu: solda küçük robot, açık yüzey.
private struct NinoBubble<Content: View>: View {
    var thinking = false
    @ViewBuilder var content: Content

    var body: some View {
        HStack(alignment: .bottom, spacing: Theme.space("s")) {
            NinoBotFace(size: 26, animated: thinking, thinking: thinking)
            content
                .font(.csBody)
                .foregroundStyle(Color.csText)
                .padding(.horizontal, 14).padding(.vertical, 10)
                .ninoGlass(in: BubbleShape(mine: false))
                .overlay(BubbleShape(mine: false).strokeBorder(Color.ninoGlassEdge))
            Spacer(minLength: 48)
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
            Spacer(minLength: 72)
            VStack(alignment: .trailing, spacing: 6) {
                if !entry.images.isEmpty {
                    HStack(spacing: 6) {
                        ForEach(entry.images.indices, id: \.self) { i in
                            if let image = NSImage(data: entry.images[i]) {
                                Image(nsImage: image).resizable().scaledToFill()
                                    .frame(width: 84, height: 64)
                                    .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
                            }
                        }
                    }
                }
                if !entry.text.isEmpty {
                    Text(verbatim: entry.text)
                        .font(.csBody)
                        .foregroundStyle(.white)
                        .textSelection(.enabled)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            .padding(.horizontal, 14).padding(.vertical, 10)
            .background(BubbleShape(mine: true).fill(Color.csAccent))
            .opacity(Self.dimmed(entry.state) ? 0.6 : 1)
        }
    }
}

/// Konuşma balonu.
private struct BubbleShape: InsettableShape {
    let mine: Bool
    var inset: CGFloat = 0

    func path(in rect: CGRect) -> Path {
        RoundedRectangle(cornerRadius: 18, style: .continuous).path(in: rect.insetBy(dx: inset, dy: inset))
    }

    func inset(by amount: CGFloat) -> BubbleShape {
        var shape = self
        shape.inset += amount
        return shape
    }
}

/// Öneri düğmeleri (sığmayan alt satıra geçer).
private struct FlowChips: View {
    let items: [String]
    let tap: (String) -> Void

    var body: some View {
        ChipFlow(spacing: 8) {
            ForEach(items, id: \.self) { item in
                Button { tap(item) } label: {
                    Text(verbatim: item)
                        .font(.csCallout.weight(.medium))
                        .foregroundStyle(Color.csAccentText)
                        .padding(.horizontal, 12).padding(.vertical, 7)
                        .background(Capsule().fill(Color.csAccentSoft))
                        .overlay(Capsule().strokeBorder(Color.csAccent.opacity(0.25)))
                        .contentShape(Capsule())
                }
                .buttonStyle(.plain)
            }
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
                if let image = NSImage(data: jpeg) { Image(nsImage: image).resizable().scaledToFill() } else { Color.csAccentSoft }
            }
            .frame(width: 64, height: 48)
            .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 8, style: .continuous).strokeBorder(Color.ninoGlassEdge))
            Button(action: remove) {
                Image(systemName: "xmark.circle.fill")
                    .font(.system(size: 15))
                    .symbolRenderingMode(.palette)
                    .foregroundStyle(.white, Color.black.opacity(0.6))
            }
            .buttonStyle(.plain)
            .padding(2)
            .accessibilityLabel(Text("Remove photo"))
        }
    }
}
