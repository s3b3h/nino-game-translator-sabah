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
    /// Nino: IP adresi alanı yalnız istenince (PS5 bulunamadığında "IP adresiyle bağlanın") açılır.
    @State private var showIP = false
    @FocusState private var codeFocused: Bool
    @Environment(\.scrollOnboardingTo) private var scrollTo

    private static let pairedAnchor = "paired"

    private var host: String { selected ?? manualHost.trimmingCharacters(in: .whitespaces) }

    var body: some View {
        StepLayout(title: "Connect your PS5",
                   message: "Enter the 8-digit code shown on your PS5 screen.") {
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
            // Nino: yukarıdan aşağı tek akış: üç adım kartı, PS5 durum satırı, 8 kutulu kod, tek büyük Bağlan düğmesi.
            // IP adresi yalnız PS5 bulunamazsa istenir.
            VStack(spacing: Theme.space("l")) {
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
                HStack(alignment: .top, spacing: Theme.space("m")) {
                    PairStepCard(number: 1, symbol: "person.2.fill", title: "Switch to the second user",
                                 detail: "PS button › profile picture › Switch User")
                    PairStepCard(number: 2, symbol: "gearshape.fill", title: "Open Pair Device",
                                 detail: "Settings › System › Remote Play › Pair Device")
                    PairStepCard(number: 3, symbol: "number", title: "Enter the code",
                                 detail: "Type the 8-digit code from the screen below. It is valid for 5 minutes.")
                }
                .overlay(RoundedRectangle(cornerRadius: Theme.radius("card"), style: .continuous)
                    .strokeBorder(Color.csWarning.opacity(error != nil ? 0.8 : 0), lineWidth: 1.5))

                consoleStatus

                CodeBoxes(pin: pin, focused: codeFocused)
                    .overlay {
                        // Kod yazılıp Return'e basılınca bağlanılır. Yalnız rakam, en çok 8 hane; yeni kod yazılınca Bağlan
                        // yeniden açılır. Alan görünmez, kutuların üstünde durur (tıklanınca odak ona geçer).
                        TextField("", text: Binding(get: { pin }, set: { value in
                            pin = String(value.filter(\.isNumber).prefix(8))
                            if !pin.isEmpty { paired = false; error = nil }
                        }))
                        .textFieldStyle(.plain)
                        .focused($codeFocused)
                        .opacity(0.02)
                        .onSubmit { Task { await register() } }
                        .accessibilityLabel(Text("8-digit code"))
                    }
                    .onTapGesture { codeFocused = true }

                // Düğme çalışırken ve eşleşmeden sonra (kod değişene dek) kapalı.
                Button { Task { await register() } } label: {
                    Text("Connect").frame(minWidth: 220)
                }
                .buttonStyle(CSButtonStyle(kind: .primary, height: "buttonLarge"))
                .disabled(working || paired || pin.count != 8 || model.accountId == nil || host.isEmpty)
                if working {
                    HStack(spacing: Theme.space("s")) {
                        ProgressView().controlSize(.small)
                        HintText(text: "Connecting to the PS5… This can take up to 30 seconds.")
                    }
                }
                // Eşleşme başarılı: düğmenin hemen altında yeşil ileti.
                if paired, let console = model.console {
                    DoneLabel(text: String(localized: "PS5 paired: \(Self.displayName(of: console)) (\(console.host)). Press Continue."))
                        .id(Self.pairedAnchor)
                }
                ErrorText(error: error).textSelection(.enabled).multilineTextAlignment(.center)
                if error != nil {
                    // Eşleştirme olmazsa gönderilecek remoteplay.log Finder'da seçili açılır.
                    Button("Show log file") { showLogFile() }.buttonStyle(.secondary)
                }
            }
            .frame(maxWidth: .infinity)
            .onAppear { codeFocused = true }
            }
        }
        .task { await search() }
    }

    /// Nino: PS5 araması tek satırlık durum: aranıyor, bulundu (birden çoksa seçim menüsü) ya da bulunamadı.
    @ViewBuilder private var consoleStatus: some View {
        HStack(spacing: Theme.space("s")) {
            if searching {
                ProgressView().controlSize(.small)
                Text("Looking for your PS5…").foregroundStyle(Color.csSecondary)
            } else if consoles.count > 1 {
                Image(systemName: "checkmark.circle.fill").foregroundStyle(Color.csSuccess)
                Picker("PS5", selection: $selected) {
                    ForEach(consoles, id: \.host) { Text(verbatim: "\($0.name) — \($0.host)").tag(Optional($0.host)) }
                }
                .labelsHidden()
                .fixedSize()
            } else if let console = consoles.first {
                Image(systemName: "checkmark.circle.fill").foregroundStyle(Color.csSuccess)
                Text("\(console.name) found")
            } else {
                Image(systemName: "exclamationmark.circle.fill").foregroundStyle(Color.csWarning)
                Text("PS5 not found")
                if showIP {
                    // IP adresi durum satırının içinde: kod kutuları ve Bağlan yerinden oynamaz.
                    TextField("IP address, e.g. 192.168.1.20", text: $manualHost)
                        .textFieldStyle(CSTextFieldStyle(height: 30))
                        .frame(width: 230)
                        .onSubmit { Task { await register() } }
                } else {
                    Button("Connect with IP address") { withAnimation { showIP = true } }
                        .buttonStyle(.plain)
                        .foregroundStyle(Color.csAccentText)
                }
            }
            if !searching {
                Text(verbatim: "·").foregroundStyle(Color.csSecondary)
                Button("Search again") { Task { await search() } }
                    .buttonStyle(.plain)
                    .foregroundStyle(Color.csAccentText)
            }
        }
        .font(.csCallout.weight(.semibold))
        .padding(.horizontal, Theme.space("l"))
        .padding(.vertical, Theme.space("s"))
        .background(Capsule().fill(Color.white.opacity(0.06)))
        .overlay(Capsule().strokeBorder(Color.ninoGlassEdge, lineWidth: 1))
        .help(consoles.isEmpty && !searching
              ? Text("No PS5 found. Make sure it is on and on the same network, or enter its IP address. Nino must also be allowed in System Settings › Privacy & Security › Local Network.")
              : Text(verbatim: ""))
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

/// Nino: eşleştirme adım kartı: numara, simge, kısa başlık ve menü yolu.
private struct PairStepCard: View {
    let number: Int
    let symbol: String
    let title: LocalizedStringKey
    let detail: LocalizedStringKey

    var body: some View {
        VStack(alignment: .leading, spacing: Theme.space("s")) {
            HStack {
                GradientIcon(symbol: symbol, size: 36)
                Spacer()
                Text(verbatim: "\(number)")
                    .font(.system(size: 22, weight: .bold, design: .rounded))
                    .foregroundStyle(Color.csSecondary.opacity(0.6))
            }
            Text(title).font(.csHeadline).fixedSize(horizontal: false, vertical: true)
            Text(detail).font(.csCallout).foregroundStyle(Color.csSecondary).fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: 0)
        }
        .frame(maxWidth: .infinity, minHeight: 130, alignment: .topLeading)
        .tile(padding: Theme.space("m"))
    }
}

/// Nino: 8 kutulu kod (telefon doğrulama kodu gibi). Sıradaki kutu mavi çerçeveli.
private struct CodeBoxes: View {
    let pin: String
    let focused: Bool

    var body: some View {
        let digits = Array(pin)
        HStack(spacing: 8) {
            ForEach(0..<8, id: \.self) { i in
                let active = focused && i == min(digits.count, 7)
                Text(verbatim: i < digits.count ? String(digits[i]) : "")
                    .font(.system(size: 26, weight: .semibold, design: .rounded).monospacedDigit())
                    .frame(width: 44, height: 56)
                    .background(RoundedRectangle(cornerRadius: 12, style: .continuous).fill(Color.white.opacity(0.06)))
                    .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .strokeBorder(active ? Color.csAccent : Color.ninoGlassEdge, lineWidth: active ? 2 : 1))
                if i == 3 { Text(verbatim: "–").foregroundStyle(Color.csSecondary) }
            }
        }
        .environment(\.layoutDirection, .leftToRight)
        .contentShape(Rectangle())
    }
}
