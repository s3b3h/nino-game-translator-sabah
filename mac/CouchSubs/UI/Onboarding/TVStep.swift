// SPDX-License-Identifier: AGPL-3.0-only

import CouchSubsCore
import SwiftUI

struct TVStep: View {
    @EnvironmentObject private var model: AppModel
    @State private var tvs: [LGTV] = []
    @State private var searching = false
    @State private var working = false
    @State private var error: String?
    /// Bağlanılan TV'nin markası (Samsung'da izin kutusu ayrıca anlatılır).
    @State private var pairingBrand: TVBrand?
    /// Nino: önce "TV'niz hangisi?" diye sorulur; LG/Samsung seçilince ağ taranır.
    @State private var lookingForLGSamsung = false

    var body: some View {
        StepLayout(title: "Connect your TV",
                   message: "Turn on the TV. When you press Connect, the TV asks for permission once — accept it with the remote. If the Nino TV app is missing, this screen helps you install it.") {
            VStack(alignment: .leading, spacing: Theme.space("l")) {
                if let tv = model.tv {
                    DoneLabel(text: tv.name)
                }
                if model.tv == nil && !lookingForLGSamsung && !working {
                    // Önce TV'nin türünü sor.
                    Text("Which TV do you have?").font(.csHeadline).frame(maxWidth: .infinity, alignment: .leading)
                    OptionCard(symbol: "tv.fill", image: "TVOptionAndroid", title: "Android TV / Google TV",
                               detail: "TCL, iFFALCON, Sony, Philips, Vestel, Arçelik, Beko, Grundig and other Android TVs.") {
                        Task { await pair(LGTV(name: "Android TV", host: "", brand: .androidTV)) }
                    }
                    // Nino: PS5 ve Android TV kurulumunun fotoğraflı rehberi (GitHub'da).
                    if model.settings.gameConsole != .xbox {
                        Link(destination: URL(string: "https://github.com/yunusdemirbag/nino-game-translator/blob/main/docs/KURULUM-ANDROID-TV.md")!) {
                            Label("Photo guide for Android TV", systemImage: "photo.on.rectangle")
                                .font(.csCallout.weight(.semibold))
                                .foregroundStyle(Color.csAccentText)
                        }
                        .padding(.leading, Theme.space("xs"))
                    }
                    OptionCard(symbol: "sparkles.tv.fill", image: "TVOptionLGSamsung", title: "LG or Samsung",
                               detail: "LG webOS and Samsung Tizen TVs. Nino finds them on the network.") {
                        lookingForLGSamsung = true
                        Task { await search() }
                    }
                    // TV'si olmayanlar (PS5 monitörde ya da PS Remote Play bilgisayarda): TV kurulumu atlanır.
                    OptionCard(symbol: "desktopcomputer", image: "TVOptionMac", title: "No TV? Show it on this Mac's screen",
                               // Nino: PS5'te oyun bu Mac'te Remote Play ile, Xbox'ta Greenlight ya da xbox.com/play ile oynanır.
                               detail: model.settings.gameConsole == .xbox
                                   ? "You play on this Mac in the Xbox window; subtitles appear on that screen. You can connect a TV later."
                                   : "You play on this Mac with Remote Play; subtitles appear on your Remote Play screen. You can connect a TV later.") {
                        model.useComputerScreen()
                    }
                }
                if lookingForLGSamsung {
                Card {
                    HStack(spacing: Theme.space("m")) {
                        GradientIcon(symbol: "wifi", size: 32)
                        Text("LG and Samsung TVs on this network").font(.csHeadline)
                        if searching { ProgressView().controlSize(.small) }
                        Spacer()
                        Button("Search again") { Task { await search() } }.buttonStyle(.secondary).disabled(searching)
                    }
                    if tvs.isEmpty && !searching {
                        HintText(text: "No LG or Samsung TV found. Make sure the TV is on and on the same network.")
                    }
                    ForEach(tvs, id: \.host) { tv in
                        HStack {
                            Text(verbatim: "\(tv.name) — \(tv.host)")
                            Spacer()
                            Button("Connect") { Task { await pair(tv) } }.buttonStyle(.primary).disabled(working)
                        }
                    }
                }
                    Button { lookingForLGSamsung = false } label: { Label("Choose Another TV", systemImage: "chevron.left") }
                        .buttonStyle(.ghost)
                }
                if working {
                    HStack(spacing: Theme.space("s")) {
                        ProgressView().controlSize(.small)
                        if pairingBrand == .samsung {
                            Text("Accept the permission box on the TV with the remote (Allow). Nino waits 60 seconds.")
                                .foregroundStyle(Color.csSecondary)
                        } else {
                            Text("Accept the request on the TV…").foregroundStyle(Color.csSecondary)
                        }
                    }
                }
                ErrorText(error: error)
                TVAppCard()
                // Uygulamayla TV paketi gelmediyse (geliştirici derlemesi) rehber gösterilir.
                if let tv = model.tv, tv.brand != .lg, !model.canInstallTVApp {
                    Card(title: "Nino TV app") {
                        Text("Install the Nino TV app on this TV using the guide and open it. It finds this computer by itself.")
                        Link("Open the guide", destination: AppIdentity.tvGuideURL)
                    }
                }
            }
        }
        .task {
            // Kurulum yarıda kaldıysa (ör. TV uygulaması kurulurken kapatıldı) eşleşmiş TV'deki uygulamaya yeniden bakılır.
            if model.hasTV, model.tvApp == .unknown { Task { await model.refreshTVApp() } }
            if lookingForLGSamsung { await search() }
        }
    }

    private func search() async {
        searching = true
        tvs = await model.discoverTVs()
        searching = false
    }

    private func pair(_ tv: LGTV) async {
        working = true
        pairingBrand = tv.brand
        error = nil
        do { try await model.pair(tv) } catch { self.error = Self.pairingMessage(for: error, brand: tv.brand) }
        working = false
        pairingBrand = nil
    }

    /// Bağlanamayınca ne yapılacağı. Samsung'da izin kutusu süresinde onaylanmadıysa ya da TV reddettiyse bunu söyler;
    /// önceden hepsi "TV yanıt vermedi" diyordu ve kullanıcı kutu çıkana kadar körlemesine yeniden deniyordu.
    static func pairingMessage(for error: Error, brand: TVBrand) -> String {
        if brand == .samsung, let samsung = error as? SamsungClient.SamsungError {
            switch samsung {
            case .rejected:
                return String(localized: "The TV refused the connection. Allow Nino in Settings › General › External Device Manager › Device Connection Manager › Device List on the TV, then press Connect again.")
            case .cannotConnect:
                return String(localized: "The TV's permission box was not accepted within 60 seconds. If no box appeared, open the TV's home screen and press Connect again. If Nino was denied before, allow it in Settings › General › External Device Manager › Device Connection Manager › Device List.")
            }
        }
        return String(localized: "The TV did not respond. Make sure it is on and on the same network.")
    }
}
