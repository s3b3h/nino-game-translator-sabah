// SPDX-License-Identifier: AGPL-3.0-only

import RemotePlay
import SwiftUI
import WebKit

struct PSNLoginStep: View {
    @EnvironmentObject private var model: AppModel
    @State private var showLogin = false
    @State private var working = false
    @State private var error: String?
    /// Pencere yönlendirmeyi yakaladı mı; yakalamadan kapanırsa kullanıcıya söylenir (eskiden sessizdi).
    @State private var redirected = false
    /// Giriş sayfasının son sorunu (açılamadı, Sony'nin HTTP hatası).
    @State private var pageProblem: String?
    @State private var showManual = false
    @State private var manualId = ""
    @State private var manualError: String?

    var body: some View {
        StepLayout(title: "Sign in with the second account",
                   message: "Sign in to PlayStation Network with the second account you just created. Your password goes directly to Sony; Nino only keeps the account ID.") {
            VStack(alignment: .leading, spacing: Theme.space("m")) {
                if let id = model.accountId {
                    // Giriş yapıldıysa: hangi hesap olduğu ve Çıkış Yap; başka düğme yok.
                    HStack(spacing: Theme.space("m")) {
                        GradientIcon(symbol: "person.crop.circle.badge.checkmark", size: 44)
                        VStack(alignment: .leading, spacing: 2) {
                            Text("Signed in").font(.csHeadline).foregroundStyle(Color.csSuccess)
                            Text(verbatim: String(localized: "PSN account ID") + ": " + Self.masked(id))
                                .font(.csCallout.monospaced()).foregroundStyle(Color.csSecondary)
                        }
                        Spacer()
                        Button("Sign Out") { model.signOutPSN() }.buttonStyle(.danger)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .tile(padding: Theme.space("l"))
                } else {
                    Button("Sign in") {
                        redirected = false
                        pageProblem = nil
                        showLogin = true
                    }
                    .buttonStyle(.primary)
                    .disabled(working)
                    if working { ProgressView().controlSize(.small) }
                    ErrorText(error: error).textSelection(.enabled)
                    manualEntry.padding(.top, Theme.space("s"))
                }
            }
        }
        .sheet(isPresented: $showLogin, onDismiss: sheetClosed) {
            PSNLoginSheet(onRedirect: received, onProblem: { pageProblem = $0 })
        }
    }

    /// Hesap kimliğinin ilk ve son dört karakteri (gerisi gizli).
    static func masked(_ id: Data) -> String {
        let text = id.base64EncodedString()
        guard text.count > 8 else { return text }
        return String(text.prefix(4)) + "••••" + String(text.suffix(4))
    }

    /// Sony girişi açılmıyorsa (ör. servis sağlayıcı engelliyor) hesap kimliği elle yazılır.
    @ViewBuilder private var manualEntry: some View {
        if showManual {
            VStack(alignment: .leading, spacing: Theme.space("s")) {
                HintText(text: "If Sony's sign-in page does not open (some internet providers block it), enter the second account's PSN account ID in base64 (12 characters, e.g. AbCdEfGhIjk=).")
                HStack(spacing: Theme.space("m")) {
                    TextField("", text: $manualId)
                        .textFieldStyle(CSTextFieldStyle())
                        .frame(maxWidth: 240)
                        .onSubmit(saveManual)
                    Button("Save", action: saveManual).buttonStyle(.primary)
                }
                ErrorText(error: manualError)
            }
        } else {
            Button("Enter account ID manually") { showManual = true }.buttonStyle(.secondary)
        }
    }

    private func saveManual() {
        if model.useManualAccountId(manualId) {
            manualError = nil
            error = nil
        } else {
            manualError = String(localized: "This is not a valid account ID. It is 12 characters in base64, e.g. AbCdEfGhIjk=.")
        }
    }

    /// Pencere yönlendirmesiz kapandıysa nedeni söylenir (eskiden sessizce dönülüyordu).
    private func sheetClosed() {
        guard !redirected else { return }
        let failure: Error = model.loginWindowError(problem: pageProblem)
        error = failure.localizedDescription
    }

    private func received(_ url: URL) {
        redirected = true
        showLogin = false
        working = true
        error = nil
        Task {
            do { try await model.completePSNLogin(redirect: url) } catch { self.error = error.localizedDescription }
            working = false
        }
    }
}

/// Sony'nin giriş sayfasını açar; giriş bitince yönlendirme adresini yakalar.
struct PSNLoginSheet: View {
    let onRedirect: (URL) -> Void
    /// Sayfa açılamadı ya da Sony hata kodu döndürdü (nil: sorun giderildi).
    let onProblem: (String?) -> Void
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Text(verbatim: "PlayStation Network").font(.csHeadline)
                Spacer()
                Button("Cancel") { dismiss() }.buttonStyle(.secondary)
            }
            .padding(Theme.space("m"))
            Divider()
            LoginWebView(onRedirect: onRedirect, onProblem: onProblem)
        }
        .frame(width: 520, height: 680)
    }
}
