// SPDX-License-Identifier: AGPL-3.0-only
// Nino: deneme adımı TV önizlemesiyle; düğme TV uygulamasını gerekirse kendisi açar.

import SwiftUI

struct TestStep: View {
    @EnvironmentObject private var model: AppModel
    @State private var sent = false
    @State private var sending = false
    @State private var notSeen = false

    /// TV seçilmediyse ("TV'm yok") örnek altyazı bu bilgisayarın ekranında görünür.
    private var onComputer: Bool { model.settings.output == .computer }

    var body: some View {
        StepLayout(title: "Let's test it",
                   message: onComputer ? "Nino will show a sample subtitle on this computer's screen, at the bottom."
                       : "Nino will send a sample subtitle to your TV. It should appear at the bottom of the screen, on top of the game.") {
            HStack(alignment: .top, spacing: Theme.space("gap")) {
                SubtitleStylePreview(style: model.settings.style, size: CGSize(width: 330, height: 186),
                                     live: (String(localized: "This is a test subtitle. Can you see it on top of the game?"), ""))
                    .overlay(alignment: .topLeading) {
                        if !onComputer {
                            HStack(spacing: 6) {
                                Circle().fill(model.tvClients > 0 ? Color.green : Color.orange).frame(width: 7, height: 7)
                                Text(model.tvClients > 0 ? "TV connected" : "Waiting for the TV app")
                                    .font(.system(size: 11, weight: .semibold)).foregroundStyle(.white)
                            }
                            .padding(.horizontal, 10).frame(height: 24)
                            .background(Capsule().fill(Color.black.opacity(0.45)))
                            .padding(10)
                        }
                    }
                VStack(alignment: .leading, spacing: Theme.space("m")) {
                    Button {
                        sending = true
                        notSeen = false
                        Task {
                            await model.testSubtitle()
                            sending = false
                            sent = true
                        }
                    } label: {
                        HStack(spacing: 8) {
                            if sending { ProgressView().controlSize(.small).tint(.white) }
                            Text(sending ? (onComputer ? "Showing…" : "Opening the TV app…")
                                 : (onComputer ? "Show Test Subtitle" : "Send Test Subtitle to TV"))
                        }
                        .fixedSize()
                    }
                    .buttonStyle(CSButtonStyle(kind: sent ? .secondary : .primary))
                    .disabled(sending)
                    if onComputer {
                        Button("Adjust the subtitle window") { model.overlayAdjusting = true }
                            .buttonStyle(.secondary)
                            .disabled(model.overlayAdjusting)
                    }
                    if sent {
                        Text(onComputer ? "Do you see it on the screen?" : "Do you see it on the TV?").font(.csHeadline)
                        HStack(spacing: Theme.space("m")) {
                            Button("Yes, I see it") {
                                model.overlayAdjusting = false
                                model.advance()
                            }
                            .buttonStyle(.primary)
                            .keyboardShortcut(.defaultAction)
                            Button("No") { notSeen = true }.buttonStyle(.secondary)
                        }
                    }
                    if notSeen {
                        VStack(alignment: .leading, spacing: 6) {
                            Label(onComputer ? "It shows for a few seconds at the bottom of the screen. Send it again."
                                  : "Make sure the TV is on and the Nino TV app is open, then send it again.",
                                  systemImage: "lightbulb.fill")
                                .font(.csCallout)
                                .foregroundStyle(Color.csWarning)
                                .fixedSize(horizontal: false, vertical: true)
                            if !onComputer {
                                Button("Connect the TV Again") { model.step = .tv }.buttonStyle(.ghost)
                            }
                        }
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
    }
}
