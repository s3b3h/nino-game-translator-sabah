// SPDX-License-Identifier: AGPL-3.0-only
// Nino: Sorun Bildir (Ayarlar → Sorun Bildir). Açıklama, en çok 3 ekran görüntüsü (dosya seçici ya da sürükle bırak),
// isteğe bağlı iletişim bilgisi ve uygulama günlüğü Nino'nun sunucusuna gider (CouchSubsCore/ProblemReport.swift).

import AppKit
import CouchSubsCore
import RemotePlay
import SwiftUI
import UniformTypeIdentifiers

/// Taslak ayarlar kapatılıp açılınca kaybolmasın diye uygulama açık kaldıkça tutulur.
@MainActor
enum ReportDraft {
    static let shared = ProblemReportForm()
}

struct ReportProblemCard: View {
    /// Gönderildikten sonra ayarlar listesine döner.
    var close: () -> Void = {}
    @EnvironmentObject private var model: AppModel
    @ObservedObject private var form = ReportDraft.shared
    @State private var choosing = false
    @State private var dropTargeted = false

    var body: some View {
        VStack(alignment: .leading, spacing: Theme.space("gap")) {
            if form.phase == .sent {
                sent
            } else {
                Card {
                    Text("What happened?").font(.csHeadline)
                    description
                }
                Card {
                    HStack {
                        Text("Photos or screenshots").font(.csHeadline)
                        Spacer()
                        Text(verbatim: "\(form.attachments.count)/\(ProblemReport.maxImages)")
                            .font(.csCallout).foregroundStyle(Color.csSecondary)
                    }
                    photos
                    if form.unreadableImage {
                        ErrorText(error: String(localized: "This file could not be read as a photo."))
                    }
                }
                Card {
                    Text("How can we reach you? (optional)").font(.csHeadline)
                    TextField("E-mail, Instagram or X", text: $form.contact)
                        .textFieldStyle(CSTextFieldStyle())
                        .disabled(form.isBusy)
                    Divider()
                    HStack(spacing: Theme.space("m")) {
                        VStack(alignment: .leading, spacing: 2) {
                            Text("Include app log").font(.csHeadline)
                            HintText(text: "Helps us find the problem. No passwords or keys are included.")
                        }
                        Spacer(minLength: Theme.space("m"))
                        Toggle("Include app log", isOn: $form.includeLog)
                            .labelsHidden().toggleStyle(.switch).tint(Color.csAccent)
                            .disabled(form.isBusy)
                    }
                }
                if case .failed(let failure) = form.phase {
                    ErrorText(error: Self.message(for: failure))
                }
                HStack(spacing: Theme.space("m")) {
                    if form.phase == .sending {
                        ProgressView().controlSize(.small)
                        Text("Sending…").font(.csCallout).foregroundStyle(Color.csSecondary)
                    }
                    Spacer()
                    Button("Send") { send() }
                        .buttonStyle(CSButtonStyle(kind: .primary))
                        .disabled(!form.canSend)
                }
                Text("Your description, photos and (if on) the app log are sent to Nino's server so we can fix the problem. Don't include passwords.")
                    .font(.csCaption).foregroundStyle(Color.csSecondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .fileImporter(isPresented: $choosing, allowedContentTypes: [.image], allowsMultipleSelection: true) { result in
            guard case .success(let urls) = result else { return }
            add(urls: urls)
        }
        .onChange(of: form.text) { _ in form.clearError() }
    }

    private var description: some View {
        ZStack(alignment: .topLeading) {
            TextEditor(text: $form.text)
                .font(.csBody)
                .scrollContentBackground(.hidden)
                .padding(Theme.space("s"))
                .frame(minHeight: 140)
                .disabled(form.isBusy)
            if form.text.isEmpty {
                Text("What happened? Which game, what did you expect?")
                    .font(.csBody).foregroundStyle(Color.csSecondary)
                    .padding(.horizontal, Theme.space("s") + 5).padding(.vertical, Theme.space("s"))
                    .allowsHitTesting(false)
            }
        }
        .ninoGlass(in: RoundedRectangle(cornerRadius: Theme.radius("control"), style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: Theme.radius("control"), style: .continuous).strokeBorder(Color.ninoGlassEdge))
    }

    private var photos: some View {
        HStack(spacing: Theme.space("m")) {
            ForEach(form.attachments) { attachment in
                Thumbnail(attachment: attachment) { form.remove(attachment) }
            }
            if form.canAddImage {
                Button { choosing = true } label: {
                    VStack(spacing: 6) {
                        Image(systemName: form.phase == .preparing ? "hourglass" : "photo.badge.plus").font(.system(size: 22))
                        Text("Add or drop").font(.csCaption)
                    }
                    .foregroundStyle(dropTargeted ? Color.csAccentText : Color.csSecondary)
                    .frame(width: 112, height: 84)
                    .background(RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .strokeBorder(dropTargeted ? Color.csAccent : Color.ninoGlassEdge,
                                      style: StrokeStyle(lineWidth: dropTargeted ? 2 : 1, dash: [5, 4])))
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .disabled(form.isBusy)
            }
            Spacer(minLength: 0)
        }
        .onDrop(of: [.fileURL, .image], isTargeted: $dropTargeted) { providers in
            drop(providers)
        }
    }

    private var sent: some View {
        Card {
            HStack(spacing: Theme.space("m")) {
                Image(systemName: "checkmark.circle.fill").font(.system(size: 30)).foregroundStyle(Color.csSuccess)
                Text("Thanks! We received your report.").font(.csHeadline)
            }
        }
        .task {
            try? await Task.sleep(nanoseconds: 1_600_000_000)
            form.reset()
            close()
        }
    }

    // MARK: İşlemler

    private func add(urls: [URL]) {
        let urls = Array(urls.prefix(form.remainingImages))
        Task {
            let items = await Task.detached(priority: .userInitiated) {
                urls.compactMap { url -> Data? in
                    let access = url.startAccessingSecurityScopedResource()
                    defer { if access { url.stopAccessingSecurityScopedResource() } }
                    // Çok büyük dosya (ör. yanlışlıkla seçilen video) belleğe alınmaz.
                    let size = (try? url.resourceValues(forKeys: [.fileSizeKey]).fileSize) ?? 0
                    guard size <= 60_000_000 else { return Data() }
                    return try? Data(contentsOf: url)
                }
            }.value
            await form.addImages(items)
        }
    }

    private func drop(_ providers: [NSItemProvider]) -> Bool {
        guard form.canAddImage else { return false }
        let providers = Array(providers.prefix(form.remainingImages))
        Task {
            var items: [Data] = []
            for provider in providers {
                if let data = await Self.load(provider) { items.append(data) }
            }
            await form.addImages(items)
        }
        return true
    }

    /// Sürüklenen öğe: Finder'dan dosya ya da başka uygulamadan resim verisi.
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

    private func send() {
        let language = model.settings.targetLanguage
        let header = "Nino \(AppIdentity.version), macOS \(ProcessInfo.processInfo.operatingSystemVersionString)"
        Task {
            SubtitleLog.flush()
            RemotePlayLog.flush()
            let install = await model.reportInstallID()
            let logs = SubtitleLog.defaultFile.deletingLastPathComponent()
            await form.submit(install: install, app: AppIdentity.version, platform: "mac", language: language,
                              logFiles: ["remoteplay.log", "altyazi.log", "tvinstall.log"].map { logs.appendingPathComponent($0) },
                              logHeader: header)
        }
    }

    static func message(for failure: ProblemReport.Failure) -> String {
        switch failure {
        case .rateLimited: String(localized: "You've sent many reports today. Please try again tomorrow.")
        case .offline, .noEndpoint: String(localized: "The report could not be sent. Check your internet connection and try again.")
        case .tooLarge: String(localized: "The report is too large. Remove a photo and try again.")
        case .rejected, .server: String(localized: "The report could not be sent. Please try again later.")
        }
    }
}

/// Küçük resim; sağ üstte kaldırma düğmesi.
private struct Thumbnail: View {
    let attachment: ProblemReportForm.Attachment
    let remove: () -> Void

    var body: some View {
        ZStack(alignment: .topTrailing) {
            Group {
                if let image = NSImage(data: attachment.jpeg) {
                    Image(nsImage: image).resizable().scaledToFill()
                } else {
                    Color.csAccentSoft
                }
            }
            .frame(width: 112, height: 84)
            .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous).strokeBorder(Color.ninoGlassEdge))
            Button(action: remove) {
                Image(systemName: "xmark.circle.fill")
                    .font(.system(size: 18))
                    .symbolRenderingMode(.palette)
                    .foregroundStyle(.white, Color.black.opacity(0.6))
            }
            .buttonStyle(.plain)
            .padding(4)
            .accessibilityLabel(Text("Remove photo"))
        }
    }
}
