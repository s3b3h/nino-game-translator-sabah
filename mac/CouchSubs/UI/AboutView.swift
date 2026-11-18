// SPDX-License-Identifier: AGPL-3.0-only
// Nino: Hakkında ekranı. Based on CouchSubs by Sinan Yorulmaz (https://github.com/yorulmazsinan/couchsubs), modified on 2026-11-15.

import CouchSubsCore
import SwiftUI

/// Hakkında penceresi (menüden açılır).
struct AboutView: View {
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        VStack(spacing: Theme.space("l")) {
            NinoCredits()
            Button("Close") { dismiss() }.buttonStyle(.primary).keyboardShortcut(.defaultAction)
        }
        .padding(Theme.space("xxl"))
        .frame(width: 520)
    }
}

/// Logo, sürüm, geliştiren ve destekleyenler, altyapı (İngilizce) ve lisans.
struct NinoCredits: View {
    var body: some View {
        VStack(spacing: Theme.space("l")) {
            VStack(spacing: Theme.space("s")) {
                LogoView(size: 96).shadow(color: Color.csAccent.opacity(0.35), radius: 18)
                Text(verbatim: "Nino Game Translator").font(.system(size: 30, weight: .bold, design: .rounded))
                Text(verbatim: "Version \(AppIdentity.displayVersion)").font(.csCallout).foregroundStyle(Color.csSecondary)
            }

            VStack(spacing: 0) {
                CreditRow(role: "Developer", names: ["Yunus Demirbağ"], symbol: "hammer.fill")
                Divider().padding(.leading, 52)
                CreditRow(role: "Supporters", names: ["M. Akif Demirbağ"], symbol: "heart.fill")
            }
            .ninoGlass(in: RoundedRectangle(cornerRadius: Theme.radius("card"), style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: Theme.radius("card"), style: .continuous).strokeBorder(Color.ninoGlassEdge))

            // Altyapı: bilerek İngilizce. Zincir en temelden başlar: Remote Play (Chiaki → chiaki-ng) → CouchSubs → Nino.
            VStack(alignment: .leading, spacing: Theme.space("m")) {
                Text(verbatim: "Built on").font(.csCallout.weight(.semibold)).foregroundStyle(Color.csSecondary)
                FoundationRow(step: "1", title: "Chiaki — Florian Märkl (2018)",
                              detail: "The original open-source PlayStation Remote Play client. It is the foundation that lets Nino connect to the PS5.",
                              url: "https://git.sr.ht/~thestr4ng3r/chiaki")
                FoundationRow(step: "2", title: "chiaki-ng — Street Pea and contributors",
                              detail: "The actively maintained continuation of Chiaki, used for the Remote Play connection.",
                              url: "https://github.com/streetpea/chiaki-ng")
                FoundationRow(step: "3", title: "CouchSubs",
                              detail: "The subtitle reading and translation app built on chiaki-ng. Nino's code starts from CouchSubs.",
                              url: "https://github.com/yorulmazsinan/couchsubs")
                FoundationRow(step: "4", title: "Nino — Yunus Demirbağ",
                              detail: "New design for the Mac, TV and phone apps, rewritten Turkish texts, subtitle themes, game-aware subtitle reading and voice-aware Turkish dubbing. Modified on 2026-11-15.",
                              url: nil)
                Text(verbatim: "Free and open source under the GNU AGPL-3.0 license. Nino © 2026 Yunus Demirbağ. Based on CouchSubs (© 2026 Sinan Yorulmaz), modified by Yunus Demirbağ on 2026-11-15. Chiaki © Florian Märkl and contributors.")
                    .font(.csCaption).foregroundStyle(Color.csSecondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(Theme.space("l"))
            .ninoGlass(in: RoundedRectangle(cornerRadius: Theme.radius("card"), style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: Theme.radius("card"), style: .continuous).strokeBorder(Color.ninoGlassEdge))

            Text("Nino is not affiliated with Sony Interactive Entertainment. PlayStation and PS5 are trademarks of Sony Interactive Entertainment Inc.")
                .font(.csCaption).foregroundStyle(Color.csSecondary)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
        }
    }
}

private struct CreditRow: View {
    let role: LocalizedStringKey
    let names: [String]
    let symbol: String

    var body: some View {
        HStack(spacing: Theme.space("m")) {
            Image(systemName: symbol)
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(.white)
                .frame(width: 28, height: 28)
                .background(RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .fill(LinearGradient(colors: [Color.csAccentHi, Color(red: 0.0, green: 0.19, blue: 0.52)], startPoint: .top, endPoint: .bottom)))
            Text(role).font(.csBody).foregroundStyle(Color.csSecondary)
            Spacer()
            Text(verbatim: names.joined(separator: ", ")).font(.csBody.weight(.semibold))
        }
        .padding(.horizontal, Theme.space("l"))
        .frame(minHeight: 50)
    }
}

/// "Built on" zincirinin bir halkası: numara, ad, tek cümle, varsa bağlantı.
private struct FoundationRow: View {
    let step: String
    let title: String
    let detail: String
    let url: String?

    var body: some View {
        HStack(alignment: .top, spacing: Theme.space("m")) {
            Text(verbatim: step)
                .font(.system(size: 12, weight: .bold, design: .rounded))
                .foregroundStyle(.white)
                .frame(width: 24, height: 24)
                .background(Circle().fill(LinearGradient(colors: [Color.csAccentHi, Color(red: 0.0, green: 0.19, blue: 0.52)],
                                                         startPoint: .top, endPoint: .bottom)))
            VStack(alignment: .leading, spacing: 2) {
                if let url, let link = URL(string: url) {
                    Link(destination: link) { Text(verbatim: title).font(.csCallout.weight(.semibold)) }
                        .foregroundStyle(Color.csAccentText)
                } else {
                    Text(verbatim: title).font(.csCallout.weight(.semibold))
                }
                Text(verbatim: detail).font(.csCaption).foregroundStyle(Color.csSecondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }
}
