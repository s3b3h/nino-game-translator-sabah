// SPDX-License-Identifier: AGPL-3.0-only

import RemotePlay
import SwiftUI

struct ConsoleStep: View {
    @EnvironmentObject private var model: AppModel
    @State private var consoles: [ConsoleInfo] = []
    @State private var selected: String?
    @State private var manualHost = ""
    @State private var pin = ""
    @State private var searching = false
    @State private var working = false
    @State private var error: String?
    /// Bu ekranda eşleşme az önce başarıyla bitti; kod değişene dek Bağlan kapalı, ileti düğmenin altında.
    @State private var paired = false
    /// Nino: eşli PS5 varken form gizlidir; "Yeniden Eşle" ile açılır.
    @State private var repairing = false
    @Environment(\.scrollOnboardingTo) private var scrollTo

    private static let pairedAnchor = "paired"

    private var host: String { selected ?? manualHost.trimmingCharacters(in: .whitespaces) }

    var body: some View {
        StepLayout(title: "Connect your PS5",
                   message: "Pair this Mac with the 8-digit code from your PS5. It only takes a minute.") {
            if let console = model.console, !repairing, !paired {
                HStack(spacing: Theme.space("m")) {
                    GradientIcon(symbol: "checkmark", size: 44)
                    VStack(alignment: .leading, spacing: 2) {
                        Text("PS5 paired").font(.csHeadline).foregroundStyle(Color.csSuccess)
                        Text(verbatim: "\(Self.displayName(of: console)) · \(console.host)").font(.csCallout).foregroundStyle(Color.csSecondary)
                    }
                    Spacer()
                    Button("Pair Again") { repairing = true }.buttonStyle(.secondary)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .tile(padding: Theme.space("l"))
            } else {
            // Tek ekran: solda PS5, kod ve Bağlan; sağda kodu PS5'ten alma rehberi.
            HStack(alignment: .top, spacing: Theme.space("gap")) {
                VStack(alignment: .leading, spacing: Theme.space("m")) {
                // PSN girişi yapılmadan eşleme olmaz: önce giriş adımına yönlendir.
                if model.accountId == nil {
                    HStack(spacing: Theme.space("m")) {
                        Image(systemName: "person.crop.circle.badge.exclamationmark").font(.system(size: 20)).foregroundStyle(Color.csWarning)
                        Text("First sign in with your second PSN account.").font(.csCallout.weight(.semibold))
                        Spacer()
                        Button("Sign in") { model.step = .psnLogin }.buttonStyle(.primary)
                    }
                    .padding(Theme.space("m"))
                    .background(RoundedRectangle(cornerRadius: Theme.radius("control"), style: .continuous).fill(Color.csWarning.opacity(0.10)))
                }
                Card {
                HStack {
                    Text(verbatim: "PS5").font(.csHeadline)
                    if searching { ProgressView().controlSize(.small) }
                    Spacer()
                    Button("Search again") { Task { await search() } }.buttonStyle(.secondary).disabled(searching)
                }
                if consoles.isEmpty && !searching {
                    HintText(text: "No PS5 found. Make sure it is on and on the same network, or enter its IP address. Nino must also be allowed in System Settings › Privacy & Security › Local Network.")
                    TextField("IP address, e.g. 192.168.1.20", text: $manualHost)
                        .textFieldStyle(CSTextFieldStyle())
                        .onSubmit { Task { await register() } }
                } else {
                    Picker("PS5", selection: $selected) {
                        ForEach(consoles, id: \.host) { Text(verbatim: "\($0.name) — \($0.host)").tag(Optional($0.host)) }
                    }
                    .labelsHidden()
                    .pickerStyle(.radioGroup)
                    .font(.csBody)
                }
                }
                VStack(alignment: .leading, spacing: Theme.space("s")) {
                    HStack {
                        Text("8-digit code").font(.csCallout).foregroundStyle(Color.csSecondary)
                        Spacer()
                        Text(verbatim: "\(pin.count)/8").font(.csCaption.monospacedDigit())
                            .foregroundStyle(pin.count == 8 ? Color.csSuccess : Color.csSecondary)
                    }
                    .frame(maxWidth: 240)
                    // Kod yazılıp Return'e basılınca bağlanılır (eskiden Return, kapalı "Devam"a gidip hiçbir şey yapmıyordu).
                    // Yeni kod yazılınca Bağlan yeniden açılır (onChange macOS 13'te farklı olduğu için bağlamada).
                    // Yalnız rakam, en çok 8 hane.
                    TextField("12345678", text: Binding(get: { pin }, set: { value in
                        pin = String(value.filter(\.isNumber).prefix(8))
                        if !pin.isEmpty { paired = false; error = nil }
                    }))
                        .textFieldStyle(CSTextFieldStyle(font: .csCode, height: 52))
                        .frame(maxWidth: 240)
                        .onSubmit { Task { await register() } }
                }
                HStack(spacing: Theme.space("m")) {
                    // Düğme çalışırken ve eşleşmeden sonra (kod değişene dek) kapalı; eksik kod ya da adres tıklanınca
                    // açıkça söylenir.
                    Button("Connect") { Task { await register() } }
                        .buttonStyle(.primary)
                        .disabled(working || paired || pin.count != 8 || model.accountId == nil)
                    if working {
                        ProgressView().controlSize(.small)
                        HintText(text: "Connecting to the PS5… This can take up to 30 seconds.")
                    }
                }
                // Eşleşme başarılı: düğmenin hemen altında yeşil ileti (üstteki ad kaydırınca görünmüyordu).
                if paired, let console = model.console {
                    DoneLabel(text: String(localized: "PS5 paired: \(Self.displayName(of: console)) (\(console.host)). Press Continue."))
                        .id(Self.pairedAnchor)
                }
                ErrorText(error: error).textSelection(.enabled)
                if error != nil {
                    // Eşleştirme olmazsa gönderilecek remoteplay.log Finder'da seçili açılır.
                    Button("Show log file") { showLogFile() }.buttonStyle(.secondary)
                }
            }
                .frame(maxWidth: .infinity, alignment: .leading)
                VStack(alignment: .leading, spacing: Theme.space("m")) {
                    Label("How to get the code on the PS5", systemImage: "questionmark.circle.fill")
                        .font(.csHeadline)
                        .foregroundStyle(error != nil ? Color.csWarning : Color.csText)
                    GuideRow(number: 1, text: "On the PS5, switch to the second user's profile (press the PS button › your profile picture › Switch User).")
                    GuideRow(number: 2, text: "Go to Settings › System › Remote Play.")
                    GuideRow(number: 3, text: "Choose Pair Device. An 8-digit code appears on the TV.")
                    GuideRow(number: 4, text: "Type the code below and press Connect. The code is valid for about 5 minutes.")
                }
                .padding(Theme.space("l"))
                .frame(width: 290, alignment: .topLeading)
                .ninoGlass(in: RoundedRectangle(cornerRadius: Theme.radius("card"), style: .continuous))
                .overlay(RoundedRectangle(cornerRadius: Theme.radius("card"), style: .continuous)
                    .strokeBorder(error != nil ? Color.csWarning : Color.ninoGlassEdge, lineWidth: error != nil ? 1.5 : 1))
            }
            }
        }
        .task { await search() }
    }

    /// PS5 adını göndermezse yine de başarı görünsün.
    private static func displayName(of console: RegisteredConsole) -> String {
        console.name.isEmpty ? "PS5" : console.name
    }

    private func showLogFile() {
        let file = RemotePlayLog.defaultFile
        if FileManager.default.fileExists(atPath: file.path) {
            NSWorkspace.shared.activateFileViewerSelecting([file])
        } else {
            let folder = file.deletingLastPathComponent()
            try? FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
            NSWorkspace.shared.open(folder)
        }
    }

    private func search() async {
        searching = true
        consoles = await model.discoverConsoles()
        if selected == nil { selected = consoles.first?.host }
        searching = false
    }

    /// Eşleşince düğmenin altında yeşil ileti çıkar (kaydırılmış olsa da görünür), kod alanı temizlenir ve ~1 sn sonra
    /// sonraki adıma geçilir. Hata davranışı aynı.
    private func register() async {
        guard !working, !paired else { return }
        working = true
        error = nil
        do {
            try await model.register(host: host, pin: pin)
            paired = true
            pin = ""
        } catch {
            self.error = error.localizedDescription
        }
        working = false
        guard paired else { return }
        // İleti çizildikten sonra kaydırılır.
        try? await Task.sleep(for: .milliseconds(50))
        scrollTo(Self.pairedAnchor)
        try? await Task.sleep(for: .seconds(1))
        // Kullanıcı bu arada Geri'ye bastıysa model ilerlemez (yalnız PS5 adımından geçer).
        model.continueAfterPairing()
    }
}

/// Rehberdeki sıkı satır: küçük mavi numara ve tek paragraf.
private struct GuideRow: View {
    let number: Int
    let text: LocalizedStringKey

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: Theme.space("s")) {
            Text(verbatim: "\(number)")
                .font(.system(size: 11, weight: .bold, design: .rounded))
                .foregroundStyle(.white)
                .frame(width: 20, height: 20)
                .background(Circle().fill(LinearGradient(colors: [Color.csAccentHi, Color(red: 0.0, green: 0.19, blue: 0.52)],
                                                         startPoint: .top, endPoint: .bottom)))
                .alignmentGuide(.firstTextBaseline) { $0[VerticalAlignment.center] + 4 }
            Text(text).font(.csCallout).fixedSize(horizontal: false, vertical: true)
        }
    }
}
