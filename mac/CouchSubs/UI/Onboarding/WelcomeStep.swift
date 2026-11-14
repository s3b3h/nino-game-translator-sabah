// SPDX-License-Identifier: AGPL-3.0-only
// Nino: hoş geldin ekranı yeniden tasarlandı (2026-11-14).

import SwiftUI

struct WelcomeStep: View {
    var body: some View {
        StepLayout(title: "Welcome to Nino",
                   message: "Nino reads the English subtitles of your PS5 games and shows a Turkish translation on your TV, on top of the game. You keep playing on the TV with your own controller.") {
            VStack(alignment: .leading, spacing: Theme.space("m")) {
                Text("What you need")
                    .font(.csCallout)
                    .foregroundStyle(Color.csSecondary)
                    .textCase(.uppercase)
                    .padding(.leading, Theme.space("xs"))
                HStack(spacing: Theme.space("m")) {
                    RequirementTile(symbol: "gamecontroller.fill", title: "PS5", detail: "On the same Wi-Fi as this Mac")
                    RequirementTile(symbol: "tv.fill", title: "Smart TV",
                                    detail: "Android TV, Google TV, LG or Samsung")
                    RequirementTile(symbol: "person.crop.circle.badge.plus", title: "Second PSN account",
                                    detail: "Free, takes 2 minutes")
                }
                Label("Setup takes about 5 minutes.", systemImage: "clock")
                    .font(.csCallout)
                    .foregroundStyle(Color.csSecondary)
                    .padding(.top, Theme.space("s"))
                    .padding(.leading, Theme.space("xs"))
            }
        }
    }
}

/// Gereksinim karosu: büyük mavi simge, başlık ve tek satırlık açıklama; cam yüzey üzerinde.
private struct RequirementTile: View {
    let symbol: String
    let title: LocalizedStringKey
    let detail: LocalizedStringKey
    @State private var appeared = false

    var body: some View {
        VStack(alignment: .leading, spacing: Theme.space("m")) {
            ZStack {
                Circle()
                    .fill(LinearGradient(colors: [Color.csAccentHi, Color(red: 0.0, green: 0.19, blue: 0.52)],
                                         startPoint: .topLeading, endPoint: .bottomTrailing))
                    .shadow(color: Color.csAccent.opacity(0.4), radius: 10, y: 4)
                icon
                    .font(.system(size: 20, weight: .semibold))
                    .foregroundStyle(.white)
            }
            .frame(width: 48, height: 48)
            VStack(alignment: .leading, spacing: 4) {
                Text(title).font(.csHeadline)
                Text(detail)
                    .font(.csCallout)
                    .foregroundStyle(Color.csSecondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 0)
        }
        .frame(maxWidth: .infinity, minHeight: 150, alignment: .topLeading)
        .tile()
        .scaleEffect(appeared ? 1 : 0.96)
        .opacity(appeared ? 1 : 0)
        .onAppear { withAnimation(.spring(response: 0.5, dampingFraction: 0.8).delay(0.05)) { appeared = true } }
    }

    private var icon: some View { Image(systemName: symbol) }
}
