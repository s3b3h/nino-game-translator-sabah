// SPDX-License-Identifier: AGPL-3.0-only
// Konsol seçimi (PlayStation varsayılan, Xbox Beta) ve Xbox kurulumu: Microsoft girişi (cihaz kodu) → Xbox seçimi.
// Xbox'ta "İkinci hesap" (PSN) adımı yoktur. Android: ui/XboxScreens.kt.

import SwiftUI
import UIKit

struct PlatformScreen: View {
    @EnvironmentObject private var model: PhoneModel
    var onBack: (() -> Void)?
    var onDone: () -> Void
    @State private var chosen: ConsolePlatform = .playstation

    var body: some View {
        MobileScreen {
            HStack {
                if let onBack { IconButton(symbol: "chevron.left", label: "Back", action: onBack) }
                Spacer()
            }
        } content: {
            ScreenTitle(title: "Your console", message: "Choose the console whose subtitles you want translated. You can change it later in Settings.")
            option(.playstation, title: "PlayStation 5", body: "With Remote Play and a second PSN account.")
            option(.xbox, title: "Xbox", body: "With home streaming and your own Microsoft account. No second account needed.")
            if chosen == .xbox {
                MobileNote(text: String(localized: "Xbox support is in Beta. If something goes wrong, tell us and we'll fix it as soon as we can."),
                           tone: Mobile.Palette.secondary)
            }
        } bottom: {
            Button("Next") {
                model.choosePlatform(chosen)
                onDone()
            }
            .buttonStyle(.mobilePrimary)
        }
        .onAppear { chosen = model.platform }
    }

    private func option(_ platform: ConsolePlatform, title: LocalizedStringKey, body: LocalizedStringKey) -> some View {
        Button { chosen = platform } label: {
            Tile(emphasis: chosen == platform ? .selected : .none) {
                HStack(spacing: Mobile.Space.gap) {
                    MobileTileIcon(symbol: "gamecontroller.fill", tint: chosen == platform ? .accent : .neutral)
                    VStack(alignment: .leading, spacing: Mobile.Space.hair) {
                        HStack(spacing: Mobile.Space.inline) {
                            Text(title).font(Mobile.TypeScale.headline)
                            if platform == .xbox { MobilePill(text: "Beta", kind: .accent) }
                        }
                        Text(body).font(Mobile.TypeScale.caption).foregroundStyle(Mobile.Palette.secondary)
                    }
                    Spacer()
                }
            }
        }
        .buttonStyle(.plain)
    }
}

struct XboxLoginScreen: View {
    @EnvironmentObject private var model: PhoneModel
    var onBack: (() -> Void)?
    var onSkip: (() -> Void)?
    var onDone: () -> Void
    @State private var code: XboxDeviceCode?
    @State private var working = false
    @State private var error: String?
    @State private var task: Task<Void, Never>?
    @State private var copied = false

    var body: some View {
        MobileScreen {
            SetupHeader(step: 1, onBack: onBack, onSkip: onSkip)
        } content: {
            ScreenTitle(caption: "Setup · Step 1/3", title: "Sign in with Microsoft",
                        message: "Sign in with the Microsoft account you use on your Xbox. The phone watches your Xbox home stream; your game keeps running.")
            MobilePill(text: "Beta", kind: .accent)
            if model.xboxSignedIn && code == nil {
                MobilePill(text: String(localized: "Signed in"), kind: .ok, dot: true)
            }
            if code == nil && !working {
                Text("Tap the button to get a code. The Microsoft sign-in page doesn't open inside the app: you enter the code at microsoft.com/link in your browser.")
                    .font(Mobile.TypeScale.caption).foregroundStyle(Mobile.Palette.secondary)
            }
            if let code {
                Tile {
                    Text("Your code (tap to copy):").font(Mobile.TypeScale.caption).foregroundStyle(Mobile.Palette.secondary)
                    Button { copy(code) } label: {
                        Text(verbatim: code.userCode).font(Mobile.TypeScale.display).foregroundStyle(Mobile.Palette.accent)
                    }
                    .buttonStyle(.plain)
                    .accessibilityHint(Text("Copy the code"))
                    Button { open(code) } label: {
                        Text(verbatim: code.verificationURI.replacingOccurrences(of: "https://", with: ""))
                            .font(Mobile.TypeScale.headline).foregroundStyle(Mobile.Palette.accent).underline()
                    }
                    .buttonStyle(.plain)
                    .accessibilityHint(Text("Open the Microsoft page"))
                    Text("1. The code is copied and microsoft.com/link is open in your browser. If it didn't open, tap the link above.\n2. Paste the code, sign in with the Microsoft account you use on your Xbox and allow access.\n3. Come back to Nino; sign-in finishes on its own.")
                        .font(Mobile.TypeScale.caption).foregroundStyle(Mobile.Palette.secondary)
                    if copied { Text("Code copied").font(Mobile.TypeScale.caption).foregroundStyle(Mobile.Palette.success) }
                }
                if working {
                    HStack(spacing: Mobile.Space.inline) {
                        ProgressView().tint(Mobile.Palette.accent)
                        Text("Waiting for you to finish signing in…").font(Mobile.TypeScale.caption).foregroundStyle(Mobile.Palette.secondary)
                    }
                }
            }
            if let error { MobileNote(text: String(format: String(localized: "Couldn't sign in: %@"), error)) }
        } bottom: {
            if let code {
                Button("Open the Microsoft page") { open(code) }.buttonStyle(.mobileGhost)
            }
            Button("Sign in with Microsoft") { begin() }
                .buttonStyle(.mobilePrimary)
                .disabled(working)
        }
        .onDisappear { task?.cancel() }
    }

    private func copy(_ code: XboxDeviceCode) {
        UIPasteboard.general.string = code.userCode
        copied = true
    }

