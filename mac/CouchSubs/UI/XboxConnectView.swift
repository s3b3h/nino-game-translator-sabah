// SPDX-License-Identifier: AGPL-3.0-only
// Nino: bu dosya Nino için sıfırdan yazıldı.

import SwiftUI

/// "Xbox'ı Bağla": dört adımlı canlı liste. Her adım Nino Greenlight'ta olanı görünce kendiliğinden yeşile döner;
/// yalnız sıradaki adımın düğmesi görünür, kullanıcı hep tek bir şey yapar.
struct XboxConnectChecklist: View {
    @ObservedObject private var xbox = XboxConnectModel.shared

    var body: some View {
        VStack(spacing: Theme.space("s")) {
            XboxConnectRow(number: 1, symbol: "antenna.radiowaves.left.and.right", state: .manual,
                           title: "Turn On Remote Features on the Xbox",
                           detail: "Settings › Devices & connections › Remote features. Set Xbox app preferences to allow connections from any device.")
            XboxConnectRow(number: 2, symbol: "arrow.down.app.fill", state: state(of: .install),
                           title: xbox.installed ? "Greenlight Is Installed" : "Install Greenlight",
                           detail: "The free Xbox app for Mac. It gives the sharpest picture, so subtitles are read best.") {
                installAction
            }
            XboxConnectRow(number: 3, symbol: "person.crop.circle.badge.checkmark", state: state(of: .signIn),
                           title: xbox.signedIn ? "Signed In to Microsoft" : "Sign In to Microsoft",
                           detail: "Greenlight shows a code. Enter it at microsoft.com/link with the account you use on the Xbox, then press OK in Greenlight.") {
                HStack(spacing: Theme.space("s")) {
                    Button { xbox.openGreenlight() } label: { Label("Open Greenlight", systemImage: "play.fill") }
                        .buttonStyle(CSButtonStyle(kind: .primary))
                    Button { xbox.openLinkPage() } label: { Label("Open microsoft.com/link", systemImage: "arrow.up.right.square") }
                        .buttonStyle(CSButtonStyle(kind: .secondary))
                }
            }
            XboxConnectRow(number: 4, symbol: "play.tv.fill", state: state(of: .stream),
                           title: xbox.streaming ? "Your Xbox Is on This Mac" : "Start Your Xbox",
                           detail: xbox.streaming ? "Nino reads the subtitles from the Greenlight window."
                               : "In Greenlight, pick your Xbox and press Start. If it keeps spinning, close other Xbox streams and allow Greenlight in Privacy & Security › Local Network.") {
                Button { xbox.openGreenlight() } label: { Label("Go to Greenlight", systemImage: "arrow.right.circle.fill") }
                    .buttonStyle(CSButtonStyle(kind: .primary))
            }
        }
        .onAppear { xbox.watch() }
        .onDisappear { xbox.unwatch() }
        .animation(.spring(response: 0.45, dampingFraction: 0.85), value: xbox.step)
    }

    private func state(of step: XboxConnectStep) -> XboxRowState {
        xbox.step > step ? .done : xbox.step == step ? .current : .later
    }

    @ViewBuilder private var installAction: some View {
        if let progress = xbox.installProgress {
            VStack(alignment: .leading, spacing: Theme.space("xs")) {
                ProgressView(value: progress).frame(maxWidth: 320)
                Text("Installing Greenlight… \(Int(progress * 100))%")
                    .font(.csCaption)
                    .foregroundStyle(Color.csSecondary)
                    .monospacedDigit()
            }
        } else {
            VStack(alignment: .leading, spacing: Theme.space("xs")) {
                Button { xbox.install() } label: { Label("Install Greenlight", systemImage: "arrow.down.circle.fill") }
                    .buttonStyle(CSButtonStyle(kind: .primary))
                Text(xbox.installError ?? String(localized: "About 220 MB. Nino downloads it, puts it in Applications and opens it."))
                    .font(.csCaption)
                    .foregroundStyle(xbox.installError == nil ? Color.csSecondary : Color.csDanger)
            }
        }
    }
}

/// Listenin bir satırı: solda numara ya da yeşil tik, ortada başlık ve açıklama, sıradaki adımsa altında düğme.
/// Satırın durumu: elle yapılan, bitti, sıradaki, sonra.
enum XboxRowState { case manual, done, current, later }

