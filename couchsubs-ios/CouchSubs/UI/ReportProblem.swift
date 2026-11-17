// SPDX-License-Identifier: AGPL-3.0-only
// Nino: Sorun Bildir (Profil ve Ayarlar → Sorun Bildir). Açıklama, fotoğraf arşivinden en çok 3 ekran görüntüsü,
// isteğe bağlı iletişim bilgisi ve uygulama günlüğü Nino'nun sunucusuna gider (CouchSubsCore/ProblemReport.swift).

import CouchSubsCore
import PhotosUI
import RemotePlay
import SwiftUI

/// Taslak sayfa aşağı kaydırılıp kapatılınca kaybolmasın diye uygulama açık kaldıkça tutulur.
@MainActor
enum ReportDraft {
    static let shared = ProblemReportForm()
}

/// Ayarlar listelerindeki "Sorun Bildir" satırı; sayfayı alttan açar.
struct ReportProblemRow: View {
    @State private var showing = false

    var body: some View {
        Button { showing = true } label: { ListRow(symbol: "exclamationmark.bubble", title: "Report a Problem") }
            .buttonStyle(.plain)
            .sheet(isPresented: $showing) { ReportProblemSheet() }
    }
}

struct ReportProblemSheet: View {
    @EnvironmentObject private var model: PhoneModel
    @Environment(\.dismiss) private var dismiss
    @ObservedObject private var form = ReportDraft.shared
    @State private var picked: [PhotosPickerItem] = []
    @FocusState private var focused: Bool