    private func open(_ code: XboxDeviceCode) {
        copy(code)
        if let url = URL(string: code.verificationURI) { UIApplication.shared.open(url) }
    }

    private func begin() {
        task?.cancel()
        error = nil
        working = true
        task = Task {
            defer { working = false }
            do {
                let challenge = try await model.xboxAuth.startDeviceCode()
                code = challenge
                open(challenge)
                _ = try await model.xboxAuth.pollDeviceCode(challenge)
                onDone()
            } catch is CancellationError {
            } catch let failure as XboxError {
                error = XboxText.problem(failure)
                code = nil
            } catch {
                self.error = error.localizedDescription
                code = nil
            }
        }
    }
}

struct XboxConsoleScreen: View {
    @EnvironmentObject private var model: PhoneModel
    var onBack: (() -> Void)?
    var onSkip: (() -> Void)?
    var onSignIn: () -> Void
    var onDone: () -> Void
    @State private var consoles: [XboxConsole]?
    @State private var selected: String?
    @State private var error: String?
    @State private var needsSignIn = false

    private var choice: XboxConsole? { consoles?.first { $0.id == selected && $0.streamingEnabled } }

    var body: some View {
        MobileScreen {
            SetupHeader(step: 2, onBack: onBack, onSkip: onSkip)
        } content: {
            ScreenTitle(caption: "Setup · Step 2/3", title: "Choose your Xbox",
                        message: "The Xboxes on your account. On the Xbox, turn on Settings › Devices & connections › Remote features.")
            if let consoles {
                if consoles.isEmpty && error == nil {
                    MobileNote(text: String(localized: "No Xbox found on this account. Sign in on your Xbox with the same account and turn on remote features."),
                               tone: Mobile.Palette.secondary)
                }
                ForEach(consoles) { console in
                    Button { if console.streamingEnabled { selected = console.id } } label: {
                        Tile(emphasis: selected == console.id ? .selected : .none) {
                            HStack(spacing: Mobile.Space.gap) {
                                MobileTileIcon(symbol: console.streamingEnabled ? "checkmark.circle.fill" : "exclamationmark.triangle.fill",
                                               tint: console.streamingEnabled ? .ok : .danger)
                                VStack(alignment: .leading, spacing: Mobile.Space.hair) {
                                    Text(verbatim: console.name.isEmpty ? console.model : console.name).font(Mobile.TypeScale.headline)
                                    Text(console.streamingEnabled ? "Remote play on" : "Remote play off: turn on Remote features on the Xbox")
                                        .font(Mobile.TypeScale.caption).foregroundStyle(Mobile.Palette.secondary)
                                }
                                Spacer()
                            }
                        }
                    }
                    .buttonStyle(.plain)
                }
            } else {
                Tile { Text("Looking for your Xboxes…").font(Mobile.TypeScale.body).foregroundStyle(Mobile.Palette.secondary) }
            }
            if let error { MobileNote(text: error) }
        } bottom: {
            Button("Search again") { Task { await load() } }.buttonStyle(.mobileGhost)
            if needsSignIn {
                Button("Sign in with Microsoft", action: onSignIn).buttonStyle(.mobilePrimary)
            } else {
                Button("Use this Xbox") {
                    if let choice { model.chooseXbox(choice) }
                    onDone()
                }
                .buttonStyle(.mobilePrimary)
                .disabled(choice == nil)
            }
        }
        .task { await load() }
    }

    private func load() async {
        consoles = nil
        error = nil
        selected = selected ?? model.xboxConsole?.id
        do {
            let list = try await XboxHome(auth: model.xboxAuth).consoles()
            consoles = list
            if selected == nil { selected = list.first { $0.streamingEnabled }?.id }
        } catch let failure as XboxError {
            needsSignIn = failure.kind == .signInRequired
            error = XboxText.problem(failure)
            consoles = []
        } catch {
            self.error = error.localizedDescription
            consoles = []
        }
    }
}

/// Xbox hatalarının ekrandaki anlatımı.
enum XboxText {
    /// Kurulum ekranlarında: anlaşılır neden; beklenmedik yanıtta teknik ayrıntı parantez içinde.
    static func problem(_ error: XboxError) -> String {
        switch error.kind {
        case .signInRequired, .signInDeclined: return String(localized: "Your Microsoft sign-in expired. Sign in again in Settings › Console.")
        case .codeExpired: return String(localized: "The code expired. Try again.")
        case .noXboxAccount: return String(localized: "This Microsoft account has no Xbox profile. Sign in with the account you use on your Xbox.")
        case .network: return String(localized: "Couldn't connect to the internet. Check your connection and try again.")
        default: return String(format: String(localized: "The Xbox service sent an unexpected reply (%@)."), error.message)
        }
    }

    /// Çeviri sürerken oturum durumu.
    static func session(_ kind: XboxErrorKind) -> String {
        switch kind {
        case .signInRequired, .codeExpired, .signInDeclined:
            return String(localized: "Your Microsoft sign-in expired. Sign in again in Settings › Console.")
        case .noXboxAccount: return String(localized: "This Microsoft account has no Xbox profile. Sign in with the account you use on your Xbox.")
        case .consoleUnavailable:
            return String(localized: "Can't reach your Xbox. Is it on, and is remote play enabled in Settings › Devices & connections › Remote features? Retrying…")
        case .busy: return String(localized: "Your Xbox is in another remote play session. Close it; retrying…")
        case .timeout: return String(localized: "Your Xbox didn't answer. Retrying…")
        case .network: return String(localized: "The Xbox connection dropped. Reconnecting…")
        case .service: return String(localized: "The Xbox service sent an unexpected reply. Retrying…")
        }
    }
}