struct XboxConnectRow<Action: View>: View {
    let number: Int
    let symbol: String
    let state: XboxRowState
    let title: LocalizedStringKey
    let detail: LocalizedStringKey
    @ViewBuilder var action: Action

    var body: some View {
        HStack(alignment: .top, spacing: Theme.space("m")) {
            badge
            VStack(alignment: .leading, spacing: Theme.space("xs")) {
                HStack(spacing: Theme.space("s")) {
                    Image(systemName: symbol).foregroundStyle(state == .later ? Color.csSecondary : Color.csAccentText)
                    Text(title).font(.csHeadline)
                }
                if state != .done {
                    Text(detail)
                        .font(.csCallout)
                        .foregroundStyle(Color.csSecondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                if state == .current {
                    action.padding(.top, Theme.space("xs"))
                }
            }
            Spacer(minLength: 0)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .tile(padding: Theme.space("m"))
        .overlay(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .strokeBorder(state == .current ? Color.csAccent.opacity(0.7) : .clear, lineWidth: 1.5)
        )
        .opacity(state == .later ? 0.55 : 1)
    }

    @ViewBuilder private var badge: some View {
        ZStack {
            Circle().fill(state == .done ? Color.csSuccess : state == .current ? Color.csAccent : Color.csSecondary.opacity(0.18))
            if state == .done {
                Image(systemName: "checkmark").font(.system(size: 13, weight: .bold)).foregroundStyle(.white)
            } else {
                Text(verbatim: "\(number)")
                    .font(.system(size: 13, weight: .bold, design: .rounded))
                    .foregroundStyle(state == .current ? Color.csOnAccent : Color.csSecondary)
            }
        }
        .frame(width: 26, height: 26)
    }
}

extension XboxConnectRow where Action == EmptyView {
    init(number: Int, symbol: String, state: XboxRowState, title: LocalizedStringKey, detail: LocalizedStringKey) {
        self.init(number: number, symbol: symbol, state: state, title: title, detail: detail) { EmptyView() }
    }
}

/// Ana ekrandan açılan "Xbox'ı Bağla" penceresi.
struct XboxConnectSheet: View {
    @ObservedObject private var xbox = XboxConnectModel.shared
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        VStack(alignment: .leading, spacing: Theme.space("l")) {
            HStack(spacing: Theme.space("s")) {
                GradientIcon(symbol: "gamecontroller.fill", size: 40)
                VStack(alignment: .leading, spacing: 2) {
                    Text("Connect Your Xbox").font(.csTitle)
                    Text("Nino checks each step by itself and moves on.")
                        .font(.csCallout)
                        .foregroundStyle(Color.csSecondary)
                }
                Spacer()
            }
            ScrollView { XboxConnectChecklist() }.scrollIndicators(.never)
            HStack {
                if xbox.step == .done {
                    Label("Connected", systemImage: "checkmark.circle.fill")
                        .font(.csHeadline)
                        .foregroundStyle(Color.csSuccess)
                }
                Spacer()
                Button(xbox.step == .done ? "Done" : "Close") { dismiss() }
                    .buttonStyle(CSButtonStyle(kind: xbox.step == .done ? .primary : .secondary))
                    .keyboardShortcut(.defaultAction)
            }
        }
        .padding(Theme.space("xl"))
        .frame(width: 600, height: 640)
    }
}

/// Ana ekranda, Xbox bağlı değilken çıkan büyük düğme.
struct XboxConnectButton: View {
    @EnvironmentObject private var model: AppModel
    @ObservedObject private var xbox = XboxConnectModel.shared
    @State private var showing = false

    var body: some View {
        Group {
            if model.usesXboxWindow && xbox.step != .done {
                Button { showing = true } label: {
                    Label(xbox.step == .stream ? "Start Your Xbox" : "Connect Your Xbox", systemImage: "gamecontroller.fill")
                        .frame(minWidth: 220)
                }
                .buttonStyle(CSButtonStyle(kind: .primary, height: "buttonLarge"))
            }
        }
        .onAppear { xbox.watch() }
        .onDisappear { xbox.unwatch() }
        .sheet(isPresented: $showing) { XboxConnectSheet().appSurface() }
    }
}