    var body: some View {
        MobileScreen {
            HStack(spacing: Mobile.Space.gap) {
                Text("Report a Problem").font(Mobile.TypeScale.title)
                Spacer()
                IconButton(symbol: "xmark", label: "Close") { dismiss() }
            }
            .frame(height: Mobile.Control.icon)
        } content: {
            if form.phase == .sent {
                Tile {
                    HStack(spacing: Mobile.Space.gap) {
                        Image(systemName: "checkmark.circle.fill").font(.system(size: 28)).foregroundStyle(Mobile.Palette.success)
                        Text("Thanks! We received your report.").font(Mobile.TypeScale.headline)
                    }
                }
                .task {
                    try? await Task.sleep(nanoseconds: 1_600_000_000)
                    form.reset()
                    dismiss()
                }
            } else {
                Tile {
                    Text("What happened?").font(Mobile.TypeScale.headline)
                    description
                }
                Tile {
                    HStack {
                        Text("Photos or screenshots").font(Mobile.TypeScale.headline)
                        Spacer()
                        Text(verbatim: "\(form.attachments.count)/\(ProblemReport.maxImages)")
                            .font(Mobile.TypeScale.caption).foregroundStyle(Mobile.Palette.secondary)
                    }
                    photos
                    if form.unreadableImage { MobileNote(text: String(localized: "This file could not be read as a photo.")) }
                }
                Tile {
                    Text("How can we reach you? (optional)").font(Mobile.TypeScale.headline)
                    TextField("E-mail, Instagram or X", text: $form.contact)
                        .textFieldStyle(MobileFieldStyle())
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                        .keyboardType(.emailAddress)
                        .focused($focused)
                        .disabled(form.isBusy)
                    RowDivider()
                    Toggle(isOn: $form.includeLog) {
                        VStack(alignment: .leading, spacing: Mobile.Space.hair) {
                            Text("Include app log").font(Mobile.TypeScale.headline)
                            Text("Helps us find the problem. No passwords or keys are included.")
                                .font(Mobile.TypeScale.caption).foregroundStyle(Mobile.Palette.secondary)
                        }
                    }
                    .tint(Mobile.Palette.accent)
                    .disabled(form.isBusy)
                }
                if case .failed(let failure) = form.phase { MobileNote(text: Self.message(for: failure)) }
                Text("Your description, photos and (if on) the app log are sent to Nino's server so we can fix the problem. Don't include passwords.")
                    .font(Mobile.TypeScale.caption).foregroundStyle(Mobile.Palette.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        } bottom: {
            if form.phase != .sent {
                Button { send() } label: {
                    HStack(spacing: Mobile.Space.inline) {
                        if form.phase == .sending { ProgressView().tint(Mobile.Palette.onAccent) }
                        Text(form.phase == .sending ? LocalizedStringKey("Sending…") : LocalizedStringKey("Send"))
                    }
                }
                .buttonStyle(.mobilePrimary)
                .disabled(!form.canSend)
            }
        }
        .onChange(of: form.text) { _ in form.clearError() }
        .onChange(of: picked) { items in load(items) }
        .sheetBackground(Mobile.Palette.bg)
    }

    private var description: some View {
        ZStack(alignment: .topLeading) {
            TextEditor(text: $form.text)
                .font(Mobile.TypeScale.body)
                .scrollContentBackground(.hidden)
                .frame(minHeight: 130)
                .focused($focused)
                .disabled(form.isBusy)
            if form.text.isEmpty {
                Text("What happened? Which game, what did you expect?")
                    .font(Mobile.TypeScale.body).foregroundStyle(Mobile.Palette.tertiary)
                    .padding(.horizontal, 5).padding(.vertical, 8)
                    .allowsHitTesting(false)
            }
        }
        .padding(.horizontal, Mobile.Space.inline)
        .background(Mobile.Palette.surface2, in: RoundedRectangle(cornerRadius: Mobile.Radius.control))
        .overlay(RoundedRectangle(cornerRadius: Mobile.Radius.control).strokeBorder(Mobile.Palette.border))
    }

    private var photos: some View {
        HStack(spacing: Mobile.Space.gap) {
            ForEach(form.attachments) { attachment in
                Thumbnail(attachment: attachment) { form.remove(attachment) }
            }
            if form.canAddImage {
                PhotosPicker(selection: $picked, maxSelectionCount: form.remainingImages, matching: .images) {
                    VStack(spacing: Mobile.Space.hair) {
                        Image(systemName: form.phase == .preparing ? "hourglass" : "photo.badge.plus").font(.system(size: 22))
                        Text("Add").font(Mobile.TypeScale.caption)
                    }
                    .foregroundStyle(Mobile.Palette.accent)
                    .frame(width: 88, height: 88)
                    .background(RoundedRectangle(cornerRadius: Mobile.Radius.inner * 1.5, style: .continuous)
                        .strokeBorder(Mobile.Palette.borderStrong, style: StrokeStyle(lineWidth: 1, dash: [5, 4])))
                }
                .disabled(form.isBusy)
            }
            Spacer(minLength: 0)
        }
    }

    // MARK: İşlemler

    private func load(_ items: [PhotosPickerItem]) {
        guard !items.isEmpty else { return }
        picked = []
        Task {
            var data: [Data] = []
            for item in items {
                // HEIC dahil özgün veri; ImageIO küçültüp JPEG yapar.
                if let value = try? await item.loadTransferable(type: Data.self) { data.append(value) }
            }
            await form.addImages(data)
        }
    }

    private func send() {
        focused = false
        let language = model.settings.targetLanguage
        let header = "Nino iOS \(AppIdentity.version), \(UIDevice.current.systemName) \(UIDevice.current.systemVersion), \(UIDevice.current.model)"
        Task {
            RemotePlayLog.flush()
            SubtitleLog.flush()
            let install = await model.reportInstallID()
            await form.submit(install: install, app: AppIdentity.version, platform: "ios", language: language,
                              logFiles: [RemotePlayLog.defaultFile, SubtitleLog.defaultFile, InstallLog.shared.file],
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
                if let image = UIImage(data: attachment.jpeg) {
                    Image(uiImage: image).resizable().scaledToFill()
                } else {
                    Mobile.Palette.surface2
                }
            }
            .frame(width: 88, height: 88)
            .clipShape(RoundedRectangle(cornerRadius: Mobile.Radius.inner * 1.5, style: .continuous))
            Button(action: remove) {
                Image(systemName: "xmark.circle.fill")
                    .font(.system(size: 20))
                    .symbolRenderingMode(.palette)
                    .foregroundStyle(.white, Color.black.opacity(0.6))
            }
            .padding(4)
            .accessibilityLabel(Text("Remove photo"))
        }
    }
}
